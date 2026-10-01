import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/application/workday_view.dart';
import 'package:kangoshi_quest/domain/day_shift.dart';
import 'package:kangoshi_quest/domain/models.dart';
import 'package:kangoshi_quest/domain/unified_shift.dart';

import '../../bin/phase11.dart' show simulatePhase11;

void main() {
  test('clock and overtime cross midnight', () {
    expect(clockLabel(510), '08:30');
    expect(clockLabel(1020), '17:00');
    expect(clockLabel(1525), '翌 01:25');
    expect(durationLabel(1025), '17時間5分');
  });

  test('queue categories and handoff use actual eligibility', () {
    const care = WorkTask(
      taskId: 'care',
      title: 'ケア',
      createdAt: 510,
      estimatedMinutes: 5,
      taskType: WorkTaskType.routine,
      requiredToLeave: false,
    );
    const record = WorkTask(
      taskId: 'record',
      title: '記録',
      createdAt: 510,
      estimatedMinutes: 5,
      taskType: WorkTaskType.documentation,
    );
    final interrupted = care.copyWith(
      status: WorkTaskStatus.interrupted,
      remainingDuration: 3,
      interruptionCount: 1,
    );
    final queue = TaskQueue([interrupted, record]);
    final view = QueueOverview.from(queue);
    expect(
      [view.total, view.care, view.records, view.interrupted, view.other],
      [2, 0, 1, 1, 0],
    );
    expect(canHandOff(interrupted), false);
    expect(canHandOff(care), true);
    expect(canHandOff(record), false);
    expect(taskStatusLabel(interrupted), contains('中断'));
    expect(interrupted.remainingDuration, 3);
  });

  test('summary is generated from persisted task facts', () {
    final fresh = startUnifiedShift(
      GameState.initial('summary', 17, 'test', 'test'),
    );
    final queue = fresh.workQueue!;
    final task = queue.tasks.first;
    final state = fresh.copyWith(
      timeMinutes: 1025,
      workQueue: queue.replace(
        task.copyWith(status: WorkTaskStatus.completed, interruptionCount: 2),
      ),
    );
    final summary = DaySummary.fromState(state);
    expect(summary.finishTime, 1025);
    expect(summary.overtimeMinutes, 5);
    expect(summary.completed, 1);
    expect(summary.interruptions, 2);
    expect(DaySummary.fromJson(summary.toJson()).toJson(), summary.toJson());
  });

  test('phase 11 seed 17 remains unchanged for all three policies', () {
    final all = simulatePhase11(17, 'all');
    final handoff = simulatePhase11(17, 'handoff');
    final quick = simulatePhase11(17, 'quick');
    expect(
      [
        all['finishMinute'],
        all['overtimeMinutes'],
        all['completed'],
        all['handedOff'],
        all['unrecorded'],
        all['overdue'],
        all['events'],
        all['interruptions'],
      ],
      [2045, 1025, 169, 0, 0, 0, 28, 5],
    );
    expect(
      [
        handoff['finishMinute'],
        handoff['overtimeMinutes'],
        handoff['completed'],
        handoff['handedOff'],
        handoff['unrecorded'],
        handoff['overdue'],
        handoff['events'],
        handoff['interruptions'],
      ],
      [1248, 228, 81, 43, 0, 17, 28, 5],
    );
    expect(
      [
        quick['finishMinute'],
        quick['overtimeMinutes'],
        quick['completed'],
        quick['handedOff'],
        quick['unrecorded'],
        quick['overdue'],
        quick['events'],
        quick['interruptions'],
      ],
      [1033, 13, 54, 43, 27, 36, 28, 5],
    );
  });
}
