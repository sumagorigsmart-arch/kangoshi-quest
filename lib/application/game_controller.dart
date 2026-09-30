import 'package:flutter/foundation.dart';

import '../content/content_loader.dart';
import '../domain/engine.dart';
import '../domain/models.dart';

abstract class ShiftStore {
  GameState? get current;
  OutcomeView? get outcomeView;
  void save(GameState state, OutcomeView? outcomeView);
  void clear();
}

class MemoryShiftStore implements ShiftStore {
  GameState? _current;
  OutcomeView? _outcomeView;
  @override
  GameState? get current => _current;
  @override
  OutcomeView? get outcomeView => _outcomeView;
  @override
  void save(GameState state, OutcomeView? outcomeView) {
    _current = state;
    _outcomeView = outcomeView;
  }

  @override
  void clear() {
    _current = null;
    _outcomeView = null;
  }
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
  late final GameEngine engine;
  GameState? _state;
  OutcomeView? _outcomeView;
  bool _sending = false;
  int _runSerial = 0;

  GameController(this.content, this.store) {
    engine = GameEngine(content.balance, content.events, content.titles);
    _state = store.current;
    _outcomeView = store.outcomeView;
  }

  GameState? get state => _state;
  OutcomeView? get outcomeView => _outcomeView;
  bool get sending => _sending;
  bool get hasActiveShift => _state != null && _state!.phase != 'completed';
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
    if (hasActiveShift) throw StateError('Active shift requires confirmation');
    _runSerial++;
    final actualSeed =
        seed ?? (DateTime.now().microsecondsSinceEpoch & 0xffffffff);
    final initial = GameState.initial(
      'run-${DateTime.now().microsecondsSinceEpoch}-$_runSerial',
      actualSeed == 0 ? 1 : actualSeed,
      content.contentVersion,
      content.balanceVersion,
    );
    _outcomeView = null;
    _commit(engine.dispatch(initial, const StartShift()));
  }

  void replaceShift({int? seed}) {
    store.clear();
    _state = null;
    startNew(seed: seed);
  }

  bool select(String instanceId, String choiceId) {
    final before = _state;
    if (_sending ||
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
    if (_sending || before == null || before.phase != 'showingOutcome') {
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

  void _commit(Transition transition) {
    _state = transition.state;
    store.save(transition.state, _outcomeView);
    notifyListeners();
  }
}
