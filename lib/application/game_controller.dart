import 'package:flutter/foundation.dart';

import '../content/content_loader.dart';
import '../domain/engine.dart';
import '../domain/models.dart';
import '../domain/day_shift.dart';
import '../domain/unified_shift.dart';
import 'shift_history.dart';

abstract class ShiftStore {
  GameState? get current;
  OutcomeView? get outcomeView;
  int? get startedAtMillis;
  String? get error;
  bool get durable;
  bool get canRestoreBackup;
  Future<void> restoreBackup();
  void setOnChanged(VoidCallback callback);
  void setStartedAtMillis(int value);
  void save(GameState state, OutcomeView? outcomeView);
  void clear();
  Future<void> flush();
  Future<void> clearPersisted();
}

class MemoryShiftStore implements ShiftStore {
  GameState? _current;
  OutcomeView? _outcomeView;
  int? _startedAtMillis;
  @override
  String? get error => null;
  @override
  bool get durable => false;
  @override
  bool get canRestoreBackup => false;
  @override
  Future<void> restoreBackup() async {}
  @override
  void setOnChanged(VoidCallback callback) {}
  @override
  GameState? get current => _current;
  @override
  OutcomeView? get outcomeView => _outcomeView;
  @override
  int? get startedAtMillis => _startedAtMillis;
  @override
  void setStartedAtMillis(int value) => _startedAtMillis = value;
  @override
  void save(GameState state, OutcomeView? outcomeView) {
    _current = state;
    _outcomeView = outcomeView;
  }

  @override
  void clear() {
    _current = null;
    _outcomeView = null;
    _startedAtMillis = null;
  }

  @override
  Future<void> flush() async {}
  @override
  Future<void> clearPersisted() async => clear();
}

/// A display snapshot of one transition. GameState remains authoritative.
class OutcomeView {
  final int elapsedMinutes;
  final Map<String, int> meterChanges;
  final TaskState taskChanges;
  final int patientChange, teamChange;
  const OutcomeView(
    this.elapsedMinutes,
    this.meterChanges,
    this.taskChanges,
    this.patientChange,
    this.teamChange,
  );

  factory OutcomeView.between(GameState before, GameState after) => OutcomeView(
    after.timeMinutes - before.timeMinutes,
    Map.unmodifiable({
      for (final key in ['hp', 'mental', 'bladder', 'hunger'])
        key: after.meters[key]! - before.meters[key]!,
    }),
    TaskState(
      after.tasks.record - before.tasks.record,
      after.tasks.coordination - before.tasks.coordination,
      after.tasks.care - before.tasks.care,
    ),
    after.scores['patient']! - before.scores['patient']!,
    after.scores['team']! - before.scores['team']!,
  );
}

class GameController extends ChangeNotifier {
  final ContentBundle content;
  final ShiftStore store;
  final ShiftHistory history;
  late final GameEngine engine;
  GameState? _state;
  OutcomeView? _outcomeView;
  bool _sending = false;
  int _runSerial = 0;
  DateTime? _startedAt;
  Future<void>? _lastArchive;
  bool _archiveReady = true;
  String? archiveError;
  Future<void>? get lastArchive => _lastArchive;

  GameController(this.content, this.store, {ShiftHistory? history})
    : history = history ?? ShiftHistory(MemoryHistoryStore()) {
    engine = GameEngine(content.balance, content.events, content.titles);
    store.setOnChanged(notifyListeners);
    _state = store.current;
    if (_state?.phase == 'completed' && store.durable) _archiveReady = false;
    _outcomeView = store.outcomeView;
    if (store.startedAtMillis != null) {
      _startedAt = DateTime.fromMillisecondsSinceEpoch(store.startedAtMillis!);
    }
  }

  GameState? get state => _state;
  OutcomeView? get outcomeView => _outcomeView;
  bool get sending => _sending;
  bool get hasActiveShift => _state != null && _state!.phase != 'completed';
  bool get canStartNew => store.error == null && _archiveReady;
  List<ChoiceDefinition> get choices =>
      _state == null ? const [] : engine.choices(_state!);
  EventDefinition? get event {
    final id = _state?.currentEventId;
    for (final e in content.events) {
      if (e.eventId == id) return e;
    }
    return null;
  }

