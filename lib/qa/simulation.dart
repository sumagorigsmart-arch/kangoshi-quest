import 'dart:convert';

import '../content/content_loader.dart';
import '../domain/engine.dart';
import '../domain/models.dart';

class SimulatedShift {
  final GameState state;
  final int maxFallbackStreak;
  final List<String> eventTrace;
  const SimulatedShift(this.state, this.maxFallbackStreak, this.eventTrace);
}

/// All decisions pass through the same command boundary as the UI.
SimulatedShift runShift(
  ContentBundle bundle,
  int seed, {
  String policy = 'mixed',
  List<String>? replayChoices,
}) {
  final engine = GameEngine(bundle.balance, bundle.events, bundle.titles);
  var state = engine
      .dispatch(
        GameState.initial(
          'qa',
          seed,
          bundle.contentVersion,
          bundle.balanceVersion,
        ),
        const StartShift(),
      )
      .state;
  final trace = <String>[];
  var fallbackStreak = 0, maxFallbackStreak = 0, index = 0;
  final known = bundle.events.map((e) => e.eventId).toSet();
  while (state.phase != 'completed') {
    if (state.phase != 'awaitingChoice' || state.eventInstanceId == null) {
      throw StateError('Unexpected simulation phase ${state.phase}');
    }
    if (!known.contains(state.currentEventId) &&
        !{
          'fallback',
          'closing_tasks',
          'final_handover',
        }.contains(state.currentEventId)) {
      throw StateError('Ineligible or unknown event ${state.currentEventId}');
    }
    if (known.contains(state.currentEventId)) {
      final event = bundle.events.firstWhere(
        (e) => e.eventId == state.currentEventId,
      );
      if (state.timeMinutes < event.minTime ||
          state.timeMinutes > event.maxTime ||
          !event.conditions.every((c) => c.matches(state)) ||
          state.playedEventIds.where((id) => id == event.eventId).length != 1) {
        throw StateError('Ineligible event ${event.eventId}');
      }
    }
    if (state.currentEventId == 'fallback') {
      fallbackStreak++;
      if (fallbackStreak > maxFallbackStreak)
        maxFallbackStreak = fallbackStreak;
    } else {
      fallbackStreak = 0;
    }
    final eventId = state.currentEventId!;
    trace.add(eventId);
    final available = engine.choices(state);
    String id;
    String? expectedOutcome;
    if (replayChoices != null) {
      if (index >= replayChoices.length)
        throw StateError('Replay ended at $eventId');
      final parts = replayChoices[index].split(':');
      if (parts.length != 3 || parts[0] != state.eventInstanceId) {
        throw StateError('Replay instance mismatch at $eventId');
      }
      id = parts[1];
      expectedOutcome = parts[2];
    } else if (eventId == 'closing_tasks') {
      id = available.first.choiceId;
    } else if (eventId == 'final_handover') {
      id = 'short';
    } else if (eventId == 'fallback') {
      id = state.tasks.record > 0
          ? 'record'
          : state.tasks.coordination > 0
          ? 'coordination'
          : 'rest';
    } else {
      final preferred = switch (policy) {
        'efficient' => 'share',
        'careful' => 'careful',
        'quick' => 'quick',
        _ => ['share', 'quick', 'careful'][(seed + index) % 3],
      };
      id = available.any((c) => c.choiceId == preferred)
          ? preferred
          : available.first.choiceId;
    }
    final before = state;
    state = engine
        .dispatch(state, SelectChoice(state.eventInstanceId!, id))
        .state;
    if (expectedOutcome != null && state.currentOutcomeId != expectedOutcome) {
      throw StateError('Replay outcome mismatch at $eventId');
    }
    if (state.timeMinutes < before.timeMinutes ||
        state.timeMinutes > bundle.balance.hardStop) {
      throw StateError('Invalid time at $eventId');
    }
    if ([
      state.tasks.record,
      state.tasks.coordination,
      state.tasks.care,
    ].any((n) => n < 0 || n > 1000000)) {
      throw StateError('Invalid task count at $eventId');
    }
    if (state.counters.breakMinutes < 0 ||
        state.counters.breakMinutes > state.timeMinutes - 510) {
      throw StateError('Invalid break minutes at $eventId');
    }
    index++;
    if (index > bundle.balance.maxChoices + 2)
      throw StateError('Infinite loop');
    if (state.phase != 'completed') {
      final timeBeforeNext = state.timeMinutes;
      state = engine.dispatch(state, const Next()).state;
      if (state.timeMinutes < timeBeforeNext)
        throw StateError('Time reversed on Next');
    }
  }
  if (replayChoices != null && replayChoices.length != index) {
    throw StateError('Unused replay choices');
  }
  final result = state.result!;
  if (result.reason == 'normal' &&
      (state.tasks.total != 0 || !state.handoverDone)) {
    throw StateError('Normal ending with unfinished work');
  }
  if (result.overtimeMinutes == 0 &&
      result.reason == 'normal' &&
      state.timeMinutes != 1035) {
    throw StateError('On-time ending outside 17:15');
  }
  return SimulatedShift(state, maxFallbackStreak, trace);
}

Map<String, dynamic> summarizeShifts(
  ContentBundle bundle,
  int count, {
  int firstSeed = 1,
}) {
  final endings = {'onTime': 0, 'overtime': 0, 'forcedRelief': 0};
  final policies = {'efficient': 0, 'mixed': 0, 'careful': 0, 'quick': 0};
  final policyEndings = {
    for (final policy in policies.keys)
      policy: {'onTime': 0, 'overtime': 0, 'forcedRelief': 0},
  };
  final seenEvents = <String>{};
  var maxFallbackStreak = 0;
  int? onTimeSeed;
  List<String>? onTimeHistory;
  for (var i = 0; i < count; i++) {
    final seed = firstSeed + i;
    final policy = policies.keys.elementAt(i % policies.length);
    policies[policy] = policies[policy]! + 1;
    final run = runShift(bundle, seed, policy: policy);
    seenEvents.addAll(
      run.eventTrace.where((id) => bundle.events.any((e) => e.eventId == id)),
    );
    final s = run.state;
    if (run.maxFallbackStreak > maxFallbackStreak) {
      maxFallbackStreak = run.maxFallbackStreak;
    }
    if (s.result!.reason == 'forcedRelief') {
      endings['forcedRelief'] = endings['forcedRelief']! + 1;
      policyEndings[policy]!['forcedRelief'] =
          policyEndings[policy]!['forcedRelief']! + 1;
    } else if (s.timeMinutes == 1035 && s.result!.overtimeMinutes == 0) {
      endings['onTime'] = endings['onTime']! + 1;
      policyEndings[policy]!['onTime'] = policyEndings[policy]!['onTime']! + 1;
      onTimeSeed ??= seed;
      onTimeHistory ??= s.choiceHistory;
    } else {
      endings['overtime'] = endings['overtime']! + 1;
      policyEndings[policy]!['overtime'] =
          policyEndings[policy]!['overtime']! + 1;
    }
  }
  return {
    'count': count,
    'firstSeed': firstSeed,
    'policies': policies,
    'policyEndings': policyEndings,
    'endings': endings,
    'seenOfficialEvents': seenEvents.length,
    'onTimeRate': endings['onTime']! / count,
    'maxFallbackStreak': maxFallbackStreak,
    'onTimeSeed': onTimeSeed,
    'onTimeChoiceHistory': onTimeHistory,
    'contentVersion': bundle.contentVersion,
  };
}

String stateFingerprint(GameState state) => jsonEncode(state.toJson());
