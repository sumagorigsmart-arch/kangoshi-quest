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
  String exitStrategy = 'all',
}) {
  var state = startUnifiedShift(
    GameState.initial(name, seed, 'phase9', 'balance_v1'),
  );
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
    if (state.timeMinutes >= 1020 && exitStrategy != 'all') {
      final transferable = state.workQueue!.pending
          .where(
            (t) =>
                t.taskType != WorkTaskType.documentation &&
                !t.requiredToLeave &&
                t.priority != WorkPriority.urgent,
          )
          .toList();
      if (transferable.isNotEmpty) {
        state = state.copyWith(
          workQueue: state.workQueue!.handOff(
            transferable.map((t) => t.taskId),
            state.timeMinutes,
          ),
        );
      }
      if (state.workStatus!.canLeave && exitStrategy == 'quick') {
        break;
      }
      if (state.workStatus!.canLeave &&
          state.workQueue!.documentationCount == 0) {
        break;
      }
    }
    if (exitStrategy == 'all' &&
        state.workQueue!.pending.isEmpty &&
        state.timeMinutes >= 1020) {
      break;
    }
    final available = availableTasks(state.workQueue!, state.timeMinutes)
        .where(
          (t) =>
              state.timeMinutes < 1020 ||
              exitStrategy == 'all' ||
              t.requiredToLeave ||
              t.priority == WorkPriority.urgent ||
              (exitStrategy == 'handoff' &&
                  t.taskType == WorkTaskType.documentation),
        )
        .toList();
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
    'overdue':
        state.workStatus!.overdueCount +
        state.workQueue!.handedOff
            .where((t) => t.deadline != null && t.handedOffAt! > t.deadline!)
            .length,
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
    'completed': state.workQueue!.completed.length,
    'handedOff': state.workQueue!.handedOff.length,
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
    simulate(
      '全部やる',
      17,
      interruptInterval: 45,
      delayRecords: false,
      urgentFirst: true,
      exitStrategy: 'all',
    ),
    simulate(
      '引き継ぐ',
      17,
      interruptInterval: 45,
      delayRecords: false,
      urgentFirst: true,
      exitStrategy: 'handoff',
    ),
    simulate(
      'とにかく帰る',
      17,
      interruptInterval: 45,
      delayRecords: false,
      urgentFirst: true,
      exitStrategy: 'quick',
    ),
  ];
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(results));
}
