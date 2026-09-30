import 'dart:collection';

import 'day_shift.dart';

Map<String, dynamic> object(dynamic value) =>
    Map<String, dynamic>.from(value as Map);
int number(dynamic value) => value as int;

class TaskState {
  final int record, coordination, care;
  const TaskState(this.record, this.coordination, this.care);
  int get total => record + coordination + care;
  factory TaskState.fromJson(dynamic value) {
    final m = object(value);
    return TaskState(
      m['record'] as int,
      m['coordination'] as int,
      m['care'] as int,
    );
  }
  Map<String, int> toJson() => {
    'record': record,
    'coordination': coordination,
    'care': care,
  };
  TaskState add(TaskState other) => TaskState(
    record + other.record,
    coordination + other.coordination,
    care + other.care,
  );
  TaskState subtract(TaskState other) => TaskState(
    (record - other.record).clamp(0, 1000000),
    (coordination - other.coordination).clamp(0, 1000000),
    (care - other.care).clamp(0, 1000000),
  );
  TaskState taken(TaskState request) => TaskState(
    record < request.record ? record : request.record,
    coordination < request.coordination ? coordination : request.coordination,
    care < request.care ? care : request.care,
  );
}

class Counters {
  final int breakMinutes,
      toiletCount,
      callCount,
      admissionCount,
      acuteChangeCount;
  final int completedRecord,
      completedCoordination,
      completedCare,
      transferredCoordination,
      transferredCare,
      handoverAttempts;
  const Counters({
    this.breakMinutes = 0,
    this.toiletCount = 0,
    this.callCount = 0,
    this.admissionCount = 0,
    this.acuteChangeCount = 0,
    this.completedRecord = 0,
    this.completedCoordination = 0,
    this.completedCare = 0,
    this.transferredCoordination = 0,
    this.transferredCare = 0,
    this.handoverAttempts = 0,
  });
  factory Counters.fromJson(dynamic value) {
    final m = object(value);
    int v(String key) => (m[key] ?? 0) as int;
    return Counters(
      breakMinutes: v('breakMinutes'),
      toiletCount: v('toiletCount'),
      callCount: v('callCount'),
      admissionCount: v('admissionCount'),
      acuteChangeCount: v('acuteChangeCount'),
      completedRecord: v('completedRecord'),
      completedCoordination: v('completedCoordination'),
      completedCare: v('completedCare'),
      transferredCoordination: v('transferredCoordination'),
      transferredCare: v('transferredCare'),
      handoverAttempts: v('handoverAttempts'),
    );
  }
  Map<String, int> toJson() => {
    'breakMinutes': breakMinutes,
    'toiletCount': toiletCount,
    'callCount': callCount,
    'admissionCount': admissionCount,
    'acuteChangeCount': acuteChangeCount,
    'completedRecord': completedRecord,
    'completedCoordination': completedCoordination,
    'completedCare': completedCare,
    'transferredCoordination': transferredCoordination,
    'transferredCare': transferredCare,
    'handoverAttempts': handoverAttempts,
  };
  Counters add({
    int breakMinutes = 0,
    int toiletCount = 0,
    int callCount = 0,
    int admissionCount = 0,
    int acuteChangeCount = 0,
    TaskState completed = const TaskState(0, 0, 0),
    TaskState transferred = const TaskState(0, 0, 0),
    int handoverAttempts = 0,
  }) => Counters(
    breakMinutes: this.breakMinutes + breakMinutes,
    toiletCount: this.toiletCount + toiletCount,
    callCount: this.callCount + callCount,
    admissionCount: this.admissionCount + admissionCount,
    acuteChangeCount: this.acuteChangeCount + acuteChangeCount,
    completedRecord: completedRecord + completed.record,
    completedCoordination: completedCoordination + completed.coordination,
    completedCare: completedCare + completed.care,
    transferredCoordination: transferredCoordination + transferred.coordination,
    transferredCare: transferredCare + transferred.care,
    handoverAttempts: this.handoverAttempts + handoverAttempts,
  );
  int get transferredTotal => transferredCoordination + transferredCare;
}

