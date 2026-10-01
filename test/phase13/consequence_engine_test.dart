import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/application/workday_view.dart';
import 'package:kangoshi_quest/domain/consequence_engine.dart';
import 'package:kangoshi_quest/domain/day_shift.dart';
import 'package:kangoshi_quest/domain/models.dart';
import 'package:kangoshi_quest/domain/unified_shift.dart';

void main() {
  final patients = generatePatients();

  test('seed 3: postponed toileting creates a bounded care chain', () {
    ConsequenceDecision run() {
      final first = ConsequenceEngine.evaluate(
        queue: generatePatientRoutineTasks(patients),
        patients: patients,
        previous: const [],
        ledger: const [],
        seed: 3,
        before: 679,
        now: 680,
      );
      expect(
        first.consequences.any(
          (c) => c.generatedTaskIds.any(
            (id) => first.queue.tasks
                .firstWhere((t) => t.taskId == id)
                .title
                .contains('失禁対応'),
          ),
        ),
        isTrue,
      );
      final source = first.consequences.firstWhere(
        (c) => c.sourceTaskId == 'p302a-am-toilet',
      );
      final completed = first.queue.complete(
        source.generatedTaskIds.first,
        681,
      );
      final second = ConsequenceEngine.evaluate(
        queue: completed,
        patients: patients,
        previous: first.consequences,
        ledger: first.events,
        seed: 3,
        before: 681,
        now: 682,
      );
      expect(second.queue.tasks.any((t) => t.title.contains('寝具交換')), isTrue);
      return second;
    }

    final a = run();
    final b = run();
    expect(jsonEncode(a.queue.toJson()), jsonEncode(b.queue.toJson()));
    expect(
      jsonEncode(a.consequences.map((e) => e.toJson()).toList()),
      jsonEncode(b.consequences.map((e) => e.toJson()).toList()),
    );
    expect(
      a.queue.tasks.every((t) => t.chainDepth <= ConsequenceEngine.maxDepth),
      isTrue,
    );
  });

  test('seed 3: unattended call creates one repeat, not an infinite loop', () {
    final queue = TaskQueue([
      WorkTask(
        taskId: 'dynamic-1',
        title: 'ナースコール',
        patientId: 'p302a',
        createdAt: 600,
        scheduledAt: 600,
        estimatedMinutes: 5,
        taskType: WorkTaskType.dynamic,
        sourceEventId: 'call',
      ),
    ]);
    final first = ConsequenceEngine.evaluate(
      queue: queue,
      patients: patients,
      previous: const [],
      ledger: const [],
      seed: 3,
      before: 639,
      now: 640,
    );
    expect(first.consequences.single.triggerType, 'repeatedCall');
    final second = ConsequenceEngine.evaluate(
      queue: first.queue,
      patients: patients,
      previous: first.consequences,
      ledger: first.events,
      seed: 3,
      before: 640,
      now: 900,
    );
    expect(second.consequences, isEmpty);
    expect(
      jsonEncode(first.queue.toJson()),
      jsonEncode(
        ConsequenceEngine.evaluate(
          queue: queue,
          patients: patients,
          previous: const [],
          ledger: const [],
          seed: 3,
          before: 639,
          now: 640,
        ).queue.toJson(),
      ),
    );
  });

  test(
    'seed 17: documentation backlog is visible at 17:00 and in overtime',
    () {
      final initial = GameState.initial('phase13', 17, 'test', 'test');
      var state = startUnifiedShift(initial, enableConsequences: true);
      final records = List.generate(
        6,
        (i) => WorkTask(
          taskId: 'record-$i',
          title: '記録 $i',
          createdAt: 900,
          estimatedMinutes: 5,
          taskType: WorkTaskType.documentation,
        ),
      );
      state = state.copyWith(
        timeMinutes: 1019,
        workQueue: TaskQueue([...state.workQueue!.tasks, ...records]),
      );
      final advanced = advanceUnifiedTime(state, 2);
      expect(
        advanced.unifiedShift!.eventLedger.any(
          (e) => e.eventType == 'documentationBacklog',
        ),
        isTrue,
      );
      final summary = DaySummary.fromState(advanced);
      expect(summary.overtimeMinutes, 1);
      expect(summary.undocumented, greaterThanOrEqualTo(6));
      expect(
        jsonEncode(advanced.toJson()),
        jsonEncode(advanceUnifiedTime(state, 2).toJson()),
      );
    },
  );

  test('event ledger survives parent removal and state roundtrip', () {
    final initial = startUnifiedShift(
      GameState.initial('ledger', 17, 'test', 'test'),
      enableConsequences: true,
    );
    const entry = ShiftEventLedgerEntry(
      eventId: 'dynamic-1',
      eventType: 'call',
      patientId: 'p301a',
      occurredAt: 600,
      wasInterruption: true,
    );
    final state = initial.copyWith(
      timeMinutes: 1020,
      workQueue: TaskQueue(const []),
      unifiedShift: initial.unifiedShift!.copyWith(eventLedger: [entry]),
    );
    final restored = GameState.fromJson(jsonDecode(jsonEncode(state.toJson())));
    final summary = DaySummary.fromState(restored);
    expect(summary.events, 1);
    expect(summary.eventCounts['call'], 1);
    expect(summary.interruptions, 1);
    expect(restored.unifiedShift!.consequencesEnabled, isTrue);
  });

  test('break exposes a domain reason for urgent work', () {
    final queue = TaskQueue([
      const WorkTask(
        taskId: 'break',
        title: '休憩',
        createdAt: 510,
        scheduledAt: 755,
        estimatedMinutes: 30,
        taskType: WorkTaskType.routine,
      ),
      const WorkTask(
        taskId: 'urgent',
        title: '急ぎの仕事',
        createdAt: 750,
        estimatedMinutes: 5,
        priority: WorkPriority.urgent,
        taskType: WorkTaskType.dynamic,
      ),
    ]);
    expect(breakBlockReason(queue, 760), contains('緊急'));
  });
}
