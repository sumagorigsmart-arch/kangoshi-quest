import 'day_shift.dart';
import 'models.dart';

int nextShiftRandom(int value) {
  var n = value;
  n ^= (n << 13) & 0xffffffff;
  n ^= n >>> 17;
  n ^= (n << 5) & 0xffffffff;
  return n & 0xffffffff;
}

GameState advanceUnifiedTime(
  GameState state,
  int minutes, {
  BalanceConfig? balance,
}) {
  if (minutes < 0) throw ArgumentError.value(minutes, 'minutes');
  final config = balance;
  final meters = Map<String, int>.from(state.meters);
  meters['hp'] = (meters['hp']! + minutes * (config?.hpPerMinute ?? -5)).clamp(
    0,
    10000,
  );
  meters['mental'] =
      (meters['mental']! + minutes * (config?.mentalPerMinute ?? -2)).clamp(
        0,
        10000,
      );
  meters['bladder'] =
      (meters['bladder']! + minutes * (config?.bladderPerMinute ?? 12)).clamp(
        0,
        10000,
      );
  meters['hunger'] =
      (meters['hunger']! + minutes * (config?.hungerPerMinute ?? 10)).clamp(
        0,
        10000,
      );
  return state.copyWith(
    timeMinutes: state.timeMinutes + minutes,
    meters: meters,
    peakBladder: meters['bladder']! > state.peakBladder
        ? meters['bladder']
        : state.peakBladder,
  );
}

const mappedEventTasks = <String, String>{
  'call_water': 'ナースコール対応',
  'iv_alarm': '輸液ポンプ確認',
  'toilet_call': 'トイレ介助',
  'fall_prevention': '転倒リスク対応',
  'doctor_question': '医師からの確認',
  'new_order': '新しい指示の確認',
  'family_visit': '家族対応',
  'exam_transport': '検査搬送',
  'admission_notice': '入院連絡への対応',
  'acute_warning': '患者状態変化への対応',
  'colleague_request': '同僚の応援',
  'pharmacy_check': '薬剤部からの確認',
};

class InterruptDecision {
  final GameState state;
  final String? message;
  const InterruptDecision(this.state, this.message);
}

GameState startUnifiedShift(GameState base) {
  final patients = List<Patient>.unmodifiable(generatePatients());
  return base.copyWith(
    phase: 'taskSelection',
    tasks: const TaskState(0, 0, 0),
    workQueue: generatePatientRoutineTasks(patients),
    unifiedShift: UnifiedShiftState(patients: patients),
    clearCurrent: true,
  );
}

