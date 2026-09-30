import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/application/game_controller.dart';
import 'package:kangoshi_quest/application/persistent_shift_store.dart';
import 'package:kangoshi_quest/application/shift_history.dart';
import 'package:kangoshi_quest/application/shift_summary.dart';
import 'package:kangoshi_quest/content/content_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../phase4/shift_history_test.dart' show record;

class FakePreferences implements SharedPreferencesAsync {
  final Map<String, String> values = {};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FailingPreferences extends FakePreferences {
  @override
  Future<void> setString(String key, String value) async =>
      throw StateError('disk full');
}

class FailingHistoryStore extends MemoryHistoryStore {
  @override
  Future<void> write(String value) async => throw StateError('disk full');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final content = ContentLoader.load(
    File('assets/content/balance_v1.json').readAsStringSync(),
    File('assets/content/titles_v1.json').readAsStringSync(),
    File('assets/content/fixture_events.json').readAsStringSync(),
  );

  test('choice, confirmed outcome, result display and next transition survive reload', () async {
    final prefs = FakePreferences();
    final store = PersistentShiftStore(prefs, content);
    final c = GameController(content, store)..startNew(seed: 42);
    await store.flush();
    final before = c.state!;
    final reloaded1 = PersistentShiftStore(prefs, content);
    await reloaded1.load();
    final c1 = GameController(content, reloaded1);
    expect(c1.state!.toJson(), before.toJson());
    expect(c1.state!.eventInstanceId, before.eventInstanceId);
    expect(c1.state!.rngState, before.rngState);

    expect(c1.select(before.eventInstanceId!, 'focused'), isTrue);
    await reloaded1.flush();
    final after = c1.state!;
    final reloaded2 = PersistentShiftStore(prefs, content);
    await reloaded2.load();
    final c2 = GameController(content, reloaded2);
    expect(c2.state!.phase, 'showingOutcome');
    expect(c2.state!.currentOutcomeId, after.currentOutcomeId);
    expect(c2.state!.currentOutcome!.toJson(), after.currentOutcome!.toJson());
    expect(c2.state!.rngState, after.rngState);
    expect(c2.state!.eventInstanceId, after.eventInstanceId);
    expect(c2.outcomeView!.elapsedMinutes, c1.outcomeView!.elapsedMinutes);

    expect(c2.next(), isTrue);
    await reloaded2.flush();
    final reloaded3 = PersistentShiftStore(prefs, content);
    await reloaded3.load();
    expect(reloaded3.current!.toJson(), c2.state!.toJson());
  });

  test(
    'corrupt JSON and unknown or mismatched versions keep original value',
    () async {
      final prefs = FakePreferences();
      for (final raw in [
        '{bad',
        '{"schemaVersion":99,"state":{}}',
        '{"schemaVersion":1,"startedAtMillis":1,"state":{"schemaVersion":1}}',
      ]) {
        await prefs.setString(PersistentShiftStore.key, raw);
        final store = PersistentShiftStore(prefs, content);
        await store.load();
        expect(store.error, isNotNull);
        expect(await prefs.getString(PersistentShiftStore.key), raw);
      }
      final goodStore = PersistentShiftStore(prefs, content);
      await goodStore.clearPersisted();
      final c = GameController(content, goodStore)..startNew(seed: 42);
      await goodStore.flush();
      final value = jsonDecode(
        (await prefs.getString(PersistentShiftStore.key))!,
      );
      value['state']['contentVersion'] = 'other';
      await prefs.setString(PersistentShiftStore.key, jsonEncode(value));
      final mismatch = PersistentShiftStore(prefs, content);
      await mismatch.load();
      expect(mismatch.error, isNotNull);
      expect(mismatch.current, isNull);
      expect(c.state, isNotNull);
    },
  );

  test('one generation backup can be explicitly restored', () async {
    final prefs = FakePreferences();
    final store = PersistentShiftStore(prefs, content);
    final c = GameController(content, store)..startNew(seed: 42);
    await store.flush();
    final original = c.state!;
    c.select(original.eventInstanceId!, 'focused');
    await store.flush();
    expect(await prefs.getString(PersistentShiftStore.backupKey), isNotNull);
    await prefs.setString(PersistentShiftStore.key, '{bad');
    final recovery = PersistentShiftStore(prefs, content);
    await recovery.load();
    expect(recovery.current!.toJson(), original.toJson());
    expect(recovery.canRestoreBackup, isTrue);
    expect(await prefs.getString(PersistentShiftStore.key), '{bad');
    await recovery.restoreBackup();
    expect(recovery.error, isNull);
    expect((await prefs.getString(PersistentShiftStore.key))!, isNot('{bad'));
  });