class Condition {
  final String field, op;
  final Object value;
  const Condition(this.field, this.op, this.value);
  factory Condition.fromJson(dynamic value) {
    final m = object(value);
    return Condition(
      m['field'] as String,
      m['op'] as String,
      m['value'] as Object,
    );
  }
  Map<String, Object> toJson() => {'field': field, 'op': op, 'value': value};
  bool matches(GameState s) {
    final Object actual = switch (field) {
      'timeMinutes' => s.timeMinutes,
      'meters.hp' => s.meters['hp']!,
      'meters.mental' => s.meters['mental']!,
      'meters.bladder' => s.meters['bladder']!,
      'meters.hunger' => s.meters['hunger']!,
      'scores.patient' => s.scores['patient']!,
      'scores.team' => s.scores['team']!,
      'scores.risk' => s.scores['risk']!,
      'tasks.record' => s.tasks.record,
      'tasks.coordination' => s.tasks.coordination,
      'tasks.care' => s.tasks.care,
      'tasks.total' => s.tasks.total,
      'counters.breakMinutes' => s.counters.breakMinutes,
      'flags.hasRested' => s.flags['hasRested'] ?? false,
      'flags.teamSupport' => s.flags['teamSupport'] ?? false,
      _ => throw StateError('Unknown condition $field'),
    };
    return switch (op) {
      'eq' => actual == value,
      'gte' => (actual as num) >= (value as num),
      'lte' => (actual as num) <= (value as num),
      _ => throw StateError('Unknown operator $op'),
    };
  }
}

class WeightModifier {
  final List<Condition> conditions;
  final double factor;
  const WeightModifier(this.conditions, this.factor);
  factory WeightModifier.fromJson(dynamic value) {
    final m = object(value);
    return WeightModifier(
      List.unmodifiable((m['conditions'] as List).map(Condition.fromJson)),
      (m['factor'] as num).toDouble(),
    );
  }
  Map<String, dynamic> toJson() => {
    'conditions': conditions.map((e) => e.toJson()).toList(),
    'factor': factor,
  };
  double apply(GameState s) =>
      conditions.every((c) => c.matches(s)) ? factor : 1;
}

class Effects {
  final int durationMinutes;
  final Map<String, int> meterDelta, scoreDelta;
  final TaskState createTasks, completeTasks, transferTasks;
  final int? setBladderAfter;
  final int breakMinutes, toiletCount;
  final Map<String, bool> setFlags;
  const Effects({
    required this.durationMinutes,
    this.meterDelta = const {},
    this.scoreDelta = const {},
    this.createTasks = const TaskState(0, 0, 0),
    this.completeTasks = const TaskState(0, 0, 0),
    this.transferTasks = const TaskState(0, 0, 0),
    this.setBladderAfter,
    this.breakMinutes = 0,
    this.toiletCount = 0,
    this.setFlags = const {},
  });
  factory Effects.fromJson(dynamic value) {
    final m = object(value);
    Map<String, int> ints(String key) =>
        (m[key] == null ? <String, dynamic>{} : object(m[key])).map(
          (k, v) => MapEntry(k, v as int),
        );
    TaskState tasks(String key) => m[key] == null
        ? const TaskState(0, 0, 0)
        : TaskState(
            m[key]['record'] ?? 0,
            m[key]['coordination'] ?? 0,
            m[key]['care'] ?? 0,
          );
    final c = m['counters'] == null
        ? <String, dynamic>{}
        : object(m['counters']);
    return Effects(
      durationMinutes: m['durationMinutes'] as int,
      meterDelta: Map.unmodifiable(ints('meterDelta')),
      scoreDelta: Map.unmodifiable(ints('scoreDelta')),
      createTasks: tasks('createTasks'),
      completeTasks: tasks('completeTasks'),
      transferTasks: tasks('transferTasks'),
      setBladderAfter: m['setBladderAfter'] as int?,
      breakMinutes: (c['breakMinutes'] ?? 0) as int,
      toiletCount: (c['toiletCount'] ?? 0) as int,
      setFlags: m['setFlags'] == null
          ? const {}
          : Map.unmodifiable(
              object(m['setFlags']).map((k, v) => MapEntry(k, v as bool)),
            ),
    );
  }
  Map<String, dynamic> toJson() => {
    'durationMinutes': durationMinutes,
    'meterDelta': meterDelta,
    'scoreDelta': scoreDelta,
    'createTasks': createTasks.toJson(),
    'completeTasks': completeTasks.toJson(),
    'transferTasks': transferTasks.toJson(),
    if (setBladderAfter != null) 'setBladderAfter': setBladderAfter,
    'counters': {'breakMinutes': breakMinutes, 'toiletCount': toiletCount},
    'setFlags': setFlags,
  };
}

