import 'dart:collection';

enum ShiftPhase {
  morningHandoff,
  morningCare,
  lunchCare,
  breakTime,
  afternoonCare,
  afternoonHandoff,
  remainingWork,
  overtime,
}

enum WorkTaskType { routine, dynamic, documentation }

enum WorkTaskStatus { pending, completed, expired }

enum WorkPriority { urgent, high, normal, low }

enum DeadlineState { comfortable, approaching, overdue }

class DayShiftConfig {
  final int lunchStart, afternoonStart, handoffStart, handoffEnd, finish;
  const DayShiftConfig({
    this.lunchStart = 690,
    this.afternoonStart = 780,
    this.handoffStart = 930,
    this.handoffEnd = 950,
    this.finish = 1020,
  });
}

ShiftPhase phaseAt(
  int minute, {
  DayShiftConfig config = const DayShiftConfig(),
  bool lunchDone = false,
  bool breakDone = false,
}) {
  if (minute >= config.finish) return ShiftPhase.overtime;
  if (minute >= config.handoffEnd) return ShiftPhase.remainingWork;
  if (minute >= config.handoffStart) return ShiftPhase.afternoonHandoff;
  if (minute >= config.afternoonStart) return ShiftPhase.afternoonCare;
  if (minute >= config.lunchStart) {
    if (!lunchDone) return ShiftPhase.lunchCare;
    if (!breakDone) return ShiftPhase.breakTime;
    return ShiftPhase.afternoonCare;
  }
  if (minute >= 530) return ShiftPhase.morningCare;
  return ShiftPhase.morningHandoff;
}

String phaseLabel(ShiftPhase phase) => switch (phase) {
  ShiftPhase.morningHandoff => '朝の申し送り',
  ShiftPhase.morningCare => '午前のケア',
  ShiftPhase.lunchCare => '昼食業務',
  ShiftPhase.breakTime => '休憩可能',
  ShiftPhase.afternoonCare => '午後のケア',
  ShiftPhase.afternoonHandoff => '午後の申し送り',
  ShiftPhase.remainingWork => '残務処理',
  ShiftPhase.overtime => '定時到達・残務処理',
};

class WorkTask {
  final String taskId, title;
  final int createdAt, estimatedMinutes, documentationMinutes;
  final int? scheduledAt, deadline;
  final WorkPriority priority;
  final WorkTaskStatus status;
  final WorkTaskType taskType;
  final String? sourceEventId, patientId, parentTaskId, routineCategory;
  final ShiftPhase? shiftPhase;
  const WorkTask({
    required this.taskId,
    required this.title,
    required this.createdAt,
    this.scheduledAt,
    this.deadline,
    required this.estimatedMinutes,
    this.priority = WorkPriority.normal,
    this.status = WorkTaskStatus.pending,
    required this.taskType,
    this.sourceEventId,
    this.patientId,
    this.documentationMinutes = 0,
    this.parentTaskId,
    this.routineCategory,
    this.shiftPhase,
  });
  WorkTask copyWith({WorkTaskStatus? status}) => WorkTask(
    taskId: taskId,
    title: title,
    createdAt: createdAt,
    scheduledAt: scheduledAt,
    deadline: deadline,
    estimatedMinutes: estimatedMinutes,
    priority: priority,
    status: status ?? this.status,
    taskType: taskType,
    sourceEventId: sourceEventId,
    patientId: patientId,
    documentationMinutes: documentationMinutes,
    parentTaskId: parentTaskId,
    routineCategory: routineCategory,
    shiftPhase: shiftPhase,
  );
  factory WorkTask.fromJson(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    return WorkTask(
      taskId: m['taskId'] as String,
      title: m['title'] as String,
      createdAt: m['createdAt'] as int,
      scheduledAt: m['scheduledAt'] as int?,
      deadline: m['deadline'] as int?,
      estimatedMinutes: m['estimatedMinutes'] as int,
      priority: WorkPriority.values.byName(m['priority'] as String),
      status: WorkTaskStatus.values.byName(m['status'] as String),
      taskType: WorkTaskType.values.byName(m['taskType'] as String),
      sourceEventId: m['sourceEventId'] as String?,
      patientId: m['patientId'] as String?,
      documentationMinutes: m['documentationMinutes'] as int? ?? 0,
      parentTaskId: m['parentTaskId'] as String?,
      routineCategory: m['routineCategory'] as String?,
      shiftPhase: m['shiftPhase'] == null
          ? null
          : ShiftPhase.values.byName(m['shiftPhase'] as String),
    );
  }
  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'title': title,
    'createdAt': createdAt,
    'scheduledAt': scheduledAt,
    'deadline': deadline,
    'estimatedMinutes': estimatedMinutes,
    'priority': priority.name,
    'status': status.name,
    'taskType': taskType.name,
    'sourceEventId': sourceEventId,
    'patientId': patientId,
    'documentationMinutes': documentationMinutes,
    'parentTaskId': parentTaskId,
    'routineCategory': routineCategory,
    'shiftPhase': shiftPhase?.name,
  };
}

