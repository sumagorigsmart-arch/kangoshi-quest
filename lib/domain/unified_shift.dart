import 'dynamic_events.dart';
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
    unifiedShift: state.unifiedShift?.copyWith(
      exitView: state.timeMinutes < 1020 && state.timeMinutes + minutes >= 1020
          ? 'decision'
          : null,
    ),
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

/// Every elapsed minute is rolled once from the saved RNG state.
InterruptDecision rollInterrupt(
  GameState state, {
  bool force = false,
  List<EventDefinition> events = const [],
}) {
  final before = state.unifiedShift?.interruptSerial ?? 0;
  var next = DynamicEventEngine.advance(state, force: force);
  final serial = next.unifiedShift?.interruptSerial ?? before;
  if (serial != before &&
      serial % 4 == 0 &&
      events.isNotEmpty &&
      next.timeMinutes < 1020 &&
      next.phase == 'taskSelection') {
    final options = events
        .where(
          (e) =>
              mappedEventTasks.containsKey(e.eventId) &&
              next.timeMinutes >= e.minTime &&
              next.timeMinutes <= e.maxTime &&
              !next.playedEventIds.contains(e.eventId) &&
              e.conditions.every((c) => c.matches(next)),
        )
        .toList();
    if (options.isNotEmpty) {
      final event = options[next.rngState % options.length];
      // The official choice replaces this event's work instead of adding a
      // second workload for the same interruption.
      final id = 'dynamic-$serial';
      final queue = TaskQueue(
        next.workQueue!.tasks.where(
          (t) => t.taskId != id && t.sourceTaskId != id,
        ),
      );
      next = next.copyWith(
        workQueue: queue,
        phase: 'awaitingChoice',
        currentEventId: event.eventId,
        eventInstanceId: '${state.runId}-event-$serial',
        playedEventIds: [...state.playedEventIds, event.eventId],
      );
    }
  }
  return InterruptDecision(
    next,
    serial == before ? null : next.unifiedShift?.notice,
  );
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
  final suspendedId = shift.activeTaskId != taskId ? shift.activeTaskId : null;
  final suspendedRemaining = suspendedId == null
      ? 0
      : shift.activeTaskRemaining;
  final continuing =
      task.status == WorkTaskStatus.interrupted || shift.activeTaskId == taskId;
  final duration = continuing
      ? (task.remainingDuration ?? shift.activeTaskRemaining)
      : task.estimatedMinutes +
            (nextShiftRandom(state.rngState) % 4) -
            1 +
            (deadlineState(task, state.timeMinutes) == DeadlineState.overdue
                ? 4
                : 0);
  var current = state.copyWith(
    workQueue: queue.replace(
      task.copyWith(
        status: WorkTaskStatus.inProgress,
        remainingDuration: duration < 1 ? 1 : duration,
        resumedAt: continuing ? state.timeMinutes : null,
      ),
    ),
    unifiedShift: shift.copyWith(
      activeTaskId: taskId,
      activeTaskRemaining: duration < 1 ? 1 : duration,
    ),
  );
  for (var left = duration < 1 ? 1 : duration; left > 0; left--) {
    current = advanceUnifiedTime(current, 1);
    final active = current.workQueue!.tasks.firstWhere(
      (t) => t.taskId == taskId,
    );
    current = current.copyWith(
      workQueue: current.workQueue!.replace(
        active.copyWith(remainingDuration: left - 1),
      ),
      unifiedShift: current.unifiedShift!.copyWith(
        activeTaskRemaining: left - 1,
      ),
    );
    if (allowInterrupt) {
      final before = current.unifiedShift!.interruptSerial;
      current = rollInterrupt(current, events: events).state;
      if (current.unifiedShift!.interruptSerial != before &&
          current.workQueue!.tasks
                  .firstWhere((t) => t.taskId == taskId)
                  .status ==
              WorkTaskStatus.interrupted) {
        return TaskAction(current, interrupted: true);
      }
    }
  }
  final done = current.workQueue!.complete(taskId, current.timeMinutes);
  final completed = TaskState(
    task.taskType == WorkTaskType.documentation ? 1 : 0,
    task.taskType == WorkTaskType.dynamic ? 1 : 0,
    task.taskType == WorkTaskType.routine ? 1 : 0,
  );
  current = current.copyWith(
    workQueue: done,
    counters: current.counters.add(
      completed: completed,
      breakMinutes: task.taskId == 'break' ? duration : 0,
    ),
    unifiedShift: current.unifiedShift!.copyWith(
      clearActive: suspendedId == null,
      activeTaskId: suspendedId,
      activeTaskRemaining: suspendedRemaining,
    ),
  );
  return TaskAction(current, completed: true);
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
          result.pending
              .where(
                (t) => t.taskType == type && t.status == WorkTaskStatus.pending,
              )
              .toList()
            ..sort(
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
          requiredToLeave: event.eventId == 'acute_warning',
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
          requiredToLeave: false,
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
          requiredToLeave: false,
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
          requiredToLeave: true,
        ),
      );
    }
    return result;
  }
}