  void startNew({int? seed}) {
    if (!canStartNew) throw StateError('勤務結果の保存が完了していません');
    if (hasActiveShift) throw StateError('Active shift requires confirmation');
    _runSerial++;
    _startedAt = DateTime.now();
    store.setStartedAtMillis(_startedAt!.millisecondsSinceEpoch);
    final actualSeed =
        seed ?? (DateTime.now().microsecondsSinceEpoch & 0xffffffff);
    final initial = GameState.initial(
      'run-${DateTime.now().microsecondsSinceEpoch}-$_runSerial',
      actualSeed == 0 ? 1 : actualSeed,
      content.contentVersion,
      content.balanceVersion,
    );
    _outcomeView = null;
    if (content.events.length == 50) {
      _commit(Transition(startUnifiedShift(initial), '勤務開始'));
    } else {
      _commit(
        engine.dispatch(
          initial.copyWith(workQueue: generateRoutineTasks()),
          const StartShift(),
        ),
      );
    }
  }

  Future<void> replaceShift({int? seed}) async {
    await store.clearPersisted();
    _state = null;
    startNew(seed: seed);
  }

  Future<void> deleteAllRecords() async {
    await (_lastArchive ?? Future.value());
    await history.clear();
    await store.clearPersisted();
    _state = null;
    _outcomeView = null;
    _archiveReady = true;
    archiveError = null;
    notifyListeners();
  }

  Future<void> recoverCompleted() async {
    final state = _state;
    if (state?.phase == 'completed' && state?.result != null) {
      await _archive(state!);
    }
  }

