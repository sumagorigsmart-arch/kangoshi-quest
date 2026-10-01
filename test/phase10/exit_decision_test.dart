import 'dart:io';
import 'dart:convert';

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
  WorkTask task(
    String id, {
    WorkTaskType type = WorkTaskType.routine,
    WorkPriority priority = WorkPriority.normal,
    bool required = false,
    String? patient,
    int? deadline,
  }) => WorkTask(
    taskId: id,
    title: id,
    createdAt: 900,
    scheduledAt: 900,
    deadline: deadline,
    estimatedMinutes: 1,
    taskType: type,
    priority: priority,
    requiredToLeave: required,
    patientId: patient,
  );
  GameController controller(
    List<WorkTask> tasks, {
    int time = 1020,
    String? active,
  }) {
    final store = MemoryShiftStore()
      ..setStartedAtMillis(DateTime.now().millisecondsSinceEpoch);
    final state =
        startUnifiedShift(
          GameState.initial(
            'phase10',
            42,
            content.contentVersion,
            content.balanceVersion,
          ),
        ).copyWith(
          timeMinutes: time,
          workQueue: TaskQueue(tasks),
          unifiedShift: UnifiedShiftState(
            patients: generatePatients(),
            activeTaskId: active,
            activeTaskRemaining: active == null ? 0 : 1,
            exitView: 'decision',
          ),
        );
    store.save(state, null);
    return GameController(content, store);
  }

  test('17:00 enters decision and overtime is minute accurate', () {
    final s = startUnifiedShift(
      GameState.initial('x', 1, content.contentVersion, content.balanceVersion),
    );
    final crossed = advanceUnifiedTime(s.copyWith(timeMinutes: 1019), 1);
    expect(crossed.phase, 'taskSelection');
    expect(crossed.unifiedShift!.exitView, 'decision');
    expect(crossed.copyWith(timeMinutes: 1047).workStatus!.overtimeMinutes, 27);
  });

  test('mandatory, urgent and interrupted work block leaving', () {
    for (final blocked in [
      task('required', required: true),
      task('urgent', priority: WorkPriority.urgent),
    ]) {
      final c = controller([blocked]);
      expect(c.state!.workStatus!.canLeave, false);
      expect(c.handOffTasks([blocked.taskId]), false);
      expect(c.finishUnifiedShift(), false);
    }
    final c = controller([
      task('record', type: WorkTaskType.documentation),
    ], active: 'record');
    expect(c.state!.workStatus!.canLeave, false);
    expect(c.finishUnifiedShift(), false);
  });

  test(
    'handoff remains distinct from completion in result and history data',
    () async {
      final c = controller([
        task('handoff', priority: WorkPriority.high, deadline: 1000),
        task(
          'record',
          type: WorkTaskType.documentation,
          patient: 'p301a',
          deadline: 1000,
        ),
      ]);
      expect(c.handOffTasks(['handoff']), true);
      expect(c.state!.workQueue!.handedOff, hasLength(1));
      expect(c.state!.workQueue!.completed, isEmpty);
      expect(c.state!.workStatus!.canLeave, true);
      expect(c.finishUnifiedShift(), true);
      final r = c.state!.result!;
      expect(r.exitType, 'handedOffAndIncompleteRecordExit');
      expect(r.completedTaskCount, 0);
      expect(r.handedOffTaskCount, 1);
      expect(r.incompleteRecordCount, 1);
      expect(r.incompleteRecordPatients, 1);
      expect(r.overdueRecordCount, 1);
      expect(r.handedOffImportance, 3);
      expect(r.handedOffTaskIds, ['handoff']);
      expect(r.completedTaskIds, isEmpty);
      expect(GameResult.fromJson(r.toJson()).exitType, r.exitType);
      await c.lastArchive;
    },
  );

  test('four exit types, including leaving own documentation', () async {
    for (final expected in [
      'cleanExit',
      'handedOffExit',
      'incompleteRecordExit',
      'handedOffAndIncompleteRecordExit',
    ]) {
      final hand =
          expected.contains('handedOff') || expected.contains('HandedOff');
      final record = expected.contains('Record');
      final c = controller([
        if (hand) task('handoff'),
        if (record) task('record', type: WorkTaskType.documentation),
      ]);
      if (hand) expect(c.handOffTasks(['handoff']), true);
      expect(c.finishUnifiedShift(), true);
      expect(c.state!.result!.exitType, expected);
      await c.lastArchive;
    }
  });

  test(
    'v4 restores exit screen and handed-off queue; v3 remains readable',
    () async {
      final prefs = FakePreferences();
      final store = PersistentShiftStore(prefs, content)
        ..setStartedAtMillis(DateTime.now().millisecondsSinceEpoch);
      final state =
          startUnifiedShift(
            GameState.initial(
              'persist',
              42,
              content.contentVersion,
              content.balanceVersion,
            ),
          ).copyWith(
            timeMinutes: 1020,
            workQueue: TaskQueue([task('pass')]).handOff(['pass'], 1020),
            unifiedShift: UnifiedShiftState(
              patients: generatePatients(),
              exitView: 'handoff',
            ),
          );
      store.save(state, null);
      await store.flush();
      final raw =
          jsonDecode((await prefs.getString(PersistentShiftStore.key))!) as Map;
      expect(raw['schemaVersion'], 4);
      final restored = PersistentShiftStore(prefs, content);
      await restored.load();
      expect(restored.error, isNull);
      expect(restored.current!.unifiedShift!.exitView, 'handoff');
      expect(restored.current!.workQueue!.handedOff.single.taskId, 'pass');
      final v3 = Map<String, dynamic>.from(raw)..['schemaVersion'] = 3;
      await prefs.setString(PersistentShiftStore.key, jsonEncode(v3));
      final old = PersistentShiftStore(prefs, content);
      await old.load();
      expect(old.error, isNull);
    },
  );
}