/// Every roll is deterministic from GameState.rngState, including a no-interrupt roll.
InterruptDecision rollInterrupt(
  GameState state, {
  bool force = false,
  List<EventDefinition> events = const [],
}) {
  final shift = state.unifiedShift;
  if (shift == null || state.workQueue == null) {
    return InterruptDecision(state, null);
  }
  final random = nextShiftRandom(state.rngState);
  final now = state.timeMinutes;
  final infusion = shift.patients.where((p) => p.hasInfusion).length;
  final assisted = shift.patients
      .where((p) => p.adl != AdlLevel.independent)
      .length;
  var chance = 18 + infusion * 3 + assisted * 2;
  if (now >= 690 && now < 780) chance += 10;
  if (now >= 740 && now < 790) chance += 8;
  if (now >= 910 && now < 930) chance += 10;
  if (now >= 1020) chance = 12;
  if (!force && random % 100 >= chance) {
    return InterruptDecision(state.copyWith(rngState: random), null);
  }
  final serial = shift.interruptSerial + 1;
  final patient = shift.patients[(random >>> 8) % shift.patients.length];
  final kinds = <String>[
    'ナースコール',
    'トイレ介助',
    '点滴終了',
    '輸液ポンプアラーム',
    '患者から質問',
    '家族から質問',
    '医師からの指示',
    '検査室から呼び出し',
    'リハビリから確認',
    '薬剤部から連絡',
    '転倒リスク対応',
    '急な処置',
    '入院連絡',
    '同僚から応援依頼',
    '患者状態変化',
  ];
  var index = (random >>> 16) % kinds.length;
  if (patient.hasInfusion && serial % 3 == 0) index = 2 + serial % 2;
  if (patient.needsToileting && serial % 4 == 0) index = 1;
  if (now >= 690 && now < 780 && serial % 3 == 1) index = 1;
  final title = kinds[index];
  final urgent = index == 10 || index == 14;
  final task = WorkTask(
    taskId: 'interrupt-$serial',
    title: '${patient.bedLabel} $title',
    patientId: patient.patientId,
    createdAt: now,
    scheduledAt: now,
    deadline: now + (urgent ? 10 : 30),
    estimatedMinutes: urgent ? 12 : 4 + (random >>> 24) % 10,
    priority: urgent ? WorkPriority.urgent : WorkPriority.high,
    taskType: WorkTaskType.dynamic,
    documentationMinutes: urgent ? 6 : 3,
  );
  var result = state.copyWith(
    rngState: random,
    unifiedShift: shift.copyWith(interruptSerial: serial, lastInterruptAt: now),
    workQueue: state.workQueue!.add(task),
    counters: state.counters.add(callCount: index == 0 ? 1 : 0),
  );
  // Official event choices are surfaced periodically. Their selected outcome is
  // translated through EventTaskAdapter rather than the legacy aggregate counter.
  if (events.isNotEmpty && serial % 4 == 0 && now < 1020) {
    final options = events
        .where(
          (e) =>
              mappedEventTasks.containsKey(e.eventId) &&
              now >= e.minTime &&
              now <= e.maxTime &&
              !result.playedEventIds.contains(e.eventId) &&
              e.conditions.every((c) => c.matches(result)),
        )
        .toList();
    if (options.isNotEmpty) {
      final weights = options
          .map(
            (e) =>
                e.weight *
                e.weightModifiers.fold<double>(
                  1,
                  (w, m) => w * m.apply(result),
                ),
          )
          .toList();
      var target =
          random / 4294967296 * weights.fold<double>(0, (a, b) => a + b);
      var event = options.last;
      for (var i = 0; i < options.length; i++) {
        target -= weights[i];
        if (target < 0) {
          event = options[i];
          break;
        }
      }
      result = result.copyWith(
        phase: 'awaitingChoice',
        counters: result.counters.add(
          callCount: event.onAppear['callCount'] ?? 0,
          admissionCount: event.onAppear['admissionCount'] ?? 0,
          acuteChangeCount: event.onAppear['acuteChangeCount'] ?? 0,
        ),
        currentEventId: event.eventId,
        eventInstanceId: '${state.runId}-event-$serial',
        playedEventIds: [...state.playedEventIds, event.eventId],
      );
    }
  }
  return InterruptDecision(result, task.title);
}

class TaskAction {
  final GameState state;
  final bool interrupted, completed;
  const TaskAction(
    this.state, {
    this.interrupted = false,
    this.completed = false,
  });
}

TaskAction performUnifiedTask(
  GameState state,
  String taskId, {
  bool allowInterrupt = true,
  List<EventDefinition> events = const [],
}) {
  final queue = state.workQueue;
  final shift = state.unifiedShift;
  if (queue == null || shift == null || state.phase != 'taskSelection') {
    throw StateError('Not selecting unified tasks');
  }
  if (!availableTasks(
    queue,
    state.timeMinutes,
  ).any((t) => t.taskId == taskId)) {
    throw StateError('Task unavailable');
  }
  final task = queue.tasks.firstWhere((t) => t.taskId == taskId);
  final rng = nextShiftRandom(state.rngState);
  final remaining = shift.activeTaskId == taskId
      ? shift.activeTaskRemaining
      : task.estimatedMinutes + (rng % 4) - 1;
  final lateMinutes =
      deadlineState(task, state.timeMinutes) == DeadlineState.overdue ? 4 : 0;
  final duration = (remaining < 1 ? 1 : remaining) + lateMinutes;
  if (allowInterrupt && duration >= 4 && shift.activeTaskId == null) {
    final midway = (duration / 2).floor();
    final partial = advanceUnifiedTime(state, midway).copyWith(
      rngState: rng,
      unifiedShift: shift.copyWith(
        activeTaskId: taskId,
        activeTaskRemaining: duration - midway,
      ),
    );
    final decision = rollInterrupt(partial, events: events);
    if (decision.message != null) {
      return TaskAction(decision.state, interrupted: true);
    }
  }
  final now = state.timeMinutes + duration;
  final done = queue.complete(taskId, now);
  final completed = TaskState(
    task.taskType == WorkTaskType.documentation ? 1 : 0,
    task.taskType == WorkTaskType.dynamic ? 1 : 0,
    task.taskType == WorkTaskType.routine ? 1 : 0,
  );
  final next = advanceUnifiedTime(state, duration).copyWith(
    rngState: rng,
    workQueue: done,
    counters: state.counters.add(
      completed: completed,
      breakMinutes: task.taskId == 'break' ? duration : 0,
    ),
    unifiedShift: shift.activeTaskId == taskId
        ? shift.copyWith(clearActive: true)
        : shift,
  );
  final decision = allowInterrupt
      ? rollInterrupt(next, events: events)
      : InterruptDecision(next, null);
  return TaskAction(decision.state, completed: true);
}

