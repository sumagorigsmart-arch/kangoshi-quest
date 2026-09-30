import 'dart:convert';
import 'dart:io';

import 'package:kangoshi_quest/domain/day_shift.dart';
import 'package:kangoshi_quest/domain/models.dart';
import 'package:kangoshi_quest/domain/unified_shift.dart';

Map<String, Object> simulate(
  String name,
  int seed, {
  required int interruptInterval,
  required bool delayRecords,
  required bool urgentFirst,
}) {
  var state = startUnifiedShift(
    GameState.initial(name, seed, 'phase9', 'balance_v1'),
  );
  var completed = 0;
  var generated = 0;
  var lastForcedAt = 510;
  var steps = 0;
  Map<String, int>? at1700;
  void capture(TaskQueue queue) {
    final at = ShiftWorkStatus.from(queue, 1020);
    at1700 = {
      'pending': at.unfinishedTaskCount,
      'records': at.unfinishedRecordCount,
      'overdue': at.overdueCount,
      'urgent': at.urgentCount,
    };
  }

  while (state.timeMinutes < 1600 && steps < 1000) {
    steps++;
    final status = state.workStatus!;
    if (at1700 == null && status.scheduledEndReached) {
      at1700 = {
        'pending': status.unfinishedTaskCount,
        'records': status.unfinishedRecordCount,
        'overdue': status.overdueCount,
        'urgent': status.urgentCount,
      };
    }
    if (status.canLeave) break;
    final available = availableTasks(
      state.workQueue!,
      state.timeMinutes,
    ).where((t) => t.requiredToLeave || state.timeMinutes < 1020).toList();
    if (available.isEmpty) {
      final future =
          state.workQueue!.pending
              .where(
                (t) =>
                    t.scheduledAt != null && t.scheduledAt! > state.timeMinutes,
              )
              .map((t) => t.scheduledAt!)
              .toList()
            ..sort();
      final jump = future.isEmpty ? 5 : future.first - state.timeMinutes;
      final before = state;
      state = advanceUnifiedTime(state, jump.clamp(1, 10));
      if (at1700 == null &&
          before.timeMinutes < 1020 &&
          state.timeMinutes >= 1020) {
        capture(before.workQueue!);
      }
      continue;
    }
    if (urgentFirst) {
      available.sort((a, b) => a.priority.index.compareTo(b.priority.index));
    } else {
      available.sort(
        (a, b) => (a.scheduledAt ?? a.createdAt).compareTo(
          b.scheduledAt ?? b.createdAt,
        ),
      );
    }
    final nonRecords = available
        .where((t) => t.taskType != WorkTaskType.documentation)
        .toList();
    final task = delayRecords && nonRecords.isNotEmpty
        ? nonRecords.first
        : available.first;
    final before = state;
    state = performUnifiedTask(state, task.taskId, allowInterrupt: false).state;
    if (at1700 == null &&
        before.timeMinutes < 1020 &&
        state.timeMinutes >= 1020) {
      capture(before.workQueue!);
    }
    completed++;
    if (interruptInterval > 0 &&
        state.timeMinutes - lastForcedAt >= interruptInterval &&
        state.timeMinutes < 1020) {
      state = rollInterrupt(state, force: true).state;
      generated++;
      lastForcedAt = state.timeMinutes;
    }
  }
  at1700 ??= {
    'pending': state.workStatus!.unfinishedTaskCount,
    'records': state.workStatus!.unfinishedRecordCount,
    'overdue': state.workStatus!.overdueCount,
    'urgent': state.workStatus!.urgentCount,
  };
  return {
    'scenario': name,
    'at1700': at1700!,
    'finishMinute': state.timeMinutes,
    'overtimeMinutes': state.workStatus!.overtimeMinutes,
    'remaining': state.workStatus!.unfinishedTaskCount,
    'remainingRecords': state.workStatus!.unfinishedRecordCount,
    'overdue': state.workStatus!.overdueCount,
    'interruptions': generated,
    'completed': completed,
    'canLeave': state.workStatus!.canLeave,
  };
}

void main() {
  final results = [
    simulate(
      'peaceful',
      11,
      interruptInterval: 0,
      delayRecords: false,
      urgentFirst: false,
    ),
    simulate(
      'busy',
      17,
      interruptInterval: 45,
      delayRecords: false,
      urgentFirst: false,
    ),
    simulate(
      'recordsLater',
      23,
      interruptInterval: 75,
      delayRecords: true,
      urgentFirst: false,
    ),
    simulate(
      'urgentFirst',
      17,
      interruptInterval: 45,
      delayRecords: false,
      urgentFirst: true,
    ),
  ];
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(results));
}
