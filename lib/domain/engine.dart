import 'models.dart';

int _clamp(int n) => n.clamp(0, 10000);
int _min(int a, int b) => a < b ? a : b;

class GameEngine {
  final BalanceConfig balance;
  final List<EventDefinition> events;
  final List<TitleDefinition> titles;
  GameEngine(this.balance, this.events, this.titles);

  Transition dispatch(GameState state, GameCommand command) =>
      switch (command) {
        StartShift() => _start(state),
        SelectChoice() => _select(state, command),
        Next() => _next(state),
      };

  Transition _start(GameState state) {
    if (state.phase != 'closing' || state.presentationCount != 0) {
      throw StateError('Shift already started');
    }
    return _present(state);
  }

  int _nextRng(int n) {
    n ^= (n << 13) & 0xffffffff;
    n ^= n >>> 17;
    n ^= (n << 5) & 0xffffffff;
    return n & 0xffffffff;
  }

  (T, int) _weighted<T>(List<T> items, List<double> weights, int rng) {
    if (items.length == 1) return (items.single, rng);
    final total = weights.fold<double>(0, (a, b) => a + b);
    if (!total.isFinite || total <= 0) {
      throw StateError('Invalid effective weights');
    }
    final next = _nextRng(rng);
    final target = next / 4294967296 * total;
    var sum = 0.0;
    for (var i = 0; i < items.length; i++) {
      sum += weights[i];
      if (sum > target) return (items[i], next);
    }
    return (items.last, next);
  }

  double _weight(
    double base,
    List<WeightModifier> modifiers,
    GameState state,
  ) => modifiers.fold(base, (v, m) => v * m.apply(state));

  List<EventDefinition> eligible(GameState s) {
    final list =
        events
            .where(
              (e) =>
                  s.timeMinutes >= e.minTime &&
                  s.timeMinutes <= e.maxTime &&
                  !s.playedEventIds.contains(e.eventId) &&
                  e.conditions.every((c) => c.matches(s)) &&
                  !(e.tags.contains('major') &&
                      (s.majorCount >= balance.majorLimit || s.lastEventMajor)),
            )
            .toList()
          ..sort((a, b) => a.eventId.compareTo(b.eventId));
    return list;
  }

  double effectiveEventWeight(EventDefinition e, GameState s) {
    var w = _weight(e.weight, e.weightModifiers, s);
    if (s.timeMinutes >= 990) {
      if (e.tags.contains('lateShift')) w *= 2.5;
      if (e.tags.contains('crusher')) w *= 1.5;
    }
    if (s.meters['bladder']! >= 8500 && e.tags.contains('toilet')) w *= 3;
    if (s.meters['hunger']! >= 8500 && e.tags.contains('food')) w *= 3;
    return w;
  }

  Transition _present(GameState s) {
    if (s.timeMinutes >= balance.hardStop ||
        s.turnCount >= balance.maxChoices) {
      return _finish(s, 'forcedRelief');
    }
    if (s.timeMinutes > balance.dayEnd) return _presentClosing(s);
    final options = eligible(s);
    String id;
    var rng = s.rngState;
    var played = s.playedEventIds;
    var counters = s.counters;
    var major = false;
    if (options.isEmpty) {
      id = 'fallback';
    } else {
      final picked = _weighted(
        options,
        options.map((e) => effectiveEventWeight(e, s)).toList(),
        rng,
      );
      final event = picked.$1;
      rng = picked.$2;
      id = event.eventId;
      played = [...played, id];
      major = event.tags.contains('major');
      counters = counters.add(
        callCount: event.onAppear['callCount'] ?? 0,
        admissionCount: event.onAppear['admissionCount'] ?? 0,
        acuteChangeCount: event.onAppear['acuteChangeCount'] ?? 0,
      );
    }
    final n = s.presentationCount + 1;
    return Transition(
      s
          .copyWith(clearCurrent: true)
          .copyWith(
            phase: 'awaitingChoice',
            rngState: rng,
            playedEventIds: played,
            counters: counters,
            majorCount: s.majorCount + (major ? 1 : 0),
            lastEventMajor: major,
            currentEventId: id,
            eventInstanceId: '${s.runId}-$n',
            presentationCount: n,
            slotIndex: balance.slots.indexWhere((t) => t >= s.timeMinutes),
          ),
      id,
    );
  }

