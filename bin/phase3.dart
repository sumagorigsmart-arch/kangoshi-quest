import 'dart:convert';
import 'dart:io';

import 'package:kangoshi_quest/content/content_loader.dart';
import 'package:kangoshi_quest/qa/simulation.dart';

void main(List<String> args) {
  final bundle = ContentLoader.load(
    File('assets/content/balance_v1.json').readAsStringSync(),
    File('assets/content/titles_v1.json').readAsStringSync(),
    File('assets/content/events_phase3.json').readAsStringSync(),
  );
  final command = args.isEmpty ? 'validate' : args[0];
  switch (command) {
    case 'validate':
      if (bundle.events.length != 50 ||
          bundle.events.map((e) => e.eventId).toSet().length != 50) {
        throw StateError('Expected 50 unique official events');
      }
      for (final event in bundle.events) {
        for (final choice in event.choices) {
          for (final outcome in choice.outcomes) {
            if (outcome.effects.durationMinutes > 30) {
              throw StateError('Unrealistic duration: ${event.eventId}');
            }
          }
        }
      }
      stdout.writeln(
        'VALID: 50 unique official events; schema and domain validation passed',
      );
    case 'simulate':
      final count = args.length > 1 ? int.parse(args[1]) : 1000;
      final first = args.length > 2 ? int.parse(args[2]) : 1;
      if (count < 1 || first < 1 || first + count > 0xffffffff) {
        throw ArgumentError('Invalid seed range or count');
      }
      stdout.writeln(
        const JsonEncoder.withIndent('  ')
            .convert(summarizeShifts(bundle, count, firstSeed: first)),
      );
    case 'replay':
      if (args.length != 3) throw ArgumentError('replay <seed> <history.json>');
      final replay = jsonDecode(File(args[2]).readAsStringSync());
      final payload = replay is Map<String, dynamic>
          ? replay
          : <String, dynamic>{'choiceHistory': replay};
      if (payload['contentVersion'] != null &&
          payload['contentVersion'] != bundle.contentVersion) {
        throw StateError('Replay content version mismatch');
      }
      if (payload['seed'] != null && payload['seed'] != int.parse(args[1])) {
        throw StateError('Replay seed mismatch');
      }
      final history = List<String>.from(payload['choiceHistory']);
      final s = runShift(
        bundle,
        int.parse(args[1]),
        replayChoices: history,
      ).state;
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'seed': s.seed,
          'contentVersion': s.contentVersion,
          'finishTime': s.timeMinutes,
          'result': s.result!.toJson(),
          'choiceHistory': s.choiceHistory,
        }),
      );
    default:
      throw ArgumentError(
        'Use validate, simulate [count] [firstSeed], or replay',
      );
  }
}
