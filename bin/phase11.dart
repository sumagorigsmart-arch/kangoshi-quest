import 'dart:convert';
import 'dart:io';

import 'package:kangoshi_quest/domain/day_shift.dart';
import 'package:kangoshi_quest/domain/models.dart';
import 'package:kangoshi_quest/domain/unified_shift.dart';

Map<String, Object> simulatePhase11(int seed, String policy) {
  var state = startUnifiedShift(
    GameState.initial('phase11', seed, 'phase11', 'balance_v1'),
  );
  var steps = 0;
  while (steps++ < 2500) {
    final queue = state.workQueue!;
    final now = state.timeMinutes;
    if (now >= 1020 && policy != 'all') {
      final handoff = queue.pending
          .where(
            (t) =>
                t.status != WorkTaskStatus.interrupted &&
                t.taskType != WorkTaskType.documentation &&
                !t.requiredToLeave &&
                t.priority != WorkPriority.urgent,
          )
          .toList();
      if (handoff.isNotEmpty) {
        state = state.copyWith(
          workQueue: queue.handOff(handoff.map((t) => t.taskId), now),
        );
      }
      if (state.workStatus!.canLeave &&
          (policy == 'quick' || state.workQueue!.documentationCount == 0)) {
        break;
      }
    }
    if (now >= 1020 && policy == 'all' && queue.pending.isEmpty) break;
    final tasks = availableTasks(state.workQueue!, now)
        .where(
          (t) =>
              now < 1020 ||
              policy == 'all' ||
              t.requiredToLeave ||
              t.priority == WorkPriority.urgent ||
              (policy == 'handoff' &&
                  t.taskType == WorkTaskType.documentation) ||
              t.status == WorkTaskStatus.interrupted,
        )
        .toList();
    if (tasks.isEmpty) {
      final future =
          state.workQueue!.pending
              .where((t) => t.scheduledAt != null && t.scheduledAt! > now)
              .map((t) => t.scheduledAt!)
              .toList()
            ..sort();
      if (now >= 1020 && future.isEmpty) break;
      state = rollInterrupt(
        advanceUnifiedTime(
          state,
          future.isEmpty ? 5 : (future.first - now).clamp(1, 5),
        ),
      ).state;
      continue;
    }
    tasks.sort((a, b) {
      final urgency = a.priority.index.compareTo(b.priority.index);
      if (urgency != 0) return urgency;
      return (a.deadline ?? 99999).compareTo(b.deadline ?? 99999);
    });
    state = performUnifiedTask(state, tasks.first.taskId).state;
  }
  if (steps >= 2500) throw StateError('Simulation did not finish');
  final queue = state.workQueue!;
  return {
    'policy': policy,
    'finishMinute': state.timeMinutes,
    'overtimeMinutes': state.workStatus!.overtimeMinutes,
    'completed': queue.completed.length,
    'handedOff': queue.handedOff.length,
    'unrecorded': queue.documentationCount,
    'overdue': queue.tasks
        .where(
          (t) =>
              t.deadline != null &&
              (t.status == WorkTaskStatus.handedOff
                  ? t.handedOffAt! > t.deadline!
                  : t.status != WorkTaskStatus.completed &&
                        state.timeMinutes > t.deadline!),
        )
        .length,
    'events': state.unifiedShift!.interruptSerial,
    'interruptions': queue.tasks.fold<int>(
      0,
      (sum, t) => sum + t.interruptionCount,
    ),
    'canLeave': state.workStatus!.canLeave,
  };
}

void main() {
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert([
      simulatePhase11(17, 'all'),
      simulatePhase11(17, 'handoff'),
      simulatePhase11(17, 'quick'),
    ]),
  );
}
