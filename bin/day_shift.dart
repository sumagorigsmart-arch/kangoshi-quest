import 'dart:convert';
import 'dart:io';

import 'package:kangoshi_quest/domain/day_shift.dart';

void main() {
  var queue = generateRoutineTasks();
  var now = 510;
  final timeline = <Map<String, Object>>[];
  void advance(int target) {
    queue = advanceScheduledTasks(queue, now, target);
    now = target;
  }

  void finish(String id) {
    final task = queue.tasks.firstWhere((t) => t.taskId == id);
    if (task.scheduledAt != null && now < task.scheduledAt!) {
      advance(task.scheduledAt!);
    }
    if (!availableTasks(queue, now).any((t) => t.taskId == id)) {
      throw StateError('$id is not available at $now');
    }
    final end = now + task.estimatedMinutes;
    queue = advanceScheduledTasks(queue.complete(id, end), now, end);
    timeline.add({'at': now, 'task': id, 'end': end});
    now = end;
  }

  for (final id in [
    'morning_handoff',
    'morning_vitals',
    'morning_iv',
    'morning_diaper',
    'morning_hygiene',
    'orders',
    'medication',
    'doctor_assist',
    'lunch_serve',
    'lunch_assist',
    'lunch_medication',
    'lunch_clear',
    'break',
    'afternoon_vitals',
    'afternoon_diaper',
    'afternoon_handoff',
  ]) {
    finish(id);
  }
  advance(1020);
  if (phaseAt(now) != ShiftPhase.overtime || queue.documentationCount == 0) {
    throw StateError('Expected 17:00 with pending documentation');
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'start': 510,
      'handoff': 930,
      'finish': now,
      'pending': queue.pendingCount,
      'documentation': queue.documentationCount,
      'dynamic': queue.dynamicTasks.length,
      'timeline': timeline,
    }),
  );
}
