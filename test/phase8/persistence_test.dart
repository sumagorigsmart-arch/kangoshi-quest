import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/application/game_controller.dart';
import 'package:kangoshi_quest/application/persistent_shift_store.dart';
import 'package:kangoshi_quest/content/content_loader.dart';

import '../phase5/phase5_test.dart' show FakePreferences;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final content = ContentLoader.load(
    File('assets/content/balance_v1.json').readAsStringSync(),
    File('assets/content/titles_v1.json').readAsStringSync(),
    File('assets/content/fixture_events.json').readAsStringSync(),
  );

  test('task completion and documentation restore after reload', () async {
    final prefs = FakePreferences();
    final store = PersistentShiftStore(prefs, content);
    final controller = GameController(content, store)..startNew(seed: 42);
    expect(controller.completeWorkTask('morning_handoff'), isTrue);
    expect(controller.completeWorkTask('morning_vitals'), isTrue);
    await store.flush();
    final raw =
        jsonDecode((await prefs.getString(PersistentShiftStore.key))!) as Map;
    expect(raw['schemaVersion'], 2);
    final restored = PersistentShiftStore(prefs, content);
    await restored.load();
    expect(restored.error, isNull);
    expect(restored.current!.timeMinutes, 545);
    expect(restored.current!.workQueue!.documentationCount, 1);
    expect(restored.current!.workQueue!.completed.length, 2);
  });

  test('phase 7 envelope migrates without losing the active shift', () async {
    final prefs = FakePreferences();
    final store = PersistentShiftStore(prefs, content);
    GameController(content, store).startNew(seed: 42);
    await store.flush();
    final raw =
        jsonDecode((await prefs.getString(PersistentShiftStore.key))!) as Map;
    raw['schemaVersion'] = 1;
    (raw['state'] as Map).remove('workQueue');
    await prefs.setString(PersistentShiftStore.key, jsonEncode(raw));
    final legacy = PersistentShiftStore(prefs, content);
    await legacy.load();
    expect(legacy.error, isNull);
    expect(legacy.current!.workQueue, isNull);
    final controller = GameController(content, legacy);
    expect(controller.hasActiveShift, isTrue);
    expect(
      controller.select(controller.state!.eventInstanceId!, 'focused'),
      isTrue,
    );
    await legacy.flush();
    final migrated =
        jsonDecode((await prefs.getString(PersistentShiftStore.key))!) as Map;
    expect(migrated['schemaVersion'], 2);
  });
}