class OutcomeDefinition {
  final String outcomeId, text;
  final double weight;
  final List<WeightModifier> weightModifiers;
  final Effects effects;
  const OutcomeDefinition(
    this.outcomeId,
    this.text,
    this.weight,
    this.effects, [
    this.weightModifiers = const [],
  ]);
  factory OutcomeDefinition.fromJson(dynamic value) {
    final m = object(value);
    return OutcomeDefinition(
      m['outcomeId'],
      m['text'],
      (m['weight'] as num).toDouble(),
      Effects.fromJson(m['effects']),
      List.unmodifiable(
        ((m['weightModifiers'] ?? []) as List).map(WeightModifier.fromJson),
      ),
    );
  }
  Map<String, dynamic> toJson() => {
    'outcomeId': outcomeId,
    'text': text,
    'weight': weight,
    'effects': effects.toJson(),
    'weightModifiers': weightModifiers.map((e) => e.toJson()).toList(),
  };
}

class ChoiceDefinition {
  final String choiceId, label, hint, actionType;
  final List<OutcomeDefinition> outcomes;
  const ChoiceDefinition(
    this.choiceId,
    this.label,
    this.hint,
    this.actionType,
    this.outcomes,
  );
  factory ChoiceDefinition.fromJson(dynamic value) {
    final m = object(value);
    return ChoiceDefinition(
      m['choiceId'],
      m['label'],
      m['hint'],
      m['actionType'],
      List.unmodifiable(
        (m['outcomes'] as List).map(OutcomeDefinition.fromJson),
      ),
    );
  }
  Map<String, dynamic> toJson() => {
    'choiceId': choiceId,
    'label': label,
    'hint': hint,
    'actionType': actionType,
    'outcomes': outcomes.map((e) => e.toJson()).toList(),
  };
}

class EventDefinition {
  final String eventId, title, description, category;
  final int minTime, maxTime, maxPerRun;
  final double weight;
  final List<String> tags;
  final List<Condition> conditions;
  final List<WeightModifier> weightModifiers;
  final List<ChoiceDefinition> choices;
  final Map<String, int> onAppear;
  const EventDefinition({
    required this.eventId,
    required this.title,
    required this.description,
    required this.category,
    required this.minTime,
    required this.maxTime,
    required this.weight,
    required this.tags,
    required this.conditions,
    required this.choices,
    this.maxPerRun = 1,
    this.weightModifiers = const [],
    this.onAppear = const {},
  });
  factory EventDefinition.fromJson(dynamic value) {
    final m = object(value), t = object(m['timeRange']);
    return EventDefinition(
      eventId: m['eventId'],
      title: m['title'],
      description: m['description'],
      category: m['category'],
      minTime: t['min'],
      maxTime: t['max'],
      weight: (m['weight'] as num).toDouble(),
      tags: List<String>.from(m['tags']),
      conditions: List.unmodifiable(
        (m['conditions'] as List).map(Condition.fromJson),
      ),
      choices: List.unmodifiable(
        (m['choices'] as List).map(ChoiceDefinition.fromJson),
      ),
      maxPerRun: m['maxPerRun'],
      weightModifiers: List.unmodifiable(
        ((m['weightModifiers'] ?? []) as List).map(WeightModifier.fromJson),
      ),
      onAppear:
          (m['onAppear'] == null ? <String, dynamic>{} : object(m['onAppear']))
              .map((k, v) => MapEntry(k, v as int)),
    );
  }
  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'title': title,
    'description': description,
    'category': category,
    'timeRange': {'min': minTime, 'max': maxTime},
    'weight': weight,
    'tags': tags,
    'conditions': conditions.map((e) => e.toJson()).toList(),
    'choices': choices.map((e) => e.toJson()).toList(),
    'maxPerRun': maxPerRun,
    'weightModifiers': weightModifiers.map((e) => e.toJson()).toList(),
    'onAppear': onAppear,
  };
}

