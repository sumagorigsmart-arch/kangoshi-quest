import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/application/game_controller.dart';
import 'package:kangoshi_quest/application/persistent_shift_store.dart';
import 'package:kangoshi_quest/content/content_loader.dart';
import 'package:kangoshi_quest/domain/day_shift.dart';
import 'package:kangoshi_quest/domain/models.dart';
import 'package:kangoshi_quest/domain/unified_shift.dart';

import '../phase5/phase5_test.dart' show FakePreferences;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final content = ContentLoader.load(
    File('assets/content/balance_v1.json').readAsStringSync(),
    File('assets/content/titles_v1.json').readAsStringSync(),
    File('assets/content/events_phase3.json').readAsStringSync(),
  );
  GameState fresh([int seed = 42]) => startUnifiedShift(
    GameState.initial(
      'phase9-$seed',
      seed,
      content.contentVersion,
      content.balanceVersion,
    ),
  );

  test('six anonymous patients and patient-specific routine work', () {
    final state = fresh();
    expect(state.unifiedShift!.patients, hasLength(6));
    expect(state.unifiedShift!.patients.first.bedLabel, '301-A');
    expect(
      state.workQueue!.routine.where((t) => t.patientId != null).length,
      greaterThan(20),
    );
    expect(state.workQueue!.routine.any((t) => t.patientId == null), isTrue);
    expect(
      state.workQueue!.routine.any(
        (t) => t.patientId == 'p302a' && t.title.contains('検査'),
      ),
      isTrue,
    );
  });

  test(
    'care creates patient record with source, deadline and unrecorded age',
    () {
      var state = fresh();
      state = state.copyWith(
        workQueue: state.workQueue!.complete('morning_handoff', 530),
        timeMinutes: 530,
      );
      state = performUnifiedTask(
        state,
        'p301a-am-vitals',
        allowInterrupt: false,
      ).state;
      final record = state.workQueue!.documentation.singleWhere(
        (t) => t.parentTaskId == 'p301a-am-vitals',
      );
      expect(record.patientId, 'p301a');
      expect(record.deadline, state.timeMinutes + 120);
      expect(record.unrecordedMinutes(state.timeMinutes + 12), 12);
      expect(
        availableTasks(
          state.workQueue!,
          540,
        ).any((t) => t.taskId == 'p301b-am-vitals'),
        isTrue,
      );
    },
  );

  test('interrupt adds dynamic work and preserves interrupted task', () {
    final initial = fresh();
    final forced = rollInterrupt(initial, force: true);
    expect(forced.state.workQueue!.dynamicTasks, hasLength(1));
    final task = forced.state.workQueue!.dynamicTasks.single;
    expect(task.patientId, isNotNull);
    expect(task.deadline, isNotNull);
    expect(forced.state.workQueue!.overdue(task.deadline! + 1), contains(task));
    expect(forced.state.workQueue!.pending, contains(task));
    GameState? interrupted;
    for (var seed = 1; seed < 500; seed++) {
      final candidate = performUnifiedTask(fresh(seed), 'morning_handoff');
      if (candidate.interrupted) {
        interrupted = candidate.state;
        break;
      }
    }
    expect(interrupted, isNotNull);
    final active = interrupted!.unifiedShift!.activeTaskId!;
    final dynamic = interrupted.workQueue!.dynamicTasks.last;
    final afterDynamic = performUnifiedTask(
      interrupted,
      dynamic.taskId,
      allowInterrupt: false,
    ).state;
    expect(afterDynamic.unifiedShift!.activeTaskId, active);
    final resumed = performUnifiedTask(
      afterDynamic,
      active,
      allowInterrupt: false,
    ).state;
    expect(resumed.unifiedShift!.activeTaskId, isNull);
    expect(resumed.workQueue!.completed.any((t) => t.taskId == active), isTrue);
  });

  test('17:00 status and minute-accurate overtime', () {
    final state = fresh().copyWith(timeMinutes: 1020);
    expect(state.workStatus!.scheduledEndReached, isTrue);
    expect(state.workStatus!.canLeave, isFalse);
    expect(state.workStatus!.overtimeMinutes, 0);
    expect(state.copyWith(timeMinutes: 1047).workStatus!.overtimeMinutes, 27);
    expect(ShiftWorkStatus.from(TaskQueue([]), 1020).canLeave, isTrue);
  });

  test('unified result uses 17:00 rather than legacy 17:15', () async {
    final store = MemoryShiftStore()
      ..setStartedAtMillis(DateTime.now().millisecondsSinceEpoch);
    store.save(
      fresh().copyWith(timeMinutes: 1020, workQueue: TaskQueue([])),
      null,
    );
    final controller = GameController(content, store);
    expect(controller.finishUnifiedShift(), isTrue);
    expect(controller.state!.result!.plannedFinishTime, 1020);
    expect(controller.state!.result!.overtimeMinutes, 0);
    await controller.lastArchive;
  });

  test('at least ten official events map through one adapter boundary', () {
    expect(mappedEventTasks.length, greaterThanOrEqualTo(10));
    final patient = fresh().unifiedShift!.patients.first;
    for (final id in mappedEventTasks.keys) {
      final event = content.events.firstWhere((e) => e.eventId == id);
      final result = EventTaskAdapter.apply(
        TaskQueue([]),
        event,
        event.choices.first.outcomes.first,
        600,
        patient,
        id,
      );
      expect(
        result.tasks.any((t) => t.sourceEventId == id),
        isTrue,
        reason: id,
      );
    }
  });

  test(
    'v3 restores patients, queue and interrupt state; v2 remains readable',
    () async {
      final prefs = FakePreferences();
      final store = PersistentShiftStore(prefs, content);
      final controller = GameController(content, store)..startNew(seed: 42);
      expect(controller.state!.unifiedShift!.patients, hasLength(6));
      controller.advanceWorkClock(5);
      await store.flush();
      final raw =
          jsonDecode((await prefs.getString(PersistentShiftStore.key))!) as Map;
      expect(raw['schemaVersion'], 6);
      expect((raw['state'] as Map)['scheduledEndReached'], false);
      expect((raw['state'] as Map)['overtimeMinutes'], 0);
      final restored = PersistentShiftStore(prefs, content);
      await restored.load();
      expect(restored.error, isNull);
      expect(
        restored.current!.workQueue!.pendingCount,
        controller.state!.workQueue!.pendingCount,
      );
      expect(restored.current!.unifiedShift!.patients.length, 6);
      final v3Raw = Map<String, dynamic>.from(raw)..['schemaVersion'] = 3;
      await prefs.setString(PersistentShiftStore.key, jsonEncode(v3Raw));
      final v3 = PersistentShiftStore(prefs, content);
      await v3.load();
      expect(v3.error, isNull);
      expect(v3.current!.unifiedShift!.patients.length, 6);
      final legacy = Map<String, dynamic>.from(raw);
      legacy['schemaVersion'] = 2;
      final oldState = Map<String, dynamic>.from(legacy['state'] as Map);
      oldState.remove('unifiedShift');
      oldState['phase'] = 'awaitingChoice';
      oldState['currentEventId'] = content.events.first.eventId;
      oldState['eventInstanceId'] = 'legacy-event';
      legacy['state'] = oldState;
      await prefs.setString(PersistentShiftStore.key, jsonEncode(legacy));
      final v2 = PersistentShiftStore(prefs, content);
      await v2.load();
      expect(v2.error, isNull);
      expect(v2.current!.unifiedShift, isNull);
    },
  );
}
