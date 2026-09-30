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
}
