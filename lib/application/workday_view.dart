import '../domain/day_shift.dart';
import '../domain/models.dart';

String clockLabel(int minute) {
  final day = minute ~/ 1440;
  final time =
      '${((minute % 1440) ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  return day == 0 ? time : '${day == 1 ? '翌' : '$day日後'} $time';
}

String durationLabel(int minutes) => minutes >= 60
    ? '${minutes ~/ 60}時間${minutes % 60 == 0 ? '' : '${minutes % 60}分'}'
    : '$minutes分';

String taskPriorityLabel(WorkTask task) => switch (task.priority) {
  WorkPriority.urgent => '緊急',
  WorkPriority.high => '高優先度',
  WorkPriority.normal => '通常',
  WorkPriority.low => '低優先度',
};

String taskStatusLabel(WorkTask task) => switch (task.status) {
  WorkTaskStatus.interrupted => '中断中・${task.interruptionCount}回中断',
  WorkTaskStatus.inProgress => '処理中',
  WorkTaskStatus.pending => '未着手',
  WorkTaskStatus.completed => '完了',
  WorkTaskStatus.handedOff => '引き継ぎ済み',
  WorkTaskStatus.expired => '期限切れ',
};

bool canHandOff(WorkTask task) =>
    task.status == WorkTaskStatus.pending &&
    task.taskType != WorkTaskType.documentation &&
    !task.requiredToLeave &&
    task.priority != WorkPriority.urgent;

class QueueOverview {
  final int total, care, records, interrupted, other, urgent;
  const QueueOverview(
    this.total,
    this.care,
    this.records,
    this.interrupted,
    this.other,
    this.urgent,
  );

  factory QueueOverview.from(TaskQueue queue) {
    final pending = queue.pending;
    final interrupted = pending
        .where((t) => t.status == WorkTaskStatus.interrupted)
        .length;
    final records = pending
        .where(
          (t) =>
              t.taskType == WorkTaskType.documentation &&
              t.status != WorkTaskStatus.interrupted,
        )
        .length;
    final care = pending
        .where(
          (t) =>
              t.taskType == WorkTaskType.routine &&
              t.status != WorkTaskStatus.interrupted,
        )
        .length;
    return QueueOverview(
      pending.length,
      care,
      records,
      interrupted,
      pending.length - care - records - interrupted,
      queue.urgent.length,
    );
  }
}

class DaySummary {
  final int finishTime,
      overtimeMinutes,
      completed,
      handedOff,
      undocumented,
      overdue,
      events,
      interruptions,
      patientsStart,
      patientsEnd;
  final Map<String, int> eventCounts;
  final List<({int at, String title})> timeline;
  final int consequenceCount,
      cascadeCount,
      repeatedCallCount,
      missedBreakMinutes,
      interruptedBreakCount;
  final List<String> majorCascades;
  final bool documentationOvertime;

  const DaySummary({
    required this.finishTime,
    required this.overtimeMinutes,
    required this.completed,
    required this.handedOff,
    required this.undocumented,
    required this.overdue,
    required this.events,
    required this.interruptions,
    required this.patientsStart,
    required this.patientsEnd,
    required this.eventCounts,
    required this.timeline,
    this.consequenceCount = 0,
    this.cascadeCount = 0,
    this.repeatedCallCount = 0,
    this.missedBreakMinutes = 0,
    this.interruptedBreakCount = 0,
    this.majorCascades = const [],
    this.documentationOvertime = false,
  });