DeadlineState deadlineState(WorkTask task, int now, {int warningMinutes = 20}) {
  if (task.deadline == null) return DeadlineState.comfortable;
  if (now > task.deadline!) return DeadlineState.overdue;
  if (task.deadline! - now <= warningMinutes) return DeadlineState.approaching;
  return DeadlineState.comfortable;
}

class TaskQueue {
  final List<WorkTask> tasks;
  TaskQueue(Iterable<WorkTask> tasks)
    : tasks = UnmodifiableListView(tasks.toList()) {
    if (this.tasks.map((t) => t.taskId).toSet().length != this.tasks.length) {
      throw ArgumentError('Duplicate taskId');
    }
  }
  factory TaskQueue.fromJson(dynamic raw) =>
      TaskQueue((raw as List).map(WorkTask.fromJson));
  List<Map<String, dynamic>> toJson() => tasks.map((t) => t.toJson()).toList();
  TaskQueue add(WorkTask task) => TaskQueue([...tasks, task]);
  List<WorkTask> get pending =>
      _sorted(tasks.where((t) => t.status == WorkTaskStatus.pending));
  List<WorkTask> get completed =>
      tasks.where((t) => t.status == WorkTaskStatus.completed).toList();
  List<WorkTask> overdue(int now) => pending
      .where((t) => deadlineState(t, now) == DeadlineState.overdue)
      .toList();
  List<WorkTask> get urgent =>
      pending.where((t) => t.priority == WorkPriority.urgent).toList();
  List<WorkTask> get routine =>
      tasks.where((t) => t.taskType == WorkTaskType.routine).toList();
  List<WorkTask> get dynamicTasks =>
      tasks.where((t) => t.taskType == WorkTaskType.dynamic).toList();
  List<WorkTask> get documentation =>
      tasks.where((t) => t.taskType == WorkTaskType.documentation).toList();
  int get pendingCount => pending.length;
  int get documentationCount =>
      pending.where((t) => t.taskType == WorkTaskType.documentation).length;
  List<WorkTask> _sorted(Iterable<WorkTask> source) =>
      source.toList()..sort((a, b) {
        final priority = a.priority.index.compareTo(b.priority.index);
        if (priority != 0) return priority;
        final deadline = (a.deadline ?? 99999).compareTo(b.deadline ?? 99999);
        if (deadline != 0) return deadline;
        final scheduled = (a.scheduledAt ?? 99999).compareTo(
          b.scheduledAt ?? 99999,
        );
        if (scheduled != 0) return scheduled;
        return a.createdAt.compareTo(b.createdAt);
      });
  TaskQueue complete(String id, int now) {
    final task = tasks.firstWhere((t) => t.taskId == id);
    if (task.status != WorkTaskStatus.pending) {
      throw StateError('Task already handled');
    }
    final result = tasks
        .map(
          (t) =>
              t.taskId == id ? t.copyWith(status: WorkTaskStatus.completed) : t,
        )
        .toList();
    if (task.documentationMinutes > 0) {
      result.add(
        WorkTask(
          taskId: '$id-documentation',
          title: '${task.title}の記録',
          createdAt: now,
          estimatedMinutes: task.documentationMinutes,
          taskType: WorkTaskType.documentation,
          parentTaskId: id,
          sourceEventId: task.sourceEventId,
          patientId: task.patientId,
        ),
      );
    }
    return TaskQueue(result);
  }
}