/// The old outcome counters are interpreted as commands, never added to the
/// legacy TaskState for a unified shift.
class EventTaskAdapter {
  static TaskQueue apply(
    TaskQueue queue,
    EventDefinition event,
    OutcomeDefinition outcome,
    int now,
    Patient patient,
    String instanceId,
  ) {
    var result = queue;
    final effects = outcome.effects;
    final title = mappedEventTasks[event.eventId] ?? event.title;
    void completeExisting(WorkTaskType type, int count) {
      final candidates =
          result.pending.where((t) => t.taskType == type).toList()..sort(
            (a, b) => (a.patientId == patient.patientId ? 0 : 1).compareTo(
              b.patientId == patient.patientId ? 0 : 1,
            ),
          );
      for (final task in candidates.take(count)) {
        result = result.complete(task.taskId, now);
      }
    }

    completeExisting(WorkTaskType.documentation, effects.completeTasks.record);
    completeExisting(WorkTaskType.dynamic, effects.completeTasks.coordination);
    completeExisting(WorkTaskType.routine, effects.completeTasks.care);
    if (event.eventId == 'iv_alarm') {
      final target = result.pending
          .where(
            (t) => t.patientId == patient.patientId && t.title.contains('点滴'),
          )
          .firstOrNull;
      if (target != null) {
        result = result.replace(target.copyWith(deadline: now + 10));
      }
    }
    if (event.eventId == 'exam_transport') {
      final target = result.pending
          .where(
            (t) => t.patientId == patient.patientId && t.title.contains('検査'),
          )
          .firstOrNull;
      if (target != null) {
        result = result.replace(target.copyWith(scheduledAt: now + 10));
      }
    }
    final count = effects.createTasks.coordination + effects.createTasks.care;
    final dynamicCount = count == 0 && effects.createTasks.record == 0
        ? 1
        : count;
    for (var i = 0; i < dynamicCount; i++) {
      final id = '$instanceId-task-$i';
      result = result.add(
        WorkTask(
          taskId: id,
          title: '${patient.bedLabel} $title',
          patientId: patient.patientId,
          createdAt: now,
          scheduledAt: now,
          deadline: now + 35,
          estimatedMinutes: 5 + (i % 3) * 3,
          priority: event.eventId == 'acute_warning'
              ? WorkPriority.urgent
              : WorkPriority.high,
          taskType: WorkTaskType.dynamic,
          sourceEventId: event.eventId,
          documentationMinutes: 4,
        ),
      );
    }
    for (var i = 0; i < effects.createTasks.record; i++) {
      result = result.add(
        WorkTask(
          taskId: '$instanceId-record-$i',
          title: '${patient.bedLabel} ${event.title}の記録',
          patientId: patient.patientId,
          createdAt: now,
          deadline: now + 120,
          estimatedMinutes: 5,
          taskType: WorkTaskType.documentation,
          sourceEventId: event.eventId,
        ),
      );
    }
    if (event.eventId == 'new_order') {
      result = result.add(
        WorkTask(
          taskId: '$instanceId-order-action',
          title: '${patient.bedLabel} 指示の実施',
          patientId: patient.patientId,
          createdAt: now,
          scheduledAt: now,
          deadline: now + 45,
          estimatedMinutes: 12,
          priority: WorkPriority.high,
          taskType: WorkTaskType.dynamic,
          sourceEventId: event.eventId,
          documentationMinutes: 5,
        ),
      );
    }
    if (event.eventId == 'acute_warning') {
      result = result.add(
        WorkTask(
          taskId: '$instanceId-recheck',
          title: '${patient.bedLabel} 状態再確認',
          patientId: patient.patientId,
          createdAt: now,
          scheduledAt: now,
          deadline: now + 10,
          estimatedMinutes: 8,
          priority: WorkPriority.urgent,
          taskType: WorkTaskType.dynamic,
          sourceEventId: event.eventId,
          documentationMinutes: 5,
        ),
      );
    }
    return result;
  }
}