  factory DaySummary.fromState(GameState state) {
    final queue = state.workQueue!;
    final roots =
        queue.tasks
            .where(
              (t) =>
                  t.taskId.startsWith('dynamic-') &&
                  !t.taskId.substring('dynamic-'.length).contains('-') &&
                  t.sourceEventId != null,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final counts = <String, int>{};
    final ledger = state.unifiedShift!.eventLedger;
    if (ledger.isNotEmpty) {
      for (final event in ledger.where(
        (e) => e.eventId.startsWith('dynamic-'),
      )) {
        counts.update(event.eventType, (n) => n + 1, ifAbsent: () => 1);
      }
    } else {
      for (final task in roots) {
        counts.update(task.sourceEventId!, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final major = roots
        .where(
          (t) =>
              t.sourceEventId == 'emergency' ||
              t.sourceEventId == 'admission' ||
              t.priority == WorkPriority.urgent,
        )
        .take(7);
    return DaySummary(
      finishTime: state.timeMinutes,
      overtimeMinutes: state.workStatus!.overtimeMinutes,
      completed: queue.completed.length,
      handedOff: queue.handedOff.length,
      undocumented: queue.documentationCount,
      overdue: queue.tasks
          .where(
            (t) =>
                t.deadline != null &&
                (t.status == WorkTaskStatus.handedOff
                    ? t.handedOffAt! > t.deadline!
                    : t.status != WorkTaskStatus.completed &&
                          state.timeMinutes > t.deadline!),
          )
          .length,
      events: ledger.isEmpty
          ? state.unifiedShift!.interruptSerial
          : ledger.where((e) => e.eventId.startsWith('dynamic-')).length,
      interruptions: ledger.isEmpty
          ? queue.tasks.fold(0, (int n, t) => n + t.interruptionCount)
          : ledger.where((e) => e.wasInterruption).length,
      patientsStart: state.unifiedShift!.patients
          .where((p) => !p.patientId.startsWith('admission-'))
          .length,
      patientsEnd: state.unifiedShift!.patients.length,
      eventCounts: counts,
      consequenceCount: state.unifiedShift!.consequences.length,
      cascadeCount: state.unifiedShift!.consequences
          .where((c) => c.chainDepth > 1)
          .length,
      repeatedCallCount: state.unifiedShift!.consequences
          .where((c) => c.triggerType == 'repeatedCall')
          .length,
      missedBreakMinutes:
          (30 -
                  (state.unifiedShift!.consequencesEnabled
                      ? state.unifiedShift!.breakMinutesTaken
                      : state.counters.breakMinutes))
              .clamp(0, 30),
      documentationOvertime:
          state.timeMinutes > 1020 &&
          ledger.any((e) => e.eventId == 'backlog-1020'),
      interruptedBreakCount: state.unifiedShift!.interruptedBreakCount,
      majorCascades: state.unifiedShift!.consequences
          .take(5)
          .map(
            (c) =>
                '${c.reason} → ${c.generatedTaskIds.map((id) => queue.tasks.firstWhere((t) => t.taskId == id).title).join(' → ')}',
          )
          .toList(),
      timeline: [
        (at: 510, title: '朝申し送り'),
        if (ledger.isNotEmpty)
          for (final e
              in ledger
                  .where((e) => e.isEmergency || e.eventType == 'admission')
                  .take(7))
            (at: e.occurredAt, title: e.eventType)
        else
          for (final t in major) (at: t.createdAt, title: t.title),
        (at: 1020, title: '定時'),
        (at: state.timeMinutes, title: '退勤'),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'finishTime': finishTime,
    'overtimeMinutes': overtimeMinutes,
    'completed': completed,
    'handedOff': handedOff,
    'undocumented': undocumented,
    'overdue': overdue,
    'events': events,
    'interruptions': interruptions,
    'patientsStart': patientsStart,
    'patientsEnd': patientsEnd,
    'eventCounts': eventCounts,
    'timeline': timeline.map((e) => {'at': e.at, 'title': e.title}).toList(),
    'consequenceCount': consequenceCount,
    'cascadeCount': cascadeCount,
    'repeatedCallCount': repeatedCallCount,
    'missedBreakMinutes': missedBreakMinutes,
    'interruptedBreakCount': interruptedBreakCount,
    'majorCascades': majorCascades,
    'documentationOvertime': documentationOvertime,
  };

  factory DaySummary.fromJson(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    return DaySummary(
      finishTime: m['finishTime'] as int,
      overtimeMinutes: m['overtimeMinutes'] as int,
      completed: m['completed'] as int,
      handedOff: m['handedOff'] as int,
      undocumented: m['undocumented'] as int,
      overdue: m['overdue'] as int,
      events: m['events'] as int,
      interruptions: m['interruptions'] as int,
      patientsStart: m['patientsStart'] as int,
      patientsEnd: m['patientsEnd'] as int,
      eventCounts: Map<String, int>.from(m['eventCounts'] as Map),
      consequenceCount: m['consequenceCount'] as int? ?? 0,
      cascadeCount: m['cascadeCount'] as int? ?? 0,
      repeatedCallCount: m['repeatedCallCount'] as int? ?? 0,
      missedBreakMinutes: m['missedBreakMinutes'] as int? ?? 0,
      interruptedBreakCount: m['interruptedBreakCount'] as int? ?? 0,
      majorCascades: List<String>.from(m['majorCascades'] as List? ?? const []),
      documentationOvertime: m['documentationOvertime'] as bool? ?? false,
      timeline: (m['timeline'] as List).map((e) {
        final item = Map<String, dynamic>.from(e as Map);
        return (at: item['at'] as int, title: item['title'] as String);
      }).toList(),
    );
  }
}