  Transition _presentClosing(GameState s) {
    if (s.tasks.total == 0 && s.handoverDone) return _finish(s, 'normal');
    final id = s.tasks.total == 0 ? 'final_handover' : 'closing_tasks';
    final n = s.presentationCount + 1;
    return Transition(
      s
          .copyWith(clearCurrent: true)
          .copyWith(
            phase: 'awaitingChoice',
            currentEventId: id,
            eventInstanceId: '${s.runId}-$n',
            presentationCount: n,
          ),
      id,
    );
  }

  List<ChoiceDefinition> choices(GameState s) {
    if (s.phase != 'awaitingChoice') return const [];
    if (s.currentEventId == 'fallback') return _fallbackChoices(s);
    if (s.currentEventId == 'closing_tasks') return _closingChoices(s);
    if (s.currentEventId == 'final_handover') return _handoverChoices();
    return events.firstWhere((e) => e.eventId == s.currentEventId).choices;
  }

  ChoiceDefinition _choice(
    String id,
    String label,
    String type,
    int minutes,
    Effects effects, {
    String? text,
  }) => ChoiceDefinition(id, label, '所要 $minutes 分', type, [
    OutcomeDefinition('${id}_done', text ?? label, 1, effects),
  ]);
  List<ChoiceDefinition> _fallbackChoices(GameState s) => [
    _choice(
      'record',
      '記録を整理',
      'work',
      s.tasks.record > 0 ? 6 : 6,
      Effects(
        durationMinutes: 6,
        completeTasks: TaskState(s.tasks.record > 0 ? 1 : 0, 0, 0),
        meterDelta: s.tasks.record == 0 ? const {'mental': 100} : const {},
      ),
      text: s.tasks.record > 0 ? '記録を1件終えた。' : '記録を整理・確認した。',
    ),
    _choice(
      'coordination',
      '連絡・調整',
      'coordination',
      s.tasks.coordination > 0 ? 8 : 6,
      Effects(
        durationMinutes: s.tasks.coordination > 0 ? 8 : 6,
        completeTasks: TaskState(0, s.tasks.coordination > 0 ? 1 : 0, 0),
        meterDelta: s.tasks.coordination == 0
            ? const {'mental': 100}
            : const {},
      ),
      text: s.tasks.coordination > 0 ? '調整を1件終えた。' : '連絡を整理・確認した。',
    ),
    _choice(
      'rest',
      '小休憩',
      'rest',
      5,
      const Effects(
        durationMinutes: 5,
        breakMinutes: 5,
        meterDelta: {'hp': 200, 'mental': 200},
      ),
      text: '少し休んだ。',
    ),
  ];
  List<ChoiceDefinition> _closingChoices(GameState s) {
    final result = <ChoiceDefinition>[];
    if (s.tasks.record > 0) {
      final count = _min(s.tasks.record, 2);
      result.add(
        _choice(
          'record',
          '記録を終える',
          'work',
          count * 6,
          Effects(
            durationMinutes: count * 6,
            completeTasks: TaskState(count, 0, 0),
          ),
          text: '記録を$count件終えた。',
        ),
      );
    }
    if (s.tasks.coordination > 0) {
      result.add(
        _choice(
          'coordination',
          '調整を終える',
          'coordination',
          8,
          const Effects(durationMinutes: 8, completeTasks: TaskState(0, 1, 0)),
          text: '調整を1件終えた。',
        ),
      );
    }
    if (s.tasks.care > 0) {
      result.add(
        _choice(
          'care',
          'ケアの残務を終える',
          'work',
          10,
          const Effects(durationMinutes: 10, completeTasks: TaskState(0, 0, 1)),
          text: 'ケアの残務を1件終えた。',
        ),
      );
    }
    if (s.counters.handoverAttempts < 2 &&
        s.tasks.coordination + s.tasks.care > 0) {
      result.add(
        ChoiceDefinition('consult', '合意引継ぎを相談', '承認が必要。6分', 'coordination', [
          OutcomeDefinition(
            'approved',
            '対象と承認を確認し、合意引継ぎした。',
            60,
            const Effects(durationMinutes: 6),
            [
              const WeightModifier([
                Condition('scores.team', 'gte', 7000),
              ], 1.3),
              const WeightModifier([
                Condition('scores.team', 'lte', 3499),
              ], 0.8),
            ],
          ),
          OutcomeDefinition(
            'declined',
            '調整がつかず、自分で対応する。',
            40,
            const Effects(durationMinutes: 6),
          ),
        ]),
      );
    }
    while (result.length < 3) {
      if (result.length == 1) {
        result.add(
          _choice(
            'pause',
            '休んでから処理',
            'rest',
            5,
            const Effects(
              durationMinutes: 5,
              breakMinutes: 5,
              meterDelta: {'hp': 200, 'mental': 200},
            ),
          ),
        );
      } else {
        result.add(
          _choice(
            'review',
            '状況を整理して次へ',
            'selfCare',
            3,
            const Effects(durationMinutes: 3, meterDelta: {'mental': 100}),
          ),
        );
      }
    }
    return result;
  }

