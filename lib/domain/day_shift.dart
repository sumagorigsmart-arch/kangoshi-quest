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

enum WorkTaskStatus { pending, completed, handedOff, expired }

enum WorkPriority { urgent, high, normal, low }

enum DeadlineState { comfortable, approaching, overdue }

enum PatientSeverity { stable, watch, high }

enum AdlLevel { independent, partialAssist, fullAssist }

class Patient {
  final String patientId, bedLabel;
  final PatientSeverity severity;
  final AdlLevel adl;
  final bool hasInfusion,
      hasExamination,
      hasScheduledMedication,
      needsToileting,
      needsMealAssistance;
  const Patient({
    required this.patientId,
    required this.bedLabel,
    required this.severity,
    required this.adl,
    required this.hasInfusion,
    required this.hasExamination,
    required this.hasScheduledMedication,
    required this.needsToileting,
    required this.needsMealAssistance,
  });
  Patient copyWith({PatientSeverity? severity}) => Patient(
    patientId: patientId,
    bedLabel: bedLabel,
    severity: severity ?? this.severity,
    adl: adl,
    hasInfusion: hasInfusion,
    hasExamination: hasExamination,
    hasScheduledMedication: hasScheduledMedication,
    needsToileting: needsToileting,
    needsMealAssistance: needsMealAssistance,
  );
  factory Patient.fromJson(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    return Patient(
      patientId: m['patientId'] as String,
      bedLabel: m['bedLabel'] as String,
      severity: PatientSeverity.values.byName(m['severity'] as String),
      adl: AdlLevel.values.byName(m['adl'] as String),
      hasInfusion: m['hasInfusion'] as bool,
      hasExamination: m['hasExamination'] as bool,
      hasScheduledMedication: m['hasScheduledMedication'] as bool,
      needsToileting: m['needsToileting'] as bool,
      needsMealAssistance: m['needsMealAssistance'] as bool,
    );
  }
  Map<String, dynamic> toJson() => {
    'patientId': patientId,
    'bedLabel': bedLabel,
    'severity': severity.name,
    'adl': adl.name,
    'hasInfusion': hasInfusion,
    'hasExamination': hasExamination,
    'hasScheduledMedication': hasScheduledMedication,
    'needsToileting': needsToileting,
    'needsMealAssistance': needsMealAssistance,
  };
}

List<Patient> generatePatients() => const [
  Patient(
    patientId: 'p301a',
    bedLabel: '301-A',
    severity: PatientSeverity.stable,
    adl: AdlLevel.independent,
    hasInfusion: false,
    hasExamination: false,
    hasScheduledMedication: true,
    needsToileting: false,
    needsMealAssistance: false,
  ),
  Patient(
    patientId: 'p301b',
    bedLabel: '301-B',
    severity: PatientSeverity.watch,
    adl: AdlLevel.partialAssist,
    hasInfusion: true,
    hasExamination: false,
    hasScheduledMedication: true,
    needsToileting: true,
    needsMealAssistance: false,
  ),
  Patient(
    patientId: 'p302a',
    bedLabel: '302-A',
    severity: PatientSeverity.high,
    adl: AdlLevel.fullAssist,
    hasInfusion: true,
    hasExamination: true,
    hasScheduledMedication: true,
    needsToileting: true,
    needsMealAssistance: true,
  ),
  Patient(
    patientId: 'p303b',
    bedLabel: '303-B',
    severity: PatientSeverity.watch,
    adl: AdlLevel.partialAssist,
    hasInfusion: false,
    hasExamination: true,
    hasScheduledMedication: false,
    needsToileting: true,
    needsMealAssistance: true,
  ),
  Patient(
    patientId: 'p304a',
    bedLabel: '304-A',
    severity: PatientSeverity.stable,
    adl: AdlLevel.independent,
    hasInfusion: true,
    hasExamination: false,
    hasScheduledMedication: true,
    needsToileting: false,
    needsMealAssistance: false,
  ),
  Patient(
    patientId: 'p304b',
    bedLabel: '304-B',
    severity: PatientSeverity.watch,
    adl: AdlLevel.fullAssist,
    hasInfusion: false,
    hasExamination: false,
    hasScheduledMedication: true,
    needsToileting: true,
    needsMealAssistance: true,
  ),
];

