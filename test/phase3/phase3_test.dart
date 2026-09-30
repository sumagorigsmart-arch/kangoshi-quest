import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/content/content_loader.dart';
import 'package:kangoshi_quest/domain/engine.dart';
import 'package:kangoshi_quest/domain/models.dart';
import 'package:kangoshi_quest/qa/simulation.dart';

ContentBundle official() => ContentLoader.load(
  File('assets/content/balance_v1.json').readAsStringSync(),
  File('assets/content/titles_v1.json').readAsStringSync(),
  File('assets/content/events_phase3.json').readAsStringSync(),
);

void main() {
  test('official pool has 50 unique events and 13 uncertain events', () {
    final content = official();
    expect(content.events, hasLength(50));
    expect(content.events.map((e) => e.eventId).toSet(), hasLength(50));
    expect(
      content.events
          .where((e) => e.choices.any((c) => c.outcomes.length > 1))
          .length,
      greaterThanOrEqualTo(10),
    );
    expect(
      content.events
          .expand((e) => e.choices)
          .expand((c) => c.outcomes)
          .every((o) => o.effects.durationMinutes <= 30),
      isTrue,
    );
    expect(
      content.events.any(
        (e) => e.choices.any(
          (c) => c.outcomes.any((o) => o.effects.durationMinutes == 479),
        ),
      ),
      isFalse,
    );
  });

  test('multiple seeds terminate, preserve invariants and replay exactly', () {
    final content = official();
    for (var seed = 1; seed <= 120; seed++) {
      final policy = ['efficient', 'mixed', 'careful', 'quick'][seed % 4];
      final first = runShift(content, seed, policy: policy);
      final second = runShift(
        content,
        seed,
        replayChoices: first.state.choiceHistory,
      );
      expect(stateFingerprint(second.state), stateFingerprint(first.state));
      expect(first.state.phase, 'completed');
      expect(
        first.state.choiceHistory.length,
        lessThanOrEqualTo(content.balance.maxChoices),
      );
    }
  });

  test('saved on-time QA case obeys exact time, zero tasks and handover', () {
    final content = official();
    final fixture = jsonDecode(
      File('test/phase3/on_time_seed17.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(fixture['contentVersion'], content.contentVersion);
    final run = runShift(
      content,
      fixture['seed'] as int,
      replayChoices: List<String>.from(fixture['choiceHistory']),
    );
    expect(run.state.timeMinutes, 1035);
    expect(run.state.tasks.total, 0);
    expect(run.state.handoverDone, isTrue);
    expect(run.state.result!.reason, 'normal');
    expect(run.state.result!.overtimeMinutes, 0);
  });

  test('fallback remains available and repeated use is detected', () {
    final content = official();
    final empty = ContentBundle(
      content.contentVersion,
      content.balanceVersion,
      content.balance,
      const [],
      content.titles,
    );
    final run = runShift(empty, 5);
    expect(run.state.phase, 'completed');
    expect(run.maxFallbackStreak, greaterThan(1));
    expect(run.eventTrace, contains('fallback'));
  });

  test('outcome remains fixed for the displayed event instance', () {
    final content = official();
    final engine = GameEngine(content.balance, content.events, content.titles);
    final before = engine
        .dispatch(
          GameState.initial(
            'fixed',
            11,
            content.contentVersion,
            content.balanceVersion,
          ),
          const StartShift(),
        )
        .state;
    final choice = engine.choices(before).first;
    final after = engine
        .dispatch(
          before,
          SelectChoice(before.eventInstanceId!, choice.choiceId),
        )
        .state;
    expect(after.eventInstanceId, before.eventInstanceId);
    expect(after.currentOutcomeId, isNotNull);
    expect(after.currentOutcome!.outcomeId, after.currentOutcomeId);
    expect(after.outcomeText, after.currentOutcome!.text);
    expect(
      () => engine.dispatch(
        after,
        SelectChoice(before.eventInstanceId!, choice.choiceId),
      ),
      throwsStateError,
    );
  });
}