  test(
    'save failure is visible and does not archive a completed snapshot',
    () async {
      final store = PersistentShiftStore(FailingPreferences(), content);
      GameController(content, store).startNew(seed: 42);
      await expectLater(store.flush(), throwsStateError);
      expect(store.error, isNotNull);
    },
  );

  test(
    'completed snapshot replay archives once and clears active storage',
    () async {
      final completed = GameController(content, MemoryShiftStore())
        ..startNew(seed: 42);
      for (final choice in ['focused', 'quick', 'quick', 'short']) {
        completed.select(completed.state!.eventInstanceId!, choice);
        completed.next();
      }
      expect(completed.state!.phase, 'completed');
      final prefs = FakePreferences();
      final store = PersistentShiftStore(prefs, content)
        ..setStartedAtMillis(DateTime.now().millisecondsSinceEpoch);
      store.save(completed.state!, null);
      await store.flush();
      final history = ShiftHistory(MemoryHistoryStore());
      await history.load();
      final first = PersistentShiftStore(prefs, content);
      await first.load();
      await GameController(content, first, history: history).recoverCompleted();
      expect(history.records, hasLength(1));
      expect(await prefs.getString(PersistentShiftStore.key), isNull);

      // Simulate a stop after the history write but before active deletion.
      store.save(completed.state!, null);
      await store.flush();
      final second = PersistentShiftStore(prefs, content);
      await second.load();
      await GameController(
        content,
        second,
        history: history,
      ).recoverCompleted();
      expect(history.records, hasLength(1));
    },
  );

  test(
    'failed history write keeps completed shift and prevents overwrite',
    () async {
      final prefs = FakePreferences();
      final store = PersistentShiftStore(prefs, content);
      final history = ShiftHistory(FailingHistoryStore());
      await history.load();
      final controller = GameController(content, store, history: history)
        ..startNew(seed: 42);
      for (final choice in ['focused', 'quick', 'quick', 'short']) {
        controller.select(controller.state!.eventInstanceId!, choice);
        controller.next();
      }
      await controller.lastArchive;
      expect(controller.state!.phase, 'completed');
      expect(controller.canStartNew, isFalse);
      expect(() => controller.startNew(seed: 1), throwsStateError);
      expect(await prefs.getString(PersistentShiftStore.key), isNotNull);
    },
  );

  test('delete all removes active shift and history', () async {
    final prefs = FakePreferences();
    final store = PersistentShiftStore(prefs, content);
    final history = ShiftHistory(MemoryHistoryStore());
    await history.load();
    final controller = GameController(content, store, history: history)
      ..startNew(seed: 42);
    await store.flush();
    await history.add(record('old', 2000));
    await controller.deleteAllRecords();
    expect(controller.state, isNull);
    expect(history.records, isEmpty);
    expect(await prefs.getString(PersistentShiftStore.key), isNull);
    expect(await prefs.getString(PersistentShiftStore.backupKey), isNull);
  });

  test(
    'history ID and derived totals prevent duplicate counting; delete resets',
    () async {
      final history = ShiftHistory(MemoryHistoryStore());
      await history.load();
      final a = record('a', 2000);
      await Future.wait([history.add(a), history.add(a)]);
      await history.add(record('b', 3000));
      final data = ShiftSummary.fromRecords(history.records);
      expect(data.total, 2);
      expect(data.onTime, 2);
      expect(data.titleCounts[a.title], 2);
      expect(data.axisAverages['patient'], 5000);
      expect(shareText(a), contains('退勤時刻 17:15'));
      expect(shareText(a), contains('#看護師クエスト'));
      expect(shareText(a), isNot(contains('seed')));
      await history.clear();
      expect(ShiftSummary.fromRecords(history.records).total, 0);
      expect((await history.store.read()), isNull);
    },
  );
}
