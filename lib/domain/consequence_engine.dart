import 'day_shift.dart';

/// A deterministic decision. No RNG state is consumed, so rendering and saves
/// cannot change the outcome of a delayed task.
class ConsequenceDecision {
  final TaskQueue queue;
  final List<TaskConsequence> consequences;
  final List<ShiftEventLedgerEntry> events;
  const ConsequenceDecision(this.queue, this.consequences, this.events);
}

class ConsequenceEngine {
  static const maxDepth = 3;
  static int _roll(int seed, String key) {
    var hash = seed & 0xffffffff;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0xffffffff;
    }
    return hash % 100;
  }

  static ConsequenceDecision evaluate({
    required TaskQueue queue,
    required List<Patient> patients,
    required List<TaskConsequence> previous,
    required List<ShiftEventLedgerEntry> ledger,
    required int seed,
    required int now,
    required int before,
  }) {
    var result = queue;
    final added = <TaskConsequence>[];
    final events = <ShiftEventLedgerEntry>[];
    final seen = {for (final c in previous) c.sourceTaskId: c};
    final latestByKind = <String, int>{};
    for (final e in ledger) {
      if (e.patientId != null) {
        latestByKind['${e.patientId}:${e.eventType}'] = e.occurredAt;
      }
    }
    void generate(
      WorkTask source,
      String trigger,
      String reason,
      List<(String, int, WorkPriority, WorkTaskType)> specs, {
      String severity = 'normal',
    }) {
      if (source.chainDepth >= maxDepth ||
          seen.containsKey(source.taskId) ||
          result.tasks.length > 260) {
        return;
      }
      final ids = <String>[];
      for (var i = 0; i < specs.length; i++) {
        final (title, duration, priority, type) = specs[i];
        final eventType = trigger == 'repeatedCall' ? 'repeatedCall' : trigger;
        final key = '${source.patientId}:$eventType';
        if (i == 0 &&
            source.patientId != null &&
            now - (latestByKind[key] ?? -9999) < 45) {
          return;
        }
        final id = '${source.taskId}-c${source.chainDepth + 1}-$i';
        if (result.tasks.any((t) => t.taskId == id)) continue;
        ids.add(id);
        result = result.add(
          WorkTask(
            taskId: id,
            title:
                '${patients.where((p) => p.patientId == source.patientId).firstOrNull?.bedLabel ?? ''} $title'
                    .trim(),
            patientId: source.patientId,
            createdAt: now,
            scheduledAt: now,
            deadline: now + (priority == WorkPriority.high ? 35 : 90),
            estimatedMinutes: duration,
            priority: priority,
            taskType: type,
            sourceEventId: trigger,
            sourceTaskId: source.taskId,
            parentTaskId: source.taskId,
            chainDepth: source.chainDepth + 1,
            requiredToLeave: false,
          ),
        );
      }
      if (ids.isEmpty) return;
      final id = 'consequence-${source.taskId}-$now';
      final consequence = TaskConsequence(
        id: id,
        sourceTaskId: source.taskId,
        patientId: source.patientId,
        triggerType: trigger,
        triggeredAt: now,
        reason: reason,
        generatedTaskIds: ids,
        severity: severity,
        chainDepth: source.chainDepth + 1,
      );
      added.add(consequence);
      seen[source.taskId] = consequence;
      events.add(
        ShiftEventLedgerEntry(
          eventId: id,
          eventType: trigger,
          patientId: source.patientId,
          occurredAt: now,
          sourceTaskId: source.taskId,
          parentEventId: source.sourceEventId,
          chainDepth: source.chainDepth + 1,
        ),
      );
      if (source.patientId != null) {
        latestByKind['${source.patientId}:$trigger'] = now;
      }
    }

    for (final source in queue.tasks) {
      final pending = {
        WorkTaskStatus.pending,
        WorkTaskStatus.interrupted,
        WorkTaskStatus.inProgress,
      }.contains(source.status);
      final delay = now - (source.scheduledAt ?? source.createdAt);
      final patient = patients
          .where((p) => p.patientId == source.patientId)
          .firstOrNull;
      if (pending &&
          source.title.contains('排泄介助') &&
          delay >= 65 &&
          patient != null &&
          _roll(seed, source.taskId) <
              (patient.adl == AdlLevel.fullAssist ? 80 : 55)) {
        generate(source, 'postponedTooLong', '排泄介助の遅延', [
          ('失禁対応', 12, WorkPriority.high, WorkTaskType.dynamic),
        ]);
      } else if (source.title.contains('失禁対応') &&
          source.status == WorkTaskStatus.completed &&
          _roll(seed, '${source.taskId}-followup') < 75) {
        generate(source, 'dependencyDelayed', '失禁対応後のケア', [
          ('更衣', 8, WorkPriority.normal, WorkTaskType.dynamic),
          ('寝具交換', 10, WorkPriority.normal, WorkTaskType.dynamic),
          ('失禁対応の記録', 5, WorkPriority.normal, WorkTaskType.documentation),
        ]);
      } else if (pending &&
          source.sourceEventId == 'call' &&
          delay >= 35 &&
          _roll(seed, source.taskId) < 80) {
        generate(source, 'repeatedCall', 'ナースコール未対応', [
          ('ナースコール再入電', 5, WorkPriority.high, WorkTaskType.dynamic),
          if (_roll(seed, '${source.taskId}-need') < 55)
            (
              patient?.severity == PatientSeverity.high
                  ? '疼痛対応'
                  : patient?.adl == AdlLevel.fullAssist
                  ? 'センサーマット確認'
                  : patient?.needsToileting == true
                  ? 'トイレ介助'
                  : '家族からの確認',
              8,
              WorkPriority.normal,
              WorkTaskType.dynamic,
            ),
        ]);
      } else if (pending &&
          (source.title.contains('点滴') || source.title.contains('輸液')) &&
          source.deadline != null &&
          now - source.deadline! >= 30 &&
          _roll(seed, source.taskId) < 70) {
        generate(source, 'deadlineExceeded', '点滴確認の期限超過', [
          ('滴下確認', 5, WorkPriority.high, WorkTaskType.dynamic),
          ('閉塞・ルート確認', 7, WorkPriority.high, WorkTaskType.dynamic),
          if (patient?.severity == PatientSeverity.high)
            ('医師報告', 6, WorkPriority.normal, WorkTaskType.dynamic),
        ]);
      } else if (pending &&
          source.title.contains('検査') &&
          delay >= 40 &&
          _roll(seed, source.taskId) < 75) {
        generate(source, 'dependencyDelayed', '検査対応の遅延', [
          ('検査室から確認電話', 5, WorkPriority.high, WorkTaskType.dynamic),
          ('時間再調整', 5, WorkPriority.normal, WorkTaskType.dynamic),
          ('患者準備確認', 6, WorkPriority.normal, WorkTaskType.dynamic),
        ]);
      } else if (pending &&
          source.sourceEventId == 'order' &&
          delay >= 45 &&
          _roll(seed, source.taskId) < 75) {
        generate(source, 'postponedTooLong', '追加指示の進捗確認', [
          (
            '先生から「さっきお願いした件どうなりました？」',
            4,
            WorkPriority.normal,
            WorkTaskType.dynamic,
          ),
        ]);
      } else if (pending &&
          source.title.contains('食事介助') &&
          delay >= 40 &&
          _roll(seed, source.taskId) < 60) {
        generate(source, 'dependencyDelayed', '食事介助の遅延', [
          ('食事摂取量確認', 5, WorkPriority.normal, WorkTaskType.dynamic),
          ('内服確認', 4, WorkPriority.normal, WorkTaskType.dynamic),
        ]);
      }
    }
    for (final boundary in [690, 765, 930, 1020]) {
      if (before < boundary && now >= boundary) {
        final open = result.pending
            .where((t) => t.taskType != WorkTaskType.documentation)
            .length;
        if (boundary == 930 && open >= 8) {
          final source = result.tasks.firstWhere(
            (t) => t.taskId == 'afternoon_handoff',
          );
          generate(source, 'phaseBoundary', '申し送り前の未完了ケア', [
            ('未完了ケアの申し送り整理', 8, WorkPriority.normal, WorkTaskType.dynamic),
          ]);
        }
        if ((boundary == 930 || boundary == 1020) &&
            result.documentationBacklog) {
          events.add(
            ShiftEventLedgerEntry(
              eventId: 'backlog-$boundary',
              eventType: 'documentationBacklog',
              occurredAt: boundary,
            ),
          );
        }
      }
    }
    return ConsequenceDecision(result, added, events);
  }
}