TaskQueue generateRoutineTasks({
  DayShiftConfig config = const DayShiftConfig(),
}) {
  final specs = <(String, String, int, int, ShiftPhase, int)>[
    ('morning_handoff', '朝の申し送り', 510, 20, ShiftPhase.morningHandoff, 0),
    ('morning_vitals', '午前の検温', 530, 15, ShiftPhase.morningCare, 6),
    ('morning_iv', '点滴関連業務', 545, 20, ShiftPhase.morningCare, 5),
    ('morning_diaper', 'おむつ交換', 565, 20, ShiftPhase.morningCare, 4),
    ('morning_hygiene', '清潔ケア', 585, 25, ShiftPhase.morningCare, 6),
    ('orders', '指示受け・確認', 610, 10, ShiftPhase.morningCare, 0),
    ('medication', '内服管理', 620, 15, ShiftPhase.morningCare, 4),
    ('doctor_assist', '医師処置の介助', 635, 20, ShiftPhase.morningCare, 5),
    ('lunch_serve', '昼食の配膳', config.lunchStart, 10, ShiftPhase.lunchCare, 0),
    (
      'lunch_assist',
      '食事介助',
      config.lunchStart + 10,
      20,
      ShiftPhase.lunchCare,
      5,
    ),
    (
      'lunch_medication',
      '昼の内服',
      config.lunchStart + 30,
      10,
      ShiftPhase.lunchCare,
      4,
    ),
    ('lunch_clear', '下膳', config.lunchStart + 40, 10, ShiftPhase.lunchCare, 0),
    ('break', '休憩', config.lunchStart + 50, 45, ShiftPhase.breakTime, 0),
    (
      'afternoon_vitals',
      '午後の検温',
      config.afternoonStart,
      15,
      ShiftPhase.afternoonCare,
      6,
    ),
    (
      'afternoon_diaper',
      '午後のおむつ交換',
      config.afternoonStart + 15,
      20,
      ShiftPhase.afternoonCare,
      4,
    ),
    (
      'afternoon_handoff',
      '午後の申し送り',
      config.handoffStart,
      20,
      ShiftPhase.afternoonHandoff,
      0,
    ),
  ];
  return TaskQueue(
    specs.map(
      (s) => WorkTask(
        taskId: s.$1,
        title: s.$2,
        createdAt: 510,
        scheduledAt: s.$3,
        estimatedMinutes: s.$4,
        deadline: s.$1 == 'afternoon_handoff' ? config.handoffEnd : null,
        taskType: WorkTaskType.routine,
        routineCategory: s.$1,
        shiftPhase: s.$5,
        documentationMinutes: s.$6,
      ),
    ),
  );
}

WorkTask infusionTask(String id, int at) => WorkTask(
  taskId: id,
  title: '点滴交換',
  createdAt: at,
  scheduledAt: at,
  deadline: at + 20,
  estimatedMinutes: 10,
  priority: WorkPriority.high,
  taskType: WorkTaskType.dynamic,
  documentationMinutes: 5,
);
WorkTask examinationTask(String id, int at) => WorkTask(
  taskId: id,
  title: '検査対応',
  createdAt: at,
  scheduledAt: at,
  deadline: at + 30,
  estimatedMinutes: 20,
  priority: WorkPriority.high,
  taskType: WorkTaskType.dynamic,
  documentationMinutes: 5,
);

TaskQueue advanceScheduledTasks(TaskQueue queue, int before, int after) {
  var next = queue;
  if (before < 600 &&
      after >= 600 &&
      !next.tasks.any((t) => t.taskId == 'iv-1000')) {
    next = next.add(infusionTask('iv-1000', 600));
  }
  if (before < 630 &&
      after >= 630 &&
      !next.tasks.any((t) => t.taskId == 'exam-1030')) {
    next = next.add(examinationTask('exam-1030', 630));
  }
  return next;
}

List<WorkTask> availableTasks(
  TaskQueue queue,
  int now, {
  DayShiftConfig config = const DayShiftConfig(),
}) {
  final phase = phaseAt(
    now,
    config: config,
    lunchDone: queue.tasks
        .where((t) => t.shiftPhase == ShiftPhase.lunchCare)
        .every((t) => t.status == WorkTaskStatus.completed),
    breakDone: queue.tasks.any(
      (t) => t.taskId == 'break' && t.status == WorkTaskStatus.completed,
    ),
  );
  final routine = queue.routine;
  return queue.pending.where((task) {
    if (task.taskType != WorkTaskType.routine) {
      return task.scheduledAt == null || task.scheduledAt! <= now;
    }
    if (task.taskId == 'afternoon_handoff' && now >= config.handoffStart) {
      return true;
    }
    if (task.taskId == 'morning_handoff') return now < config.handoffStart;
    if (task.shiftPhase == ShiftPhase.breakTime &&
        phase != ShiftPhase.breakTime) {
      return false;
    }
    if (task.shiftPhase == ShiftPhase.lunchCare && now < config.lunchStart) {
      return false;
    }
    if (task.shiftPhase == ShiftPhase.afternoonCare &&
        now < config.afternoonStart) {
      return false;
    }
    final index = routine.indexWhere((t) => t.taskId == task.taskId);
    if (index <= 0) return true;
    final previous = routine[index - 1];
    return previous.status == WorkTaskStatus.completed ||
        (task.shiftPhase != previous.shiftPhase &&
            (task.scheduledAt ?? 0) <= now);
  }).toList();
}
