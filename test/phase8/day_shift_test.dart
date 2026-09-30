import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/domain/day_shift.dart';
import 'package:kangoshi_quest/domain/models.dart';

void main() {
  test('time boundaries and configurable lunch', () {
    expect(phaseAt(510), ShiftPhase.morningHandoff);
    expect(phaseAt(529), ShiftPhase.morningHandoff);
    expect(phaseAt(530), ShiftPhase.morningCare);
    expect(phaseAt(690), ShiftPhase.lunchCare);
    expect(phaseAt(750, lunchDone: true), ShiftPhase.breakTime);
    expect(
      phaseAt(750, lunchDone: true, breakDone: true),
      ShiftPhase.afternoonCare,
    );
    expect(phaseAt(780), ShiftPhase.afternoonCare);
    expect(phaseAt(930), ShiftPhase.afternoonHandoff);
    expect(phaseAt(950), ShiftPhase.remainingWork);
    expect(phaseAt(1020), ShiftPhase.overtime);
    expect(
      phaseAt(700, config: const DayShiftConfig(lunchStart: 720)),
      ShiftPhase.morningCare,
    );
  });

  test('routine order, dynamic work, deadline and documentation', () {
    var queue = generateRoutineTasks();
    expect(queue.routine.first.title, '朝の申し送り');
    expect(
      availableTasks(queue, 510).map((t) => t.taskId),
      contains('morning_handoff'),
    );
    queue = queue.complete('morning_handoff', 530);
    expect(
      availableTasks(queue, 530).map((t) => t.taskId),
      contains('morning_vitals'),
    );
    queue = queue.complete('morning_vitals', 545);
    expect(queue.documentationCount, 1);
    expect(
      queue.pending.any((t) => t.parentTaskId == 'morning_vitals'),
      isTrue,
    );
    queue = advanceScheduledTasks(queue, 590, 600);
    final iv = queue.dynamicTasks.singleWhere((t) => t.taskId == 'iv-1000');
    expect(iv.scheduledAt, 600);
    expect(deadlineState(iv, 605), DeadlineState.approaching);
    expect(deadlineState(iv, 621), DeadlineState.overdue);
    expect(queue.overdue(621), contains(iv));
    expect(queue.pending, contains(iv));
    queue = queue.complete('iv-1000', 625);
    expect(queue.documentation.any((t) => t.parentTaskId == iv.taskId), isTrue);
    queue = advanceScheduledTasks(queue, 625, 630);
    expect(queue.dynamicTasks.any((t) => t.taskId == 'exam-1030'), isTrue);
  });

  test('full shift scenario and JSON restoration', () {
    var queue = generateRoutineTasks();
    var now = 510;
    void finish(String id) {
      final task = queue.tasks.firstWhere((t) => t.taskId == id);
      final end = now + task.estimatedMinutes;
      queue = advanceScheduledTasks(queue.complete(id, end), now, end);
      now = end;
    }

    finish('morning_handoff');
    expect(now, 530);
    finish('morning_vitals');
    expect(now, 545);
    for (final id in [
      'morning_iv',
      'morning_diaper',
      'morning_hygiene',
      'orders',
      'medication',
      'doctor_assist',
    ]) {
      finish(id);
    }
    now = 690;
    for (final id in [
      'lunch_serve',
      'lunch_assist',
      'lunch_medication',
      'lunch_clear',
    ]) {
      finish(id);
    }
    expect(phaseAt(now, lunchDone: true), ShiftPhase.breakTime);
    finish('break');
    now = 780;
    finish('afternoon_vitals');
    finish('afternoon_diaper');
    now = 930;
    expect(phaseAt(now), ShiftPhase.afternoonHandoff);
    finish('afternoon_handoff');
    expect(now, 950);
    expect(phaseAt(now), ShiftPhase.remainingWork);
    now = 1020;
    expect(phaseAt(now), ShiftPhase.overtime);
    expect(queue.documentationCount, greaterThan(0));
    expect(queue.pendingCount, greaterThan(0));
    final restored = TaskQueue.fromJson(jsonDecode(jsonEncode(queue.toJson())));
    expect(restored.pendingCount, queue.pendingCount);
    expect(restored.documentationCount, queue.documentationCount);
    final state = GameState.initial(
      'phase8',
      1,
      'content',
      'balance',
    ).copyWith(timeMinutes: now, workQueue: queue);
    final reloaded = GameState.fromJson(jsonDecode(jsonEncode(state.toJson())));
    expect(reloaded.timeMinutes, 1020);
    expect(reloaded.workQueue!.pendingCount, queue.pendingCount);
    final legacy = Map<String, dynamic>.from(state.toJson())
      ..remove('workQueue');
    expect(GameState.fromJson(legacy).workQueue, isNull);
  });
}