class UnifiedShiftState {
  final List<Patient> patients;
  final int interruptSerial, lastInterruptAt;
  final String? activeTaskId;
  final int activeTaskRemaining;
  final String exitView;
  const UnifiedShiftState({
    required this.patients,
    this.interruptSerial = 0,
    this.lastInterruptAt = 510,
    this.activeTaskId,
    this.activeTaskRemaining = 0,
    this.exitView = 'work',
  });
  UnifiedShiftState copyWith({
    List<Patient>? patients,
    int? interruptSerial,
    int? lastInterruptAt,
    String? activeTaskId,
    int? activeTaskRemaining,
    bool clearActive = false,
    String? exitView,
  }) => UnifiedShiftState(
    patients: patients ?? this.patients,
    interruptSerial: interruptSerial ?? this.interruptSerial,
    lastInterruptAt: lastInterruptAt ?? this.lastInterruptAt,
    activeTaskId: clearActive ? null : activeTaskId ?? this.activeTaskId,
    activeTaskRemaining: clearActive
        ? 0
        : activeTaskRemaining ?? this.activeTaskRemaining,
    exitView: exitView ?? this.exitView,
  );
  factory UnifiedShiftState.fromJson(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    return UnifiedShiftState(
      patients: List.unmodifiable(
        (m['patients'] as List).map(Patient.fromJson),
      ),
      interruptSerial: m['interruptSerial'] as int? ?? 0,
      lastInterruptAt: m['lastInterruptAt'] as int? ?? 510,
      activeTaskId: m['activeTaskId'] as String?,
      activeTaskRemaining: m['activeTaskRemaining'] as int? ?? 0,
      exitView: m['exitView'] as String? ?? 'work',
    );
  }
  Map<String, dynamic> toJson() => {
    'patients': patients.map((p) => p.toJson()).toList(),
    'interruptSerial': interruptSerial,
    'lastInterruptAt': lastInterruptAt,
    'activeTaskId': activeTaskId,
    'activeTaskRemaining': activeTaskRemaining,
    'exitView': exitView,
  };
}

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
  final int? handedOffAt;
  final WorkPriority priority;
  final WorkTaskStatus status;
  final WorkTaskType taskType;
  final String? sourceEventId, patientId, parentTaskId, routineCategory;
  final ShiftPhase? shiftPhase;
  final bool requiredToLeave;
  const WorkTask({
    required this.taskId,
    required this.title,
    required this.createdAt,
    this.scheduledAt,
    this.deadline,
    this.handedOffAt,
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
    this.requiredToLeave = true,
  });
  WorkTask copyWith({
    WorkTaskStatus? status,
    int? deadline,
    int? scheduledAt,
    int? handedOffAt,
    bool? requiredToLeave,
  }) => WorkTask(
    taskId: taskId,
    title: title,
    createdAt: createdAt,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    deadline: deadline ?? this.deadline,
    handedOffAt: handedOffAt ?? this.handedOffAt,
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
    requiredToLeave: requiredToLeave ?? this.requiredToLeave,
  );
  factory WorkTask.fromJson(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    return WorkTask(
      taskId: m['taskId'] as String,
      title: m['title'] as String,
      createdAt: m['createdAt'] as int,
      scheduledAt: m['scheduledAt'] as int?,
      deadline: m['deadline'] as int?,
      handedOffAt: m['handedOffAt'] as int?,
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
      requiredToLeave: m['requiredToLeave'] as bool? ?? true,
    );
  }
  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'title': title,
    'createdAt': createdAt,
    'scheduledAt': scheduledAt,
    'deadline': deadline,
    'handedOffAt': handedOffAt,
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
    'requiredToLeave': requiredToLeave,
  };
  int unrecordedMinutes(int now) =>
      taskType == WorkTaskType.documentation && status == WorkTaskStatus.pending
      ? (now - createdAt).clamp(0, 99999)
      : 0;
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
  TaskQueue replace(WorkTask task) =>
      TaskQueue(tasks.map((t) => t.taskId == task.taskId ? task : t));
  List<WorkTask> get pending =>
      _sorted(tasks.where((t) => t.status == WorkTaskStatus.pending));
  List<WorkTask> get completed =>
      tasks.where((t) => t.status == WorkTaskStatus.completed).toList();
  List<WorkTask> get handedOff =>
      tasks.where((t) => t.status == WorkTaskStatus.handedOff).toList();
  TaskQueue handOff(Iterable<String> ids, int now) {
    final selected = ids.toSet();
    if (selected.isEmpty || selected.length != ids.length) {
      throw StateError('Select unique tasks');
    }
    for (final id in selected) {
      final task = tasks.firstWhere((t) => t.taskId == id);
      if (task.status != WorkTaskStatus.pending ||
          task.taskType == WorkTaskType.documentation ||
          task.requiredToLeave ||
          task.priority == WorkPriority.urgent) {
        throw StateError('Task cannot be handed off');
      }
    }
    return TaskQueue(
      tasks.map(
        (t) => selected.contains(t.taskId)
            ? t.copyWith(status: WorkTaskStatus.handedOff, handedOffAt: now)
            : t,
      ),
    );
  }

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
          deadline: now + 120,
          requiredToLeave: false,
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