  List<ChoiceDefinition> _handoverChoices() => [
    _choice(
      'short',
      '短い確認',
      'coordination',
      5,
      const Effects(durationMinutes: 5),
      text: '必要な情報を確認して引き継いだ。',
    ),
    _choice(
      'detailed',
      '詳しい確認',
      'coordination',
      8,
      const Effects(durationMinutes: 8, scoreDelta: {'team': 200}),
      text: '必要な情報を詳しく確認して引き継いだ。',
    ),
    _choice(
      'recover',
      '自分の状態を整えてから確認',
      'selfCare',
      10,
      const Effects(durationMinutes: 10, meterDelta: {'mental': 300}),
      text: '状態を整え、必要な情報を確認して引き継いだ。',
    ),
  ];

  Transition _select(GameState s, SelectChoice command) {
    if (s.phase != 'awaitingChoice' ||
        s.eventInstanceId != command.eventInstanceId) {
      throw StateError('Stale or duplicate eventInstanceId');
    }
    final choice = choices(s).firstWhere(
      (c) => c.choiceId == command.choiceId,
      orElse: () => throw StateError('Unknown choice'),
    );
    final weights = choice.outcomes
        .map((o) => _weight(o.weight, o.weightModifiers, s))
        .toList();
    final picked = _weighted(choice.outcomes, weights, s.rngState);
    final outcome = picked.$1;
    final fatigue =
        (choice.actionType == 'work' || choice.actionType == 'coordination') &&
            (s.meters['hp']! < 2000 || s.meters['mental']! < 2000)
        ? balance.fatigueMinutes
        : 0;
    final total = outcome.effects.durationMinutes + fatigue;
    final available = balance.hardStop - s.timeMinutes;
    final partial = total > available;
    final elapsed = partial ? available : total;
    var advanced = _natural(s, elapsed).copyWith(
      rngState: picked.$2,
      turnCount: s.turnCount + 1,
      choiceHistory: [
        ...s.choiceHistory,
        '${s.eventInstanceId}:${choice.choiceId}:${outcome.outcomeId}',
      ],
    );
    if (partial) {
      return _finish(
        advanced.copyWith(
          phase: 'showingOutcome',
          currentOutcomeId: 'partial',
          outcomeText: '対応の途中で応援へ引き継いだ',
          currentOutcome: OutcomeDefinition(
            'partial',
            '対応の途中で応援へ引き継いだ',
            1,
            Effects(durationMinutes: elapsed),
          ),
        ),
        'forcedRelief',
      );
    }
    var effect = outcome.effects;
    if (s.currentEventId == 'closing_tasks' && choice.choiceId == 'consult') {
      effect = Effects(
        durationMinutes: effect.durationMinutes,
        transferTasks: outcome.outcomeId == 'approved'
            ? TaskState(
                0,
                _min(s.tasks.coordination, 2 - _min(s.tasks.care, 2)),
                _min(s.tasks.care, 2),
              )
            : const TaskState(0, 0, 0),
      );
    }
    final completed = advanced.tasks.taken(effect.completeTasks);
    final remaining = advanced.tasks.subtract(completed);
    final transferred = remaining.taken(effect.transferTasks);
    final shortfall =
        completed.total < effect.completeTasks.total ||
        transferred.total < effect.transferTasks.total;
    final displayText = shortfall ? '対象の残務を整理・確認した。' : outcome.text;
    advanced = _apply(advanced, effect);
    final isHandover = s.currentEventId == 'final_handover';
    if (s.currentEventId == 'closing_tasks' && choice.choiceId == 'consult') {
      advanced = advanced.copyWith(
        counters: advanced.counters.add(handoverAttempts: 1),
      );
    }
    return Transition(
      advanced.copyWith(
        phase: 'showingOutcome',
        currentOutcomeId: outcome.outcomeId,
        outcomeText: displayText,
        currentOutcome: OutcomeDefinition(
          outcome.outcomeId,
          displayText,
          outcome.weight,
          effect,
          outcome.weightModifiers,
        ),
        handoverDone: isHandover ? true : advanced.handoverDone,
      ),
      displayText,
    );
  }

