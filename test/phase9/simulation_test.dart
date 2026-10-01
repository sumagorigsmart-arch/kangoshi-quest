import 'package:flutter_test/flutter_test.dart';

import '../../bin/phase9.dart' show simulate;

void main() {
  test('headless policies reach 17:00 and make prioritization matter', () {
    final peaceful = simulate(
      'peaceful',
      11,
      interruptInterval: 0,
      delayRecords: false,
      urgentFirst: false,
    );
    final busy = simulate(
      'busy',
      17,
      interruptInterval: 45,
      delayRecords: false,
      urgentFirst: false,
    );
    final recordsLater = simulate(
      'recordsLater',
      23,
      interruptInterval: 75,
      delayRecords: true,
      urgentFirst: false,
    );
    final urgent = simulate(
      'urgentFirst',
      17,
      interruptInterval: 45,
      delayRecords: false,
      urgentFirst: true,
    );
    for (final result in [peaceful, busy, recordsLater, urgent]) {
      final at1700 = result['at1700'] as Map<String, int>;
      expect(at1700['pending'], greaterThan(0));
      expect(result['overtimeMinutes'], greaterThan(0));
      expect(result['canLeave'], isTrue);
    }
    expect(
      (busy['at1700'] as Map<String, int>)['pending'],
      greaterThan((peaceful['at1700'] as Map<String, int>)['pending']!),
    );
    expect(
      (recordsLater['at1700'] as Map<String, int>)['records'],
      greaterThan((busy['at1700'] as Map<String, int>)['records']!),
    );
    expect(
      urgent['overtimeMinutes'] as int,
      lessThan(busy['overtimeMinutes'] as int),
    );
  });

  test('exit strategies change overtime, completed and unfinished records', () {
    Map<String, Object> run(String strategy) => simulate(
      strategy,
      17,
      interruptInterval: 45,
      delayRecords: false,
      urgentFirst: true,
      exitStrategy: strategy,
    );
    final all = run('all');
    final handoff = run('handoff');
    final quick = run('quick');
    expect(all['handedOff'], 0);
    expect(handoff['handedOff'], greaterThan(0));
    expect(quick['handedOff'], greaterThan(0));
    expect(
      all['overtimeMinutes'] as int,
      greaterThan(handoff['overtimeMinutes'] as int),
    );
    expect(
      quick['overtimeMinutes'] as int,
      lessThanOrEqualTo(handoff['overtimeMinutes'] as int),
    );
    expect(
      quick['remainingRecords'] as int,
      greaterThanOrEqualTo(handoff['remainingRecords'] as int),
    );
    expect(all['completed'] as int, greaterThan(handoff['completed'] as int));
  });
}