TaskQueue generatePatientRoutineTasks(
  List<Patient> patients, {
  DayShiftConfig config = const DayShiftConfig(),
}) {
  final tasks = <WorkTask>[];
  void add(
    String id,
    String title,
    int at,
    int duration,
    ShiftPhase phase, {
    Patient? patient,
    int documentation = 0,
    WorkPriority priority = WorkPriority.normal,
    int? deadline,
    bool requiredToLeave = false,
  }) {
    tasks.add(
      WorkTask(
        taskId: id,
        title: patient == null ? title : '${patient.bedLabel} $title',
        patientId: patient?.patientId,
        createdAt: 510,
        scheduledAt: at,
        deadline: deadline,
        estimatedMinutes: duration,
        priority: priority,
        taskType: WorkTaskType.routine,
        routineCategory: id,
        shiftPhase: phase,
        documentationMinutes: documentation,
        requiredToLeave: requiredToLeave,
      ),
    );
  }

  add(
    'morning_handoff',
    '朝の申し送り',
    510,
    20,
    ShiftPhase.morningHandoff,
    deadline: 530,
    requiredToLeave: true,
  );
  for (var i = 0; i < patients.length; i++) {
    final p = patients[i];
    add(
      '${p.patientId}-am-vitals',
      '午前検温',
      530 + i * 7,
      6,
      ShiftPhase.morningCare,
      patient: p,
      documentation: 2,
      priority: p.severity == PatientSeverity.high
          ? WorkPriority.high
          : WorkPriority.normal,
      deadline: 660,
    );
    if (p.hasInfusion) {
      add(
        '${p.patientId}-iv-check',
        '点滴確認',
        575 + i * 9,
        5,
        ShiftPhase.morningCare,
        patient: p,
        documentation: 2,
        deadline: 690,
      );
    }
    if (p.needsToileting) {
      add(
        '${p.patientId}-am-toilet',
        '排泄介助',
        590 + i * 8,
        9,
        ShiftPhase.morningCare,
        patient: p,
        documentation: 2,
      );
    }
    if (p.adl != AdlLevel.independent) {
      add(
        '${p.patientId}-hygiene',
        '清潔ケア',
        615 + i * 8,
        12,
        ShiftPhase.morningCare,
        patient: p,
        documentation: 3,
      );
    }
    if (p.hasScheduledMedication) {
      add(
        '${p.patientId}-am-meds',
        '午前内服',
        640 + i * 5,
        4,
        ShiftPhase.morningCare,
        patient: p,
        documentation: 2,
        deadline: 720,
      );
      add(
        '${p.patientId}-lunch-meds',
        '昼の内服',
        config.lunchStart + 25 + i * 3,
        4,
        ShiftPhase.lunchCare,
        patient: p,
        documentation: 2,
      );
    }
    if (p.hasExamination) {
      add(
        '${p.patientId}-exam',
        '検査対応',
        650 + i * 15,
        15,
        ShiftPhase.morningCare,
        patient: p,
        documentation: 3,
        priority: WorkPriority.high,
        deadline: 750,
      );
    }
    if (p.needsMealAssistance) {
      add(
        '${p.patientId}-meal',
        '食事介助',
        config.lunchStart + 10 + i * 5,
        18,
        ShiftPhase.lunchCare,
        patient: p,
        documentation: 3,
      );
    }
    add(
      '${p.patientId}-pm-vitals',
      '午後検温',
      config.afternoonStart + i * 9,
      6,
      ShiftPhase.afternoonCare,
      patient: p,
      documentation: 2,
      deadline: 930,
    );
    if (p.needsToileting) {
      add(
        '${p.patientId}-pm-toilet',
        '午後の排泄介助',
        config.afternoonStart + 45 + i * 8,
        9,
        ShiftPhase.afternoonCare,
        patient: p,
        documentation: 2,
      );
    }
  }
  add('orders', '指示受け・確認', 620, 10, ShiftPhase.morningCare);
  add(
    'doctor_assist',
    '医師処置の介助',
    680,
    15,
    ShiftPhase.morningCare,
    documentation: 3,
  );
  add('lunch_serve', '昼食の配膳', config.lunchStart, 10, ShiftPhase.lunchCare);
  add('lunch_clear', '下膳', config.lunchStart + 55, 10, ShiftPhase.lunchCare);
  add(
    'break',
    '休憩',
    config.lunchStart + 65,
    30,
    ShiftPhase.breakTime,
    requiredToLeave: false,
  );
  add(
    'afternoon_handoff',
    '午後の申し送り',
    config.handoffStart,
    20,
    ShiftPhase.afternoonHandoff,
    deadline: config.handoffEnd,
  );
  return TaskQueue(tasks);
}