  GameState _natural(GameState s, int minutes) {
    final m = Map<String, int>.from(s.meters);
    m['hp'] = _clamp(m['hp']! + minutes * balance.hpPerMinute);
    m['mental'] = _clamp(m['mental']! + minutes * balance.mentalPerMinute);
    m['bladder'] = _clamp(m['bladder']! + minutes * balance.bladderPerMinute);
    m['hunger'] = _clamp(m['hunger']! + minutes * balance.hungerPerMinute);
    return s.copyWith(
      timeMinutes: s.timeMinutes + minutes,
      meters: m,
      peakBladder: m['bladder']! > s.peakBladder ? m['bladder'] : s.peakBladder,
      minimumHp: m['hp']! < s.minimumHp ? m['hp'] : s.minimumHp,
      minimumMental: m['mental']! < s.minimumMental
          ? m['mental']
          : s.minimumMental,
    );
  }

  GameState _apply(GameState s, Effects e) {
    final m = Map<String, int>.from(s.meters),
        scores = Map<String, int>.from(s.scores);
    for (final item in e.meterDelta.entries) {
      m[item.key] = _clamp(m[item.key]! + item.value);
    }
    if (e.setBladderAfter != null) m['bladder'] = e.setBladderAfter!;
    for (final item in e.scoreDelta.entries) {
      scores[item.key] = _clamp(scores[item.key]! + item.value);
    }
    final completed = s.tasks.taken(e.completeTasks);
    final afterComplete = s.tasks.subtract(completed);
    final transferred = afterComplete.taken(e.transferTasks);
    final tasks = afterComplete.subtract(transferred).add(e.createTasks);
    final flags = {...s.flags, ...e.setFlags};
    if (e.breakMinutes > 0) flags['hasRested'] = true;
    return s.copyWith(
      meters: m,
      scores: scores,
      tasks: tasks,
      flags: flags,
      counters: s.counters.add(
        breakMinutes: e.breakMinutes,
        toiletCount: e.toiletCount,
        completed: completed,
        transferred: transferred,
      ),
      peakBladder: m['bladder']! > s.peakBladder ? m['bladder'] : s.peakBladder,
      minimumHp: m['hp']! < s.minimumHp ? m['hp'] : s.minimumHp,
      minimumMental: m['mental']! < s.minimumMental
          ? m['mental']
          : s.minimumMental,
    );
  }