class BalanceConfig {
  final List<int> slots;
  final int hpPerMinute,
      mentalPerMinute,
      bladderPerMinute,
      hungerPerMinute,
      fatigueMinutes,
      majorLimit,
      maxChoices,
      dayEnd,
      plannedFinish,
      hardStop;
  const BalanceConfig({
    required this.slots,
    this.hpPerMinute = -5,
    this.mentalPerMinute = -2,
    this.bladderPerMinute = 12,
    this.hungerPerMinute = 10,
    this.fatigueMinutes = 5,
    this.majorLimit = 2,
    this.maxChoices = 30,
    this.dayEnd = 1020,
    this.plannedFinish = 1035,
    this.hardStop = 1230,
  });
  factory BalanceConfig.fromJson(dynamic value) {
    final m = object(value), d = object(m['naturalPerMinute']);
    return BalanceConfig(
      slots: List<int>.from(m['slots']),
      hpPerMinute: d['hp'],
      mentalPerMinute: d['mental'],
      bladderPerMinute: d['bladder'],
      hungerPerMinute: d['hunger'],
      fatigueMinutes: m['fatigueMinutes'],
      majorLimit: m['majorLimit'],
      maxChoices: m['maxChoices'],
      dayEnd: m['dayEnd'],
      plannedFinish: m['plannedFinish'],
      hardStop: m['hardStop'],
    );
  }
  Map<String, dynamic> toJson() => {
    'slots': slots,
    'naturalPerMinute': {
      'hp': hpPerMinute,
      'mental': mentalPerMinute,
      'bladder': bladderPerMinute,
      'hunger': hungerPerMinute,
    },
    'fatigueMinutes': fatigueMinutes,
    'majorLimit': majorLimit,
    'maxChoices': maxChoices,
    'dayEnd': dayEnd,
    'plannedFinish': plannedFinish,
    'hardStop': hardStop,
  };
}

class TitleDefinition {
  final String id, name;
  final int priority;
  final List<Condition> conditions;
  const TitleDefinition(this.id, this.name, this.priority, this.conditions);
  factory TitleDefinition.fromJson(dynamic value) {
    final m = object(value);
    return TitleDefinition(
      m['id'],
      m['name'],
      m['priority'],
      List.unmodifiable((m['conditions'] as List).map(Condition.fromJson)),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'priority': priority,
    'conditions': conditions.map((e) => e.toJson()).toList(),
  };
}

class GameResult {
  final String reason, primaryTitleId;
  final int plannedFinishTime, finishTime, overtimeMinutes, peakBladder;
  final TaskState remainingTasks, unresolvedAtRelief;
  final Counters counters;
  final Map<String, int> axisScores;
  final Map<String, String> grades;
  final List<String> earnedTitleIds;
  GameResult(
    this.reason,
    this.primaryTitleId,
    this.plannedFinishTime,
    this.finishTime,
    this.overtimeMinutes,
    this.peakBladder,
    this.remainingTasks,
    this.unresolvedAtRelief,
    this.counters,
    Map<String, int> axisScores,
    Map<String, String> grades,
    List<String> earnedTitleIds,
  ) : axisScores = UnmodifiableMapView(Map.of(axisScores)),
      grades = UnmodifiableMapView(Map.of(grades)),
      earnedTitleIds = List.unmodifiable(earnedTitleIds);
  factory GameResult.fromJson(dynamic value) {
    final m = object(value);
    return GameResult(
      m['reason'],
      m['primaryTitleId'],
      m['plannedFinishTime'],
      m['finishTime'],
      m['overtimeMinutes'],
      m['peakBladder'],
      TaskState.fromJson(m['remainingTasks']),
      TaskState.fromJson(m['unresolvedAtRelief']),
      Counters.fromJson(m['counters']),
      object(m['axisScores']).map((k, v) => MapEntry(k, v as int)),
      object(m['grades']).map((k, v) => MapEntry(k, v as String)),
      List<String>.from(m['earnedTitleIds']),
    );
  }
  Map<String, dynamic> toJson() => {
    'reason': reason,
    'primaryTitleId': primaryTitleId,
    'plannedFinishTime': plannedFinishTime,
    'finishTime': finishTime,
    'overtimeMinutes': overtimeMinutes,
    'peakBladder': peakBladder,
    'remainingTasks': remainingTasks.toJson(),
    'unresolvedAtRelief': unresolvedAtRelief.toJson(),
    'counters': counters.toJson(),
    'axisScores': axisScores,
    'grades': grades,
    'earnedTitleIds': earnedTitleIds,
  };
}

class GameState {
  final TaskQueue? workQueue;
  ShiftPhase? get shiftPhase {
    final queue = workQueue;
    if (queue == null) return null;
    final lunchDone = queue.tasks
        .where((t) => t.shiftPhase == ShiftPhase.lunchCare)
        .every((t) => t.status == WorkTaskStatus.completed);
    final breakDone = queue.tasks.any(
      (t) => t.taskId == 'break' && t.status == WorkTaskStatus.completed,
    );
    return phaseAt(timeMinutes, lunchDone: lunchDone, breakDone: breakDone);
  }

