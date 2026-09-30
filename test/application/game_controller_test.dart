import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/application/game_controller.dart';
import 'package:kangoshi_quest/content/content_loader.dart';
import 'package:kangoshi_quest/domain/models.dart';

GameController fixtureController([ShiftStore? store]) => GameController(
  ContentLoader.load(
    File('assets/content/balance_v1.json').readAsStringSync(),
    File('assets/content/titles_v1.json').readAsStringSync(),
    File('assets/content/fixture_events.json').readAsStringSync(),
  ),
  store ?? MemoryShiftStore(),
);

void main() {
  test(
    'same event instance applies exactly once; outcome rejects other choice',
    () {
      final c = fixtureController()..startNew(seed: 42);
      final id = c.state!.eventInstanceId!;
      expect(c.select(id, 'focused'), isTrue);
      final after = c.state!;
      expect(after.phase, 'showingOutcome');
      expect(c.select(id, 'focused'), isFalse);
      expect(c.select(id, 'slow'), isFalse);
      expect(identical(c.state, after), isTrue);
      expect(after.turnCount, 1);
      expect(after.choiceHistory, hasLength(1));
      expect(after.currentOutcomeId, 'done');
    },
  );

  test('next advances once and cannot skip another event', () {
    final c = fixtureController()..startNew(seed: 42);
    c.select(c.state!.eventInstanceId!, 'focused');
    expect(c.next(), isTrue);
    final presented = c.state!;
    expect(presented.currentEventId, 'f02');
    expect(c.next(), isFalse);
    expect(identical(c.state, presented), isTrue);
  });

  test(
    'controller exposes domain state directly and saves each transition',
    () {
      final store = MemoryShiftStore();
      final c = fixtureController(store)..startNew(seed: 42);
      expect(identical(c.state, store.current), isTrue);
      final before = c.state!;
      expect(c.state!.timeMinutes, 510);
      expect(c.state!.meters['hp'], 8000);
      expect(c.state!.tasks.toJson(), const TaskState(4, 1, 1).toJson());
      c.select(before.eventInstanceId!, 'focused');
      expect(identical(c.state, store.current), isTrue);
      final after = c.state!;
      expect(
        c.outcomeView!.elapsedMinutes,
        after.timeMinutes - before.timeMinutes,
      );
      expect(
        c.outcomeView!.meterChanges['hp'],
        after.meters['hp']! - before.meters['hp']!,
      );
      expect(
        c.outcomeView!.taskChanges.record,
        after.tasks.record - before.tasks.record,
      );
      final resumed = fixtureController(store);
      expect(identical(resumed.state, after), isTrue);
      expect(
        resumed.outcomeView!.elapsedMinutes,
        c.outcomeView!.elapsedMinutes,
      );
      expect(() => resumed.startNew(seed: 2), throwsStateError);
    },
  );

  test('closing task commands clear domain tasks before final handover', () {
    final c = fixtureController()..startNew(seed: 42);
    void choose(String id) {
      expect(c.select(c.state!.eventInstanceId!, id), isTrue);
      expect(c.next(), isTrue);
    }

    choose('slow');
    choose('quick');
    choose('quick');
    expect(c.state!.currentEventId, 'closing_tasks');
    expect(c.state!.tasks.toJson(), const TaskState(4, 1, 1).toJson());
    choose('record');
    expect(c.state!.tasks.record, 2);
    choose('record');
    choose('coordination');
    choose('care');
    expect(c.state!.currentEventId, 'final_handover');
    expect(c.state!.tasks.total, 0);
    choose('short');
    expect(c.state!.phase, 'completed');
    expect(c.state!.result?.reason, 'normal');
  });
}
