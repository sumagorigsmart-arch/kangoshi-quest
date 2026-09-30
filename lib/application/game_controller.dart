import 'package:flutter/foundation.dart';

import '../content/content_loader.dart';
import '../domain/engine.dart';
import '../domain/models.dart';
import '../domain/day_shift.dart';
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
    _commit(
      engine.dispatch(
        initial.copyWith(workQueue: generateRoutineTasks()),
        const StartShift(),
      ),
    );
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

  void _commit(Transition transition) {
    final previous = _state;
    final queue = transition.state.workQueue;
    _state = queue == null || previous == null
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
