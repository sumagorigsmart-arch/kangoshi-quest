import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/content/content_loader.dart';
import 'package:kangoshi_quest/domain/engine.dart';
import 'package:kangoshi_quest/domain/models.dart';

late ContentBundle bundle;
late GameEngine engine;
GameState fresh([int seed = 42]) => GameState.initial(
  'test',
  seed,
  bundle.contentVersion,
  bundle.balanceVersion,
);
GameState started() => engine.dispatch(fresh(), const StartShift()).state;
GameState choose(GameState s, String id) =>
    engine.dispatch(s, SelectChoice(s.eventInstanceId!, id)).state;
GameState next(GameState s) => engine.dispatch(s, const Next()).state;
GameState run(List<String> choices) {
  var s = started();
  for (final id in choices) {
    s = choose(s, id);
    if (s.phase != 'completed') s = next(s);
  }
  return s;
}

void main() {
  setUpAll(() {
    bundle = ContentLoader.load(
      File('assets/content/balance_v1.json').readAsStringSync(),
      File('assets/content/titles_v1.json').readAsStringSync(),
      File('assets/content/fixture_events.json').readAsStringSync(),
    );
    engine = GameEngine(bundle.balance, bundle.events, bundle.titles);
  });
  test('same seed and choices, and JSON roundtrip continuation', () {
    final a = run(['focused', 'quick', 'quick', 'short']);
    final b = run(['focused', 'quick', 'quick', 'short']);
    expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    var s = started();
    s = choose(s, 'focused');
    expect(s.currentOutcome?.outcomeId, 'done');
    s = GameState.fromJson(jsonDecode(jsonEncode(s.toJson())));
    s = next(s);
    s = choose(s, 'quick');
    s = next(s);
    s = choose(s, 'quick');
    s = next(s);
    s = choose(s, 'short');
    s = next(s);
    expect(jsonEncode(s.toJson()), jsonEncode(a.toJson()));
  });
  test('16:30 22-minute action skips 16:45 and advances to 17:00', () {
    var s = started();
    s = choose(s, 'focused');
    s = next(s);
    expect(s.timeMinutes, 990);
    s = choose(s, 'quick');
    expect(s.timeMinutes, 1012);
    final t = engine.dispatch(s, const Next());
    expect(t.routineMinutes, 8);
    expect(t.state.timeMinutes, 1020);
    expect(t.state.currentEventId, 'f03');
  });
  test(
    'long action consumes all natural time; fatigue at most five minutes',
    () {
      var s = started().copyWith(
        meters: {'hp': 1999, 'mental': 1999, 'bladder': 1500, 'hunger': 1000},
      );
      s = choose(s, 'focused');
      expect(s.timeMinutes, 994);
      expect(s.meters['hp'], 0);
      expect(s.meters['mental'], 1031);
      expect(s.meters['bladder'], 7308);
    },
  );
  test('tasks never negative and zero completion does not count; record transfer rejected by loader', () {
    var s = started().copyWith(tasks: const TaskState(0, 0, 0));
    s = choose(s, 'focused');
    expect(s.tasks.total, 0);
    expect(s.counters.completedRecord, 0);
    expect(s.outcomeText, '対象の残務を整理・確認した。');
  });
  test('GameState defensively copies mutable maps', () {
    final meters = {
      'hp': 8000,
      'mental': 7500,
      'bladder': 1500,
      'hunger': 1000,
    };
    final s = fresh().copyWith(meters: meters);
    meters['hp'] = 0;
    expect(s.meters['hp'], 8000);
    expect(() => s.meters['hp'] = 0, throwsUnsupportedError);
  });
  test('fixture ontime, overtime, forced relief', () {
    final ontime = run(['focused', 'quick', 'quick', 'short']);
    expect(ontime.result!.finishTime, 1035);
    expect(ontime.result!.primaryTitleId, 'ontime');
    final late = run(['focused', 'quick', 'slow', 'short']);
    expect(late.result!.finishTime, 1041);
    expect(late.result!.earnedTitleIds, isNot(contains('ontime')));
    final relief = run(['overrun']);
    expect(relief.timeMinutes, 1230);
    expect(relief.result!.reason, 'forcedRelief');
    expect(relief.tasks.total, 6);
    expect(relief.result!.earnedTitleIds, isNot(contains('ontime')));
  });
  test('17:15 versus 17:16, remaining tasks and missing handover', () {
    final base = started().copyWith(
      timeMinutes: 1030,
      phase: 'showingOutcome',
      tasks: const TaskState(0, 0, 0),
      handoverDone: true,
    );
    expect(next(base).result!.primaryTitleId, 'ontime');
    expect(
      next(base.copyWith(timeMinutes: 1036)).result!.earnedTitleIds,
      isNot(contains('ontime')),
    );
    final pending = base.copyWith(tasks: const TaskState(1, 0, 0));
    expect(next(pending).phase, 'awaitingChoice');
    expect(
      next(base.copyWith(handoverDone: false)).currentEventId,
      'final_handover',
    );
  });
  test('hard stop partial, exact boundary, and thirty selections', () {
    final partial = run(['overrun']);
    expect(partial.result!.reason, 'forcedRelief');
    expect(partial.counters.completedRecord, 0);
    expect(partial.outcomeText, '対応の途中で応援へ引き継いだ');
    final s = started().copyWith(
      timeMinutes: 1225,
      phase: 'showingOutcome',
      tasks: const TaskState(0, 0, 0),
      handoverDone: true,
    );
    expect(next(s).result!.reason, 'normal');
    final thirty = started().copyWith(
      timeMinutes: 1100,
      turnCount: 30,
      phase: 'showingOutcome',
    );
    expect(next(thirty).result!.reason, 'forcedRelief');
  });
  test('onAppear once and duplicate selection rejected', () {
    var s = started();
    s = choose(s, 'focused');
    s = next(s);
    expect(s.counters.callCount, 1);
    final before = s;
    s = choose(s, 'quick');
    expect(
      () => choose(before.copyWith(phase: 'showingOutcome'), 'quick'),
      throwsStateError,
    );
    s = next(s);
    expect(s.counters.callCount, 1);
  });
  test('eligibility conditions, major limit and fallback', () {
    final s = started().copyWith(timeMinutes: 600);
    expect(engine.eligible(s), isEmpty);
    expect(
      engine
          .dispatch(s.copyWith(phase: 'showingOutcome'), const Next())
          .state
          .currentEventId,
      'fallback',
    );
    final major = EventDefinition(
      eventId: 'm',
      title: '重大',
      description: '重大',
      category: 'acute',
      minTime: 510,
      maxTime: 1020,
      weight: 1,
      tags: ['major'],
      conditions: [],
      choices: bundle.events.first.choices,
    );
    final e = GameEngine(bundle.balance, [major], bundle.titles);
    expect(e.eligible(fresh().copyWith(majorCount: 2)), isEmpty);
    expect(e.eligible(fresh().copyWith(lastEventMajor: true)), isEmpty);
  });
  test('single candidate and single branch preserve RNG; weighted tags and conditions', () {
    final s = started();
    expect(s.rngState, 42);
    expect(choose(s, 'focused').rngState, 42);
    final base = bundle.events[1];
    final late = fresh().copyWith(
      timeMinutes: 990,
      meters: {'hp': 8000, 'mental': 7500, 'bladder': 8500, 'hunger': 8500},
    );
    final weighted = EventDefinition(
      eventId: 'w',
      title: 'w',
      description: 'w',
      category: 'w',
      minTime: 510,
      maxTime: 1020,
      weight: 2,
      tags: ['lateShift', 'crusher', 'toilet', 'food'],
      conditions: [const Condition('meters.bladder', 'gte', 8500)],
      choices: base.choices,
    );
    expect(engine.effectiveEventWeight(weighted, late), 67.5);
    final other = GameEngine(bundle.balance, [weighted], bundle.titles);
    expect(other.eligible(late).length, 1);
    expect(
      other.eligible(
        late.copyWith(
          meters: {'hp': 8000, 'mental': 7500, 'bladder': 8499, 'hunger': 8500},
        ),
      ),
      isEmpty,
    );
    expect(other.eligible(late.copyWith(timeMinutes: 509)), isEmpty);
  });
  test('random long outcome uses full duration and persists chosen branch', () {
    const long = OutcomeDefinition(
      'long',
      '長い枝',
      1,
      Effects(durationMinutes: 100),
    );
    const short = OutcomeDefinition(
      'short',
      '短い枝',
      1,
      Effects(durationMinutes: 10),
    );
    final choice = ChoiceDefinition('go', '進む', '分岐', 'work', [long, short]);
    final event = EventDefinition(
      eventId: 'random',
      title: '分岐',
      description: '分岐',
      category: 'routine',
      minTime: 510,
      maxTime: 510,
      weight: 1,
      tags: [],
      conditions: [],
      choices: [choice, choice, choice],
    );
    final e = GameEngine(bundle.balance, [event], bundle.titles);
    var s = e.dispatch(fresh(), const StartShift()).state;
    s = e.dispatch(s, SelectChoice(s.eventInstanceId!, 'go')).state;
    expect(s.currentOutcomeId, 'long');
    expect(s.timeMinutes, 610);
    expect(s.meters['hp'], 7500);
    expect(s.meters['bladder'], 2700);
    expect(s.rngState, isNot(42));
    expect(
      GameState.fromJson(jsonDecode(jsonEncode(s.toJson()))).currentOutcomeId,
      'long',
    );
  });
  test(
    'exact hard stop and thirty choices prefer normal only when complete',
    () {
      final base = started().copyWith(
        currentEventId: 'f03',
        timeMinutes: 1229,
        phase: 'awaitingChoice',
        tasks: const TaskState(0, 0, 0),
        handoverDone: true,
      );
      var s = choose(base, 'quick');
      expect(s.timeMinutes, 1230);
      expect(next(s).result!.reason, 'normal');
      s = choose(base.copyWith(tasks: const TaskState(1, 0, 0)), 'quick');
      expect(next(s).result!.reason, 'forcedRelief');
      final thirty = started().copyWith(
        timeMinutes: 1036,
        turnCount: 30,
        phase: 'showingOutcome',
        tasks: const TaskState(0, 0, 0),
        handoverDone: true,
      );
      expect(next(thirty).result!.reason, 'normal');
    },
  );
  test('peak bladder is captured before toilet reset', () {
    const toilet = Effects(
      durationMinutes: 3,
      setBladderAfter: 1000,
      toiletCount: 1,
    );
    final choice = ChoiceDefinition('toilet', 'トイレ', '3分', 'selfCare', [
      const OutcomeDefinition('done', '行けた', 1, toilet),
    ]);
    final event = EventDefinition(
      eventId: 'toilet',
      title: 'トイレ',
      description: 'トイレ',
      category: 'selfCare',
      minTime: 510,
      maxTime: 510,
      weight: 1,
      tags: ['toilet'],
      conditions: [],
      choices: [choice, choice, choice],
    );
    final e = GameEngine(bundle.balance, [event], bundle.titles);
    var s = e
        .dispatch(fresh(), const StartShift())
        .state
        .copyWith(
          meters: {'hp': 8000, 'mental': 7500, 'bladder': 9490, 'hunger': 1000},
        );
    s = e.dispatch(s, SelectChoice(s.eventInstanceId!, 'toilet')).state;
    expect(s.meters['bladder'], 1000);
    expect(s.peakBladder, 9526);
    expect(
      e.evaluate(s, 'forcedRelief').earnedTitleIds,
      contains('bladder_limit'),
    );
  });
  test('grade boundaries, multiple titles and peak bladder', () {
    var s = started().copyWith(
      timeMinutes: 1035,
      phase: 'showingOutcome',
      tasks: const TaskState(0, 0, 0),
      handoverDone: true,
      peakBladder: 9600,
      scores: {'patient': 8200, 'team': 7000, 'risk': 4200},
    );
    final result = engine.evaluate(s, 'normal');
    expect(result.grades['patient'], 'S');
    expect(result.grades['team'], 'A');
    expect(result.grades['safety'], 'B');
    expect(
      result.earnedTitleIds,
      containsAll(['ontime', 'bladder_limit', 'survivor']),
    );
    expect(result.primaryTitleId, 'ontime');
    s = s.copyWith(scores: {'patient': 8199, 'team': 6999, 'risk': 4201});
    final r = engine.evaluate(s, 'normal');
    expect(r.grades['patient'], 'A');
    expect(r.grades['team'], 'B');
    expect(r.grades['safety'], 'C');
    final tied = GameEngine(bundle.balance, bundle.events, [
      const TitleDefinition('z', 'Z', 10, []),
      const TitleDefinition('a', 'A', 10, []),
    ]);
    expect(tied.evaluate(s, 'normal').primaryTitleId, 'a');
  });
}