  bool select(String instanceId, String choiceId) {
    final before = _state;
    if (store.error != null ||
        _sending ||
        before == null ||
        before.phase != 'awaitingChoice' ||
        before.eventInstanceId != instanceId) {
      return false;
    }
    _sending = true;
    notifyListeners();
    try {
      if (before.unifiedShift != null) {
        final event = content.events.firstWhere(
          (e) => e.eventId == before.currentEventId,
        );
        final choice = event.choices.firstWhere((c) => c.choiceId == choiceId);
        final random = nextShiftRandom(before.rngState);
        double effectiveWeight(OutcomeDefinition o) =>
            o.weight *
            o.weightModifiers.fold<double>(1, (w, m) => w * m.apply(before));
        final total = choice.outcomes.fold<double>(
          0,
          (sum, o) => sum + effectiveWeight(o),
        );
        var target = random / 4294967296 * total;
        var outcome = choice.outcomes.last;
        for (final candidate in choice.outcomes) {
          target -= effectiveWeight(candidate);
          if (target < 0) {
            outcome = candidate;
            break;
          }
        }
        final patient = before
            .unifiedShift!
            .patients[random % before.unifiedShift!.patients.length];
        final advanced = advanceUnifiedTime(
          before,
          outcome.effects.durationMinutes,
          balance: content.balance,
        );
        final now = advanced.timeMinutes;
        final queue = EventTaskAdapter.apply(
          before.workQueue!,
          event,
          outcome,
          now,
          patient,
          before.eventInstanceId!,
        );
        final shift = before.unifiedShift!;
        final patients = event.eventId == 'acute_warning'
            ? shift.patients
                  .map(
                    (p) => p.patientId == patient.patientId
                        ? p.copyWith(severity: PatientSeverity.high)
                        : p,
                  )
                  .toList()
            : shift.patients;
        final meters = Map<String, int>.from(advanced.meters);
        for (final entry in outcome.effects.meterDelta.entries) {
          meters[entry.key] = ((meters[entry.key] ?? 0) + entry.value).clamp(
            0,
            10000,
          );
        }
        final scores = Map<String, int>.from(before.scores);
        for (final entry in outcome.effects.scoreDelta.entries) {
          scores[entry.key] = ((scores[entry.key] ?? 0) + entry.value).clamp(
            0,
            10000,
          );
        }
        final next = advanced.copyWith(
          phase: 'showingOutcome',
          rngState: random,
          workQueue: queue,
          unifiedShift: shift.copyWith(patients: patients),
          meters: meters,
          scores: scores,
          turnCount: before.turnCount + 1,
          choiceHistory: [
            ...before.choiceHistory,
            '${before.eventInstanceId}:$choiceId:${outcome.outcomeId}',
          ],
          currentOutcomeId: outcome.outcomeId,
          currentOutcome: outcome,
          outcomeText: outcome.text,
        );
        _outcomeView = OutcomeView.between(before, next);
        _commit(Transition(next, outcome.text));
        return true;
      }
      final transition = engine.dispatch(
        before,
        SelectChoice(instanceId, choiceId),
      );
      _outcomeView = OutcomeView.between(before, transition.state);
      _commit(transition);
      return true;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  bool next() {
    final before = _state;
    if (store.error != null ||
        _sending ||
        before == null ||
        before.phase != 'showingOutcome') {
      return false;
    }
    _sending = true;
    notifyListeners();
    try {
      _outcomeView = null;
      if (before.unifiedShift != null) {
        _commit(
          Transition(
            before.copyWith(phase: 'taskSelection', clearCurrent: true),
            '次の業務',
          ),
        );
        return true;
      }
      _commit(engine.dispatch(before, const Next()));
      return true;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  bool completeWorkTask(String taskId) {
    final before = _state;
    if (before == null ||
        before.workQueue == null ||
        before.phase == 'completed' ||
        store.error != null) {
      return false;
    }
    if (before.unifiedShift != null) {
      try {
        final action = performUnifiedTask(
          before,
          taskId,
          events: content.events,
        );
        _state = action.state;
        store.save(_state!, null);
        notifyListeners();
        return true;
      } on StateError {
        return false;
      }
    }
    final available = availableTasks(before.workQueue!, before.timeMinutes);
    if (!available.any((t) => t.taskId == taskId)) return false;
    final task = available.firstWhere((t) => t.taskId == taskId);
    final now = before.timeMinutes + task.estimatedMinutes;
    final queue = advanceScheduledTasks(
      before.workQueue!.complete(taskId, now),
      before.timeMinutes,
      now,
    );
    _state = before.copyWith(timeMinutes: now, workQueue: queue);
    store.save(_state!, _outcomeView);
    notifyListeners();
    return true;
  }

  void advanceWorkClock(int minutes) {
    final before = _state;
    if (before == null ||
        before.workQueue == null ||
        before.phase == 'completed' ||
        minutes <= 0) {
      return;
    }
    final now = before.timeMinutes + minutes;
    if (before.unifiedShift != null) {
      if (before.phase != 'taskSelection') return;
      final decision = rollInterrupt(
        advanceUnifiedTime(before, minutes, balance: content.balance),
        events: content.events,
      );
      _state = decision.state;
      store.save(_state!, null);
      notifyListeners();
      return;
    }
    _state = before.copyWith(
      timeMinutes: now,
      workQueue: advanceScheduledTasks(
        before.workQueue!,
        before.timeMinutes,
        now,
      ),
    );
    store.save(_state!, _outcomeView);
    notifyListeners();
  }

  void setExitView(String view) {
    final s = _state;
    if (s == null ||
        s.unifiedShift == null ||
        s.timeMinutes < 1020 ||
        s.phase != 'taskSelection' ||
        !{'decision', 'handoff', 'work', 'confirm'}.contains(view)) {
      return;
    }
    _state = s.copyWith(unifiedShift: s.unifiedShift!.copyWith(exitView: view));
    store.save(_state!, null);
    notifyListeners();
  }

  bool handOffTasks(Iterable<String> ids) {
    final s = _state;
    if (s == null ||
        s.unifiedShift == null ||
        s.timeMinutes < 1020 ||
        s.phase != 'taskSelection' ||
        s.unifiedShift!.activeTaskId != null) {
      return false;
    }
    try {
      _state = s.copyWith(workQueue: s.workQueue!.handOff(ids, s.timeMinutes));
      store.save(_state!, null);
      notifyListeners();
      return true;
    } on StateError {
      return false;
    }
  }

  bool finishUnifiedShift() {
    final state = _state;
    if (state == null ||
        state.unifiedShift == null ||
        state.phase != 'taskSelection' ||
        state.workStatus?.canLeave != true) {
      return false;
    }
    final status = state.workStatus!;
    final queue = state.workQueue!;
    final incomplete = queue.pending
        .where((t) => t.taskType == WorkTaskType.documentation)
        .toList();
    final handed = queue.handedOff;
    final overdueRecords = incomplete
        .where(
          (t) => deadlineState(t, state.timeMinutes) == DeadlineState.overdue,
        )
        .length;
    final overdueHanded = handed
        .where((t) => t.deadline != null && t.handedOffAt! > t.deadline!)
        .length;
    final evaluated = engine.evaluate(state, 'normal');
    final penalty = handed.fold<int>(
      0,
      (sum, t) =>
          sum +
          (t.priority == WorkPriority.high
              ? 350
              : t.priority == WorkPriority.normal
              ? 180
              : 80) +
          (t.deadline != null && t.handedOffAt! > t.deadline! ? 180 : 0),
    );
    final axis = Map<String, int>.from(evaluated.axisScores);
    axis['team'] = (axis['team']! - penalty).clamp(0, 10000);
    axis['patient'] = (axis['patient']! - penalty ~/ 2).clamp(0, 10000);
    axis['safety'] =
        (axis['safety']! -
                incomplete.length * 550 -
                overdueRecords * 350 -
                overdueHanded * 100)
            .clamp(0, 10000);
    final adjusted = engine.evaluate(
      state.copyWith(
        scores: {
          ...state.scores,
          'patient': axis['patient']!,
          'team': axis['team']!,
          'risk': 10000 - axis['safety']!,
        },
      ),
      'normal',
    );
    final exitType = handed.isEmpty
        ? (incomplete.isEmpty ? 'cleanExit' : 'incompleteRecordExit')
        : (incomplete.isEmpty
              ? 'handedOffExit'
              : 'handedOffAndIncompleteRecordExit');
    final result = GameResult(
      'normal',
      adjusted.primaryTitleId,
      1020,
      state.timeMinutes,
      status.overtimeMinutes,
      state.peakBladder,
      const TaskState(0, 0, 0),
      const TaskState(0, 0, 0),
      state.counters,
      adjusted.axisScores,
      adjusted.grades,
      adjusted.earnedTitleIds,
      exitType: exitType,
      completedTaskCount: queue.completed.length,
      handedOffTaskCount: handed.length,
      incompleteRecordCount: incomplete.length,
      overdueTaskCount: status.overdueCount + overdueHanded,
      overdueRecordCount: overdueRecords,
      incompleteRecordPatients: incomplete
          .map((t) => t.patientId)
          .whereType<String>()
          .toSet()
          .length,
      urgentResponseCount: queue.completed
          .where((t) => t.priority == WorkPriority.urgent)
          .length,
      handedOffImportance: handed.fold<int>(
        0,
        (sum, t) =>
            sum +
            (t.priority == WorkPriority.high
                ? 3
                : t.priority == WorkPriority.normal
                ? 2
                : 1),
      ),
      completedTaskIds: queue.completed.map((t) => t.taskId).toList(),
      handedOffTaskIds: handed.map((t) => t.taskId).toList(),
    );
    _commit(
      Transition(state.copyWith(phase: 'completed', result: result), '勤務終了'),
    );
    return true;
  }

  void _commit(Transition transition) {
    final previous = _state;
    final queue = transition.state.workQueue;
    _state =
        queue == null ||
            previous == null ||
            transition.state.unifiedShift != null
        ? transition.state
        : transition.state.copyWith(
            workQueue: advanceScheduledTasks(
              queue,
              previous.timeMinutes,
              transition.state.timeMinutes,
            ),
          );
    store.save(_state!, _outcomeView);
    if (transition.state.phase == 'completed' &&
        transition.state.result != null) {
      _archiveReady = false;
      archiveError = null;
      _lastArchive = _archive(transition.state);
    }
    notifyListeners();
  }

  Future<void> _archive(GameState state) async {
    try {
      // The completed snapshot is durable before the history transaction.
      await store.flush();
      final record = ShiftRecord.completed(
        state,
        _startedAt ?? DateTime.now(),
        DateTime.now(),
        content.titles,
      );
      await history.add(record);
      // Analysis is derived from unique history IDs, so it needs no second write.
      await store.clearPersisted();
      _archiveReady = true;
      archiveError = null;
    } catch (_) {
      // Keep the completed snapshot for a retry on the next launch.
      _archiveReady = false;
      archiveError = '勤務結果を確定できませんでした。再読み込み後に再試行します。';
    }
    notifyListeners();
  }
}