  final String runId, contentVersion, balanceVersion, phase;
  final int schemaVersion,
      seed,
      rngState,
      timeMinutes,
      slotIndex,
      turnCount,
      presentationCount,
      majorCount,
      peakBladder,
      minimumHp,
      minimumMental;
  final Map<String, int> meters, scores;
  final TaskState tasks;
  final Counters counters;
  final Map<String, bool> flags;
  final List<String> playedEventIds, choiceHistory;
  final String? currentEventId, eventInstanceId, currentOutcomeId, outcomeText;
  final OutcomeDefinition? currentOutcome;
  final bool lastEventMajor, handoverDone;
  final GameResult? result;
  GameState({
    required this.runId,
    required this.contentVersion,
    required this.balanceVersion,
    this.schemaVersion = 1,
    required this.seed,
    required this.rngState,
    required this.timeMinutes,
    required this.phase,
    required this.slotIndex,
    required this.turnCount,
    required this.presentationCount,
    required Map<String, int> meters,
    required Map<String, int> scores,
    required this.tasks,
    required this.counters,
    required Map<String, bool> flags,
    required List<String> playedEventIds,
    required List<String> choiceHistory,
    required this.majorCount,
    required this.lastEventMajor,
    required this.peakBladder,
    required this.minimumHp,
    required this.minimumMental,
    this.currentEventId,
    this.eventInstanceId,
    this.currentOutcomeId,
    this.outcomeText,
    this.currentOutcome,
    required this.handoverDone,
    this.result,
    this.workQueue,
  }) : meters = UnmodifiableMapView(Map.of(meters)),
       scores = UnmodifiableMapView(Map.of(scores)),
       flags = UnmodifiableMapView(Map.of(flags)),
       playedEventIds = List.unmodifiable(playedEventIds),
       choiceHistory = List.unmodifiable(choiceHistory);
  factory GameState.initial(
    String runId,
    int seed,
    String contentVersion,
    String balanceVersion,
  ) {
    if (seed == 0 || seed < 0 || seed > 0xffffffff) {
      throw ArgumentError('seed must be uint32 and nonzero');
    }
    return GameState(
      runId: runId,
      contentVersion: contentVersion,
      balanceVersion: balanceVersion,
      seed: seed,
      rngState: seed,
      timeMinutes: 510,
      phase: 'closing',
      slotIndex: 0,
      turnCount: 0,
      presentationCount: 0,
      meters: {'hp': 8000, 'mental': 7500, 'bladder': 1500, 'hunger': 1000},
      scores: {'patient': 5000, 'team': 5000, 'risk': 1200},
      tasks: const TaskState(4, 1, 1),
      counters: const Counters(),
      flags: {'hasRested': false, 'teamSupport': false},
      playedEventIds: [],
      choiceHistory: [],
      majorCount: 0,
      lastEventMajor: false,
      peakBladder: 1500,
      minimumHp: 8000,
      minimumMental: 7500,
      handoverDone: false,
    );
  }
  GameState copyWith({
    int? rngState,
    int? timeMinutes,
    String? phase,
    int? slotIndex,
    int? turnCount,
    int? presentationCount,
    Map<String, int>? meters,
    Map<String, int>? scores,
    TaskState? tasks,
    Counters? counters,
    Map<String, bool>? flags,
    List<String>? playedEventIds,
    List<String>? choiceHistory,
    int? majorCount,
    bool? lastEventMajor,
    int? peakBladder,
    int? minimumHp,
    int? minimumMental,
    String? currentEventId,
    String? eventInstanceId,
    String? currentOutcomeId,
    String? outcomeText,
    OutcomeDefinition? currentOutcome,
    bool? handoverDone,
    GameResult? result,
    TaskQueue? workQueue,
    bool clearCurrent = false,
  }) => GameState(
    runId: runId,
    contentVersion: contentVersion,
    balanceVersion: balanceVersion,
    schemaVersion: schemaVersion,
    seed: seed,
    rngState: rngState ?? this.rngState,
    timeMinutes: timeMinutes ?? this.timeMinutes,
    phase: phase ?? this.phase,
    slotIndex: slotIndex ?? this.slotIndex,
    turnCount: turnCount ?? this.turnCount,
    presentationCount: presentationCount ?? this.presentationCount,
    meters: meters ?? this.meters,
    scores: scores ?? this.scores,
    tasks: tasks ?? this.tasks,
    counters: counters ?? this.counters,
    flags: flags ?? this.flags,
    playedEventIds: playedEventIds ?? this.playedEventIds,
    choiceHistory: choiceHistory ?? this.choiceHistory,
    majorCount: majorCount ?? this.majorCount,
    lastEventMajor: lastEventMajor ?? this.lastEventMajor,
    peakBladder: peakBladder ?? this.peakBladder,
    minimumHp: minimumHp ?? this.minimumHp,
    minimumMental: minimumMental ?? this.minimumMental,
    currentEventId: clearCurrent ? null : currentEventId ?? this.currentEventId,
    eventInstanceId: clearCurrent
        ? null
        : eventInstanceId ?? this.eventInstanceId,
    currentOutcomeId: clearCurrent
        ? null
        : currentOutcomeId ?? this.currentOutcomeId,
    outcomeText: clearCurrent ? null : outcomeText ?? this.outcomeText,
    currentOutcome: clearCurrent ? null : currentOutcome ?? this.currentOutcome,
    handoverDone: handoverDone ?? this.handoverDone,
    result: result ?? this.result,
    workQueue: workQueue ?? this.workQueue,
  );
  factory GameState.fromJson(dynamic value) {
    final m = object(value);
    return GameState(
      runId: m['runId'],
      contentVersion: m['contentVersion'],
      balanceVersion: m['balanceVersion'],
      schemaVersion: m['schemaVersion'],
      seed: m['seed'],
      rngState: m['rngState'],
      timeMinutes: m['timeMinutes'],
      phase: m['phase'],
      slotIndex: m['slotIndex'],
      turnCount: m['turnCount'],
      presentationCount: m['presentationCount'],
      meters: object(m['meters']).map((k, v) => MapEntry(k, v as int)),
      scores: object(m['scores']).map((k, v) => MapEntry(k, v as int)),
      tasks: TaskState.fromJson(m['tasks']),
      counters: Counters.fromJson(m['counters']),
      flags: object(m['flags']).map((k, v) => MapEntry(k, v as bool)),
      playedEventIds: List<String>.from(m['playedEventIds']),
      choiceHistory: List<String>.from(m['choiceHistory']),
      majorCount: m['majorCount'],
      lastEventMajor: m['lastEventMajor'],
      peakBladder: m['peakBladder'],
      minimumHp: m['minimumHp'],
      minimumMental: m['minimumMental'],
      currentEventId: m['currentEventId'],
      eventInstanceId: m['eventInstanceId'],
      currentOutcomeId: m['currentOutcomeId'],
      outcomeText: m['outcomeText'],
      currentOutcome: m['currentOutcome'] == null
          ? null
          : OutcomeDefinition.fromJson(m['currentOutcome']),
      handoverDone: m['handoverDone'],
      result: m['result'] == null ? null : GameResult.fromJson(m['result']),
      workQueue: m['workQueue'] == null
          ? null
          : TaskQueue.fromJson(m['workQueue']),
    );
  }
  Map<String, dynamic> toJson() => {
    'runId': runId,
    'contentVersion': contentVersion,
    'balanceVersion': balanceVersion,
    'schemaVersion': schemaVersion,
    'seed': seed,
    'rngState': rngState,
    'timeMinutes': timeMinutes,
    'phase': phase,
    'slotIndex': slotIndex,
    'turnCount': turnCount,
    'presentationCount': presentationCount,
    'meters': meters,
    'scores': scores,
    'tasks': tasks.toJson(),
    'counters': counters.toJson(),
    'flags': flags,
    'playedEventIds': playedEventIds,
    'choiceHistory': choiceHistory,
    'majorCount': majorCount,
    'lastEventMajor': lastEventMajor,
    'peakBladder': peakBladder,
    'minimumHp': minimumHp,
    'minimumMental': minimumMental,
    'currentEventId': currentEventId,
    'eventInstanceId': eventInstanceId,
    'currentOutcomeId': currentOutcomeId,
    'outcomeText': outcomeText,
    'currentOutcome': currentOutcome?.toJson(),
    'handoverDone': handoverDone,
    'result': result?.toJson(),
    'workQueue': workQueue?.toJson(),
    'shiftPhase': shiftPhase?.name,
  };
}

sealed class GameCommand {
  const GameCommand();
}

class StartShift extends GameCommand {
  const StartShift();
}

class SelectChoice extends GameCommand {
  final String eventInstanceId, choiceId;
  const SelectChoice(this.eventInstanceId, this.choiceId);
}

class Next extends GameCommand {
  const Next();
}

class Transition {
  final GameState state;
  final String message;
  final int routineMinutes;
  const Transition(this.state, this.message, [this.routineMinutes = 0]);
}
