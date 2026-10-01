import 'day_shift.dart';
import 'models.dart';

int eventRandom(int value) {
  var n = value;
  n ^= (n << 13) & 0xffffffff;
  n ^= n >>> 17;
  n ^= (n << 5) & 0xffffffff;
  return n & 0xffffffff;
}

/// The clock and RNG live in the saved domain state. One roll is made per
/// elapsed minute, so rendering frequency never changes the event sequence.
class DynamicEventEngine {
  static GameState advance(GameState state, {bool force = false}) {
    final shift = state.unifiedShift;
    if (shift == null || state.workQueue == null) return state;
    var result = state;
    final first = force ? state.timeMinutes : shift.lastEventMinute + 1;
    for (var minute = first; minute <= state.timeMinutes; minute++) {
      if (minute > 1020 || minute < 510) continue;
      final s = result.unifiedShift!;
      var rng = eventRandom(result.rngState);
      final candidates = <(String, Patient, int)>[];
      for (final p in s.patients) {
        final assistance = p.adl == AdlLevel.fullAssist
            ? 3
            : p.adl == AdlLevel.partialAssist
            ? 2
            : 1;
        candidates.add((
          'call',
          p,
          2 * assistance + (p.needsToileting ? 2 : 0),
        ));
        if (p.needsToileting) {
          candidates.add((
            'toileting',
            p,
            (minute >= 690 && minute < 840 ? 5 : 3) * assistance,
          ));
        }
        if (p.hasInfusion) candidates.add(('infusion', p, 5));
        if (p.hasExamination && minute >= 570 && minute < 900) {
          candidates.add(('examination', p, 4));
        }
        candidates.add(('order', p, 2));
        candidates.add(('family', p, 1));
        candidates.add((
          'emergency',
          p,
          p.severity == PatientSeverity.high
              ? 2
              : p.severity == PatientSeverity.watch
              ? 1
              : 0,
        ));
      }
      if (s.patients.length < 7 && minute >= 690 && minute < 960) {
        candidates.add(('admission', s.patients.first, 2));
      }
      final total = candidates.fold<int>(0, (sum, item) => sum + item.$3);
      // Approximately one roll every 20 minutes. The weighted pool changes
      // with patient attributes and the time of day.
      final threshold = force ? 10000 : 480;
      if (rng % 10000 < threshold && total > 0) {
        rng = eventRandom(rng);
        var pick = rng % total;
        var chosen = candidates.last;
        for (final item in candidates) {
          pick -= item.$3;
          if (pick < 0) {
            chosen = item;
            break;
          }
        }
        final serial = s.interruptSerial + 1;
        final kind = chosen.$1;
        var patient = chosen.$2;
        var patients = s.patients;
        if (kind == 'admission') {
          patient = Patient(
            patientId: 'admission-$serial',
            bedLabel: '305-${s.patients.length - 5}',
            severity: PatientSeverity.watch,
            adl: AdlLevel.partialAssist,
            hasInfusion: rng.isEven,
            hasExamination: false,
            hasScheduledMedication: true,
            needsToileting: true,
            needsMealAssistance: false,
          );
          patients = List.unmodifiable([...patients, patient]);
        }
        final urgent = kind == 'emergency';
        final high = urgent || kind == 'infusion' || kind == 'examination';
        final title = switch (kind) {
          'call' => 'ナースコール',
          'toileting' => '突発の排泄介助',
          'infusion' => '点滴アラーム・交換',
          'examination' => '検査室から呼び出し',
          'order' => '医師から追加指示',
          'family' => '家族対応',
          'emergency' => '急変対応',
          _ => '新規入院対応',
        };
        final id = 'dynamic-$serial';
        var queue = result.workQueue!.add(
          WorkTask(
            taskId: id,
            title: '${patient.bedLabel} $title',
            patientId: patient.patientId,
            createdAt: minute,
            scheduledAt: minute,
            deadline:
                minute +
                (urgent
                    ? 12
                    : high
                    ? 25
                    : 50),
            estimatedMinutes: urgent
                ? 16
                : kind == 'admission'
                ? 14
                : 5 + rng % 8,
            priority: urgent
                ? WorkPriority.urgent
                : high
                ? WorkPriority.high
                : WorkPriority.normal,
            taskType: WorkTaskType.dynamic,
            sourceEventId: kind,
            documentationMinutes: kind == 'order' || kind == 'admission'
                ? 0
                : 4,
            requiredToLeave: urgent,
          ),
        );
        if (kind == 'admission') {
          for (final (suffix, label, duration) in [
            ('check', '初期確認', 9),
            ('care', '必要なケア', 12),
            ('record', '入院記録', 7),
          ]) {
            queue = queue.add(
              WorkTask(
                taskId: '$id-$suffix',
                title: '${patient.bedLabel} $label',
                patientId: patient.patientId,
                createdAt: minute,
                scheduledAt: minute,
                deadline: minute + 75,
                estimatedMinutes: duration,
                priority: WorkPriority.high,
                taskType: suffix == 'record'
                    ? WorkTaskType.documentation
                    : WorkTaskType.dynamic,
                sourceEventId: kind,
                sourceTaskId: id,
                chainDepth: 1,
                documentationMinutes: suffix == 'care' ? 3 : 0,
                requiredToLeave: false,
              ),
            );
          }
        }
        final active = s.activeTaskId;
        var remaining = s.activeTaskRemaining;
        if (active != null && high) {
          final current = queue.tasks.firstWhere((t) => t.taskId == active);
          queue = queue.replace(
            current.copyWith(
              status: WorkTaskStatus.interrupted,
              remainingDuration: remaining,
              interruptionCount: current.interruptionCount + 1,
              interruptedAt: minute,
            ),
          );
        }
        result = result.copyWith(
          rngState: rng,
          workQueue: queue,
          unifiedShift: s.copyWith(
            patients: patients,
            interruptSerial: serial,
            lastInterruptAt: minute,
            notice: '${urgent ? '🚨 ' : ''}${patient.bedLabel} $title　Queueに追加',
          ),
          counters: result.counters.add(
            callCount: kind == 'call' ? 1 : 0,
            admissionCount: kind == 'admission' ? 1 : 0,
            acuteChangeCount: urgent ? 1 : 0,
          ),
        );
      } else {
        result = result.copyWith(rngState: rng);
      }
    }
    return result.copyWith(
      unifiedShift: result.unifiedShift!.copyWith(
        lastEventMinute: state.timeMinutes,
      ),
    );
  }
}