  Transition _next(GameState s) {
    if (s.phase != 'showingOutcome') throw StateError('No outcome to advance');
    if (s.result != null) return Transition(s, 'completed');
    if (s.timeMinutes >= balance.hardStop ||
        s.turnCount >= balance.maxChoices) {
      return s.tasks.total == 0 && s.handoverDone
          ? _finish(s, 'normal')
          : _finish(s, 'forcedRelief');
    }
    if (s.timeMinutes >= balance.dayEnd) return _presentClosing(s);
    final next = balance.slots.where((t) => t > s.timeMinutes).firstOrNull;
    if (next == null) return _presentClosing(s);
    final routine = next - s.timeMinutes;
    final moved = _natural(s, routine).copyWith(clearCurrent: true);
    final presented = _present(moved);
    return Transition(presented.state, presented.message, routine);
  }

  Transition _finish(GameState s, String reason) {
    if (reason == 'normal' && (s.tasks.total != 0 || !s.handoverDone)) {
      throw StateError('Unfinished normal shift');
    }
    var finished = s;
    if (reason == 'normal' && s.timeMinutes < balance.plannedFinish) {
      finished = _natural(s, balance.plannedFinish - s.timeMinutes);
    }
    final result = evaluate(finished, reason);
    return Transition(
      finished.copyWith(phase: 'completed', result: result),
      reason,
    );
  }

  GameResult evaluate(GameState s, String reason) {
    final overtime = s.timeMinutes > balance.plannedFinish
        ? s.timeMinutes - balance.plannedFinish
        : 0;
    final health =
        (s.meters['hp']! +
            s.meters['mental']! +
            (10000 - s.meters['bladder']!) +
            (10000 - s.meters['hunger']!)) ~/
        4;
    final axis = {
      'patient': s.scores['patient']!,
      'team': s.scores['team']!,
      'health': health,
      'safety': 10000 - s.scores['risk']!,
    };
    String grade(int v) => v >= 8200
        ? 'S'
        : v >= 7000
        ? 'A'
        : v >= 5800
        ? 'B'
        : v >= 4500
        ? 'C'
        : v >= 3200
        ? 'D'
        : 'E';
    final grades = axis.map((k, v) => MapEntry(k, grade(v)));
    final values = <String, Object>{
      'reason': reason,
      'overtimeMinutes': overtime,
      'axis.patient': axis['patient']!,
      'axis.team': axis['team']!,
      'axis.health': health,
      'axis.safety': axis['safety']!,
      'peakBladder': s.peakBladder,
      'transferredTotal': s.counters.transferredTotal,
      'counters.breakMinutes': s.counters.breakMinutes,
      'counters.callCount': s.counters.callCount,
      'counters.completedRecord': s.counters.completedRecord,
      'counters.toiletCount': s.counters.toiletCount,
      'meters.mental': s.meters['mental']!,
    };
    bool matches(Condition c) {
      final actual = values[c.field];
      if (actual == null) {
        throw StateError('Unknown title condition ${c.field}');
      }
      return switch (c.op) {
        'eq' => actual == c.value,
        'gte' => (actual as num) >= (c.value as num),
        'lte' => (actual as num) <= (c.value as num),
        _ => throw StateError('Unknown title operator ${c.op}'),
      };
    }

    final earned = titles.where((t) => t.conditions.every(matches)).toList()
      ..sort((a, b) {
        final p = b.priority.compareTo(a.priority);
        return p != 0 ? p : a.id.compareTo(b.id);
      });
    return GameResult(
      reason,
      earned.isEmpty ? '' : earned.first.id,
      balance.plannedFinish,
      s.timeMinutes,
      overtime,
      s.peakBladder,
      s.tasks,
      reason == 'forcedRelief' ? s.tasks : const TaskState(0, 0, 0),
      s.counters,
      axis,
      grades,
      earned.map((e) => e.id).toList(),
    );
  }
}
