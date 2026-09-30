import 'dart:convert';
import 'dart:io';

import 'package:kangoshi_quest/content/content_loader.dart';
import 'package:kangoshi_quest/domain/engine.dart';
import 'package:kangoshi_quest/domain/models.dart';

void main(List<String> args) {
  final seed = args.isEmpty ? 42 : int.parse(args.first);
  final choices = args.length < 2
      ? <String>['focused', 'quick', 'quick', 'short']
      : args[1].split(',');
  final bundle = ContentLoader.load(
    File('assets/content/balance_v1.json').readAsStringSync(),
    File('assets/content/titles_v1.json').readAsStringSync(),
    File('assets/content/fixture_events.json').readAsStringSync(),
  );
  final engine = GameEngine(bundle.balance, bundle.events, bundle.titles);
  var state = engine
      .dispatch(
        GameState.initial(
          'headless',
          seed,
          bundle.contentVersion,
          bundle.balanceVersion,
        ),
        const StartShift(),
      )
      .state;
  var index = 0;
  while (state.phase != 'completed') {
    if (index >= choices.length) {
      throw StateError('Choice sequence ended at ${state.currentEventId}');
    }
    final choice = choices[index++];
    final before = state;
    state = engine
        .dispatch(state, SelectChoice(state.eventInstanceId!, choice))
        .state;
    stdout.writeln(
      '${before.timeMinutes} ${before.currentEventId} $choice -> ${state.timeMinutes} ${state.outcomeText ?? state.result?.reason}',
    );
    if (state.phase != 'completed') {
      state = engine.dispatch(state, const Next()).state;
    }
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert(state.result!.toJson()),
  );
}
