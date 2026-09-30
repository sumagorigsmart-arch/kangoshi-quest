import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/application/shift_history.dart';
import 'package:kangoshi_quest/domain/models.dart';

import '../application/game_controller_test.dart' show fixtureController;

GameResult result({String reason = 'normal', int overtime = 0}) => GameResult(
  reason,
  'survivor',
  1035,
  1035 + overtime,
  overtime,
  3000,
  const TaskState(0, 0, 0),
  const TaskState(0, 0, 0),
  const Counters(),
  {'patient': 5000, 'team': 5000, 'health': 5000, 'safety': 5000},
  {'patient': 'C', 'team': 'C', 'health': 'C', 'safety': 'C'},
  ['survivor'],
);

ShiftRecord record(String id, int ended, {GameResult? value}) => ShiftRecord(
  id: id,
  contentVersion: 'test',
  balanceVersion: 'test',
  title: '今日もなんとか生還した者',
  seed: 17,
  startedAtMillis: ended - 1000,
  endedAtMillis: ended,
  startMinutes: 510,
  eventCount: 3,
  result: value ?? result(),
  choices: const ['focused', 'quick'],
);

void main() {
  test('controller archives one completed shift with domain title', () async {
    final c = fixtureController()..startNew(seed: 42);
    for (final choice in ['focused', 'quick', 'quick', 'short']) {
      expect(c.select(c.state!.eventInstanceId!, choice), isTrue);
      expect(c.next(), isTrue);
    }
    await c.lastArchive;
    expect(c.history.records, hasLength(1));
    final saved = c.history.records.single;
    expect(saved.id, c.state!.runId);
    expect(saved.result.primaryTitleId, c.state!.result!.primaryTitleId);
    expect(saved.title, isNotEmpty);
    expect(saved.seed, 42);
    expect(saved.choices, c.state!.choiceHistory);
    await c.history.add(saved);
    expect(c.history.records, hasLength(1));
  });

  test('completed records persist, reload and sort newest first', () async {
    final store = MemoryHistoryStore();
    final history = ShiftHistory(store);
    await history.load();
    expect(history.records, isEmpty);
    await history.add(record('old', 2000));
    await history.add(record('new', 3000));
    final reloaded = ShiftHistory(store);
    await reloaded.load();
    expect(reloaded.records.map((e) => e.id), ['new', 'old']);
    expect(reloaded.records.first.result.axisScores['patient'], 5000);
    expect(reloaded.records.first.choices, ['focused', 'quick']);
  });

  test('concurrent duplicate saves yield one record', () async {
    final history = ShiftHistory(MemoryHistoryStore());
    await history.load();
    await Future.wait([
      history.add(record('same', 2000)),
      history.add(record('same', 2000)),
    ]);
    expect(history.records, hasLength(1));
  });

  test('incomplete shifts cannot be made into records', () {
    final state = GameState.initial('id', 1, 'v', 'v');
    expect(
      () => ShiftRecord.completed(state, DateTime.now(), DateTime.now(), []),
      throwsStateError,
    );
  });

  test(
    'corrupt, missing and unknown version are visible and do not crash',
    () async {
      for (final raw in [
        '',
        '{bad',
        '{"schemaVersion":99,"records":[]}',
        '{"schemaVersion":1,"records":[{}]}',
      ]) {
        final store = MemoryHistoryStore()..value = raw;
        final history = ShiftHistory(store);
        await history.load();
        expect(history.records, isEmpty);
        expect(history.error, isNotNull);
        expect(() => history.add(record('a', 2000)), throwsStateError);
      }
    },
  );

  test('record version and fields are validated', () {
    final data = record('a', 2000).toJson();
    expect(ShiftRecord.fromJson(jsonDecode(jsonEncode(data))).id, 'a');
    data['schemaVersion'] = 2;
    expect(() => ShiftRecord.fromJson(data), throwsFormatException);
  });
}