class ShiftWorkStatus {
  final bool scheduledEndReached, canLeave;
  final int overtimeMinutes,
      unfinishedTaskCount,
      unfinishedRecordCount,
      overdueCount,
      urgentCount;
  const ShiftWorkStatus(
    this.scheduledEndReached,
    this.canLeave,
    this.overtimeMinutes,
    this.unfinishedTaskCount,
    this.unfinishedRecordCount,
    this.overdueCount,
    this.urgentCount,
  );
  factory ShiftWorkStatus.from(
    TaskQueue queue,
    int now, {
    DayShiftConfig config = const DayShiftConfig(),
    String? activeTaskId,
  }) {
    final pending = queue.pending;
    final end = now >= config.finish;
    return ShiftWorkStatus(
      end,
      end &&
          activeTaskId == null &&
          !pending.any((t) => t.taskType != WorkTaskType.documentation),
      (now - config.finish).clamp(0, 99999),
      pending.length,
      queue.documentationCount,
      queue.overdue(now).length,
      queue.urgent.length,
    );
  }
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
    if (task.patientId != null) {
      return now >= (task.scheduledAt ?? 510) &&
          (queue.tasks
                  .firstWhere((t) => t.taskId == 'morning_handoff')
                  .status ==
              WorkTaskStatus.completed);
    }
    if (queue.tasks.any((t) => t.patientId != null)) {
      if (task.taskId == 'morning_handoff') return true;
      if (task.taskId == 'break') {
        return now >= (task.scheduledAt ?? 0) &&
            queue.tasks.firstWhere((t) => t.taskId == 'lunch_clear').status ==
                WorkTaskStatus.completed;
      }
      return now >= (task.scheduledAt ?? 510);
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
