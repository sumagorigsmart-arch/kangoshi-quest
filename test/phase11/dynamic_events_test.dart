import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/application/persistent_shift_store.dart';
import 'package:kangoshi_quest/content/content_loader.dart';
import 'package:kangoshi_quest/domain/day_shift.dart';
import 'package:kangoshi_quest/domain/models.dart';
import 'package:kangoshi_quest/domain/unified_shift.dart';

import '../../bin/phase11.dart' show simulatePhase11;
import '../phase5/phase5_test.dart' show FakePreferences;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final content = ContentLoader.load(
    File('assets/content/balance_v1.json').readAsStringSync(),
    File('assets/content/titles_v1.json').readAsStringSync(),
    File('assets/content/events_phase3.json').readAsStringSync(),
  );
  GameState fresh(int seed) => startUnifiedShift(
    GameState.initial(
      'phase11-$seed',
      seed,
      content.contentVersion,
      content.balanceVersion,
    ),
  );
  GameState tick(int seed, int at) =>
      rollInterrupt(fresh(seed).copyWith(timeMinutes: at)).state;

  test('same seed and operations reproduce event state', () {
    expect(
      jsonEncode(tick(17, 780).toJson()),
      jsonEncode(tick(17, 780).toJson()),
    );
  });
  test('different seeds change the event sequence', () {
    expect(
      tick(17, 780).workQueue!.dynamicTasks.map((t) => t.title).toList(),
      isNot(tick(18, 780).workQueue!.dynamicTasks.map((t) => t.title).toList()),
    );
  });
  test('patient attributes constrain event candidates', () {
    final s = fresh(2);
    final only = s.unifiedShift!.patients.first;
    final state = s.copyWith(
      unifiedShift: s.unifiedShift!.copyWith(patients: [only]),
    );
    final result = rollInterrupt(
      state.copyWith(timeMinutes: 800),
      force: true,
    ).state;
    expect(
      result.workQueue!.dynamicTasks.last.sourceEventId,
      isNot(anyOf('infusion', 'examination', 'toileting', 'emergency')),
    );
  });
  test(
    'emergency interrupts ordinary task and retains remaining time and count',
    () {
      GameState? found;
      for (var seed = 1; seed <= 1000 && found == null; seed++) {
        final s = fresh(seed).copyWith(
          timeMinutes: 800,
          unifiedShift: fresh(seed).unifiedShift!
              .copyWith(lastEventMinute: 800),
        );
        final active = s.workQueue!.tasks.first;
        final candidate = rollInterrupt(
          s.copyWith(
            workQueue: s.workQueue!.replace(
              active.copyWith(
                status: WorkTaskStatus.inProgress,
                remainingDuration: 12,
              ),
            ),
            unifiedShift: s.unifiedShift!.copyWith(
              activeTaskId: active.taskId,
              activeTaskRemaining: 12,
            ),
          ),
          force: true,
        ).state;
        if (candidate.workQueue!.dynamicTasks.any(
          (t) => t.priority == WorkPriority.urgent,
        )) {
          found = candidate;
        }
      }
      expect(found, isNotNull);
      final task = found!.workQueue!.tasks.first;
      expect(task.status, WorkTaskStatus.interrupted);
      expect(task.remainingDuration, 12);
      expect(task.interruptionCount, 1);
      expect(found.workStatus!.canLeave, false);
    },
  );
  test('interrupted task resumes from remaining duration', () {
    final s = fresh(1).copyWith(timeMinutes: 1020);
    final task = s.workQueue!.tasks.first;
    final modified = s.copyWith(
      workQueue: s.workQueue!.replace(
        task.copyWith(
          status: WorkTaskStatus.interrupted,
          remainingDuration: 3,
          interruptionCount: 1,
        ),
      ),
      unifiedShift: s.unifiedShift!.copyWith(
        activeTaskId: task.taskId,
        activeTaskRemaining: 3,
      ),
    );
    final result = performUnifiedTask(
      modified,
      task.taskId,
      allowInterrupt: false,
    ).state;
    expect(result.timeMinutes, 1023);
    expect(result.workQueue!.tasks.first.status, WorkTaskStatus.completed);
    expect(result.workQueue!.tasks.first.interruptionCount, 1);
  });
  test('dynamic completion expands chain and documentation but terminates', () {
    var queue = TaskQueue([
      const WorkTask(
        taskId: 'root',
        title: 'call',
        createdAt: 600,
        estimatedMinutes: 4,
        taskType: WorkTaskType.dynamic,
        sourceEventId: 'call',
        documentationMinutes: 3,
      ),
    ]);
    queue = queue.complete('root', 604);
    expect(
      queue.tasks.any(
        (t) => t.sourceTaskId == 'root' && t.taskType == WorkTaskType.dynamic,
      ),
      true,
    );
    expect(queue.documentationCount, 1);
    queue = queue.complete('root-followup', 612);
    expect(queue.tasks.length, 4);
    expect(queue.tasks.every((t) => t.chainDepth <= 2), true);
  });
  test('admission adds seventh patient and separate tasks', () {
    GameState? found;
    for (var seed = 1; seed <= 5000 && found == null; seed++) {
      final s = fresh(seed).copyWith(timeMinutes: 800);
      final result = rollInterrupt(s, force: true).state;
      if (result.unifiedShift!.patients.length == 7) found = result;
    }
    expect(found, isNotNull);
    expect(
      found!.workQueue!.tasks
          .where(
            (t) => t.patientId == found!.unifiedShift!.patients.last.patientId,
          )
          .length,
      4,
    );
  });
  test('dynamic ordinary task can hand off, record cannot', () {
    final q = TaskQueue([
      const WorkTask(
        taskId: 'care',
        title: 'care',
        createdAt: 600,
        estimatedMinutes: 3,
        taskType: WorkTaskType.dynamic,
        requiredToLeave: false,
        documentationMinutes: 3,
      ),
    ]).complete('care', 605);
    final pending = TaskQueue([
      q.tasks.first.copyWith(status: WorkTaskStatus.pending),
      q.tasks.last,
    ]);
    expect(pending.handOff(['care'], 1020).handedOff.length, 1);
    expect(
      () => pending.handOff(['care-documentation'], 1020),
      throwsStateError,
    );
  });
  test('v5 roundtrip and v4 migration retain queue', () async {
    final prefs = FakePreferences();
    final store = PersistentShiftStore(prefs, content)..setStartedAtMillis(1);
    final s = tick(17, 800);
    store.save(s, null);
    await store.flush();
    final restored = PersistentShiftStore(prefs, content);
    await restored.load();
    expect(jsonEncode(restored.current!.toJson()), jsonEncode(s.toJson()));
    final raw =
        jsonDecode((await prefs.getString(PersistentShiftStore.key))!) as Map;
    raw['schemaVersion'] = 4;
    await prefs.setString(PersistentShiftStore.key, jsonEncode(raw));
    final legacy = PersistentShiftStore(prefs, content);
    await legacy.load();
    expect(legacy.error, isNull);
    expect(legacy.current!.workQueue!.tasks.length, s.workQueue!.tasks.length);
  });
  test('headless policies reproduce seed 17', () {
    for (final policy in ['all', 'handoff', 'quick']) {
      expect(simulatePhase11(17, policy), simulatePhase11(17, policy));
    }
  });
  test('every generated dynamic task has a patient and deadline', () {
    final tasks = tick(17, 900).workQueue!.dynamicTasks;
    expect(tasks, isNotEmpty);
    expect(tasks.every((t) => t.patientId != null && t.deadline != null), true);
  });
  test('nonurgent events wait in the queue without forcing completion', () {
    final s = rollInterrupt(
      fresh(17).copyWith(timeMinutes: 650),
      force: true,
    ).state;
    final task = s.workQueue!.dynamicTasks.last;
    expect(task.status, WorkTaskStatus.pending);
    expect(s.phase, 'taskSelection');
  });
  test('chain depth cap prevents further documentation', () {
    final queue = TaskQueue([
      const WorkTask(
        taskId: 'last',
        title: 'last',
        createdAt: 600,
        estimatedMinutes: 2,
        taskType: WorkTaskType.dynamic,
        documentationMinutes: 3,
        sourceTaskId: 'middle',
        chainDepth: 3,
      ),
    ]);
    expect(queue.complete('last', 602).tasks, hasLength(1));
  });
  test('new admission does not exceed seven patients', () {
    final s = fresh(17);
    final seven = s.copyWith(
      unifiedShift: s.unifiedShift!.copyWith(
        patients: [...s.unifiedShift!.patients, s.unifiedShift!.patients.first],
      ),
    );
    final result = rollInterrupt(
      seven.copyWith(timeMinutes: 800),
      force: true,
    ).state;
    expect(result.unifiedShift!.patients.length, 7);
    expect(
      result.workQueue!.dynamicTasks.last.sourceEventId,
      isNot('admission'),
    );
  });
  test('emergency completion creates an observation and record', () {
    final queue = TaskQueue([
      const WorkTask(
        taskId: 'acute',
        title: '急変',
        createdAt: 600,
        estimatedMinutes: 10,
        taskType: WorkTaskType.dynamic,
        priority: WorkPriority.urgent,
        sourceEventId: 'emergency',
        documentationMinutes: 4,
      ),
    ]).complete('acute', 610);
    expect(queue.documentationCount, 1);
    expect(queue.urgent, hasLength(1));
    expect(queue.urgent.single.title, contains('状態観察'));
  });
  test('interruption metadata survives task JSON roundtrip', () {
    const task = WorkTask(
      taskId: 'care',
      title: 'ケア',
      createdAt: 600,
      estimatedMinutes: 10,
      taskType: WorkTaskType.routine,
      status: WorkTaskStatus.interrupted,
      interruptionCount: 2,
      remainingDuration: 4,
      interruptedAt: 606,
      resumedAt: 603,
      sourceTaskId: 'call',
      chainDepth: 1,
    );
    final restored = WorkTask.fromJson(task.toJson());
    expect(restored.toJson(), task.toJson());
  });
}
