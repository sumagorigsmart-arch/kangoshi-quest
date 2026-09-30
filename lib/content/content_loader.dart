import 'dart:convert';

import '../domain/models.dart';

class ContentException implements Exception {
  final String path, eventId, message;
  const ContentException(this.path, this.eventId, this.message);
  @override
  String toString() =>
      'ContentException(eventId=$eventId, path=$path): $message';
}

class ContentBundle {
  final String contentVersion, balanceVersion;
  final BalanceConfig balance;
  final List<EventDefinition> events;
  final List<TitleDefinition> titles;
  const ContentBundle(
    this.contentVersion,
    this.balanceVersion,
    this.balance,
    this.events,
    this.titles,
  );
}

class ContentLoader {
  static ContentBundle load(
    String balanceJson,
    String titlesJson,
    String eventsJson,
  ) {
    final b = _decode(balanceJson, 'balance');
    final t = _decode(titlesJson, 'titles');
    final e = _decode(eventsJson, 'events');
    _keys(
      b,
      {
        'schemaVersion',
        'balanceVersion',
        'slots',
        'naturalPerMinute',
        'fatigueMinutes',
        'majorLimit',
        'maxChoices',
        'dayEnd',
        'plannedFinish',
        'hardStop',
      },
      'balance',
      '\$',
      '',
    );
    _eq(b['schemaVersion'], 1, 'balance', '\$.schemaVersion', '');
    _string(b['balanceVersion'], 'balance', '\$.balanceVersion', '');
    final slots = _list(b['slots'], 'balance', '\$.slots', '');
    const expected = [
      510,
      535,
      560,
      585,
      610,
      635,
      660,
      685,
      710,
      735,
      760,
      785,
      810,
      835,
      860,
      885,
      910,
      935,
      960,
      990,
      1005,
      1020,
    ];
    if (slots.length != expected.length ||
        List.generate(
          expected.length,
          (i) => slots[i] == expected[i],
        ).contains(false)) {
      _fail(
        'balance',
        '\$.slots',
        '',
        'Expected exactly 22 specification slots',
      );
    }
    final natural = _map(
      b['naturalPerMinute'],
      'balance',
      '\$.naturalPerMinute',
      '',
    );
    _keys(
      natural,
      {'hp', 'mental', 'bladder', 'hunger'},
      'balance',
      '\$.naturalPerMinute',
      '',
    );
    for (final k in natural.keys) {
      _int(natural[k], 'balance', '\$.naturalPerMinute.$k', '');
    }
    for (final k in [
      'fatigueMinutes',
      'majorLimit',
      'maxChoices',
      'dayEnd',
      'plannedFinish',
      'hardStop',
    ]) {
      _positive(b[k], 'balance', '\$.$k', '');
    }
    final balance = BalanceConfig.fromJson(b);
    _keys(t, {'schemaVersion', 'titles'}, 'titles', '\$', '');
    _eq(t['schemaVersion'], 1, 'titles', '\$.schemaVersion', '');
    final titleItems = _list(t['titles'], 'titles', '\$.titles', '');
    final titleIds = <String>{};
    const titleFields = {
      'reason',
      'overtimeMinutes',
      'axis.patient',
      'axis.team',
      'axis.health',
      'axis.safety',
      'peakBladder',
      'transferredTotal',
      'counters.breakMinutes',
      'counters.callCount',
      'counters.completedRecord',
      'counters.toiletCount',
      'meters.mental',
    };
    for (var i = 0; i < titleItems.length; i++) {
      final p = '\$.titles[$i]';
      final m = _map(titleItems[i], 'titles', p, '');
      _keys(m, {'id', 'name', 'priority', 'conditions'}, 'titles', p, '');
      final id = _string(m['id'], 'titles', '$p.id', '');
      if (!titleIds.add(id)) _fail('titles', '$p.id', id, 'Duplicate title id');
      _string(m['name'], 'titles', '$p.name', id);
      _int(m['priority'], 'titles', '$p.priority', id);
      _conditions(m['conditions'], 'titles', '$p.conditions', id, titleFields);
    }
    _keys(
      e,
      {'schemaVersion', 'contentVersion', 'scenarioId', 'events'},
      'events',
      '\$',
      '',
    );
    _eq(e['schemaVersion'], 1, 'events', '\$.schemaVersion', '');
    _eq(e['scenarioId'], 'day_shift', 'events', '\$.scenarioId', '');
    _string(e['contentVersion'], 'events', '\$.contentVersion', '');
    final items = _list(e['events'], 'events', '\$.events', '');
    final ids = <String>{};
    for (var i = 0; i < items.length; i++) {
      final p = '\$.events[$i]';
      final m = _map(items[i], 'events', p, '');
      final id = m['eventId'] is String ? m['eventId'] as String : '<unknown>';
      _keys(
        m,
        {
          'eventId',
          'title',
          'description',
          'category',
          'timeRange',
          'conditions',
          'choices',
          'weight',
          'tags',
          'maxPerRun',
          'onAppear',
          'weightModifiers',
          'reviewNote',
        },
        'events',
        p,
        id,
        required: {
          'eventId',
          'title',
          'description',
          'category',
          'timeRange',
          'conditions',
          'choices',
          'weight',
          'tags',
          'maxPerRun',
        },
      );
      if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(id)) {
        _fail('events', '$p.eventId', id, 'Invalid eventId');
      }
      if (!ids.add(id)) _fail('events', '$p.eventId', id, 'Duplicate eventId');
      for (final k in ['title', 'description', 'category']) {
        _string(m[k], 'events', '$p.$k', id);
      }
      final range = _map(m['timeRange'], 'events', '$p.timeRange', id);
      _keys(range, {'min', 'max'}, 'events', '$p.timeRange', id);
      final min = _int(range['min'], 'events', '$p.timeRange.min', id),
          max = _int(range['max'], 'events', '$p.timeRange.max', id);
      if (min < 510 || max > 1020 || min > max) {
        _fail('events', '$p.timeRange', id, 'Invalid working-hours range');
      }
      _positiveWeight(m['weight'], 'events', '$p.weight', id);
      _eq(m['maxPerRun'], 1, 'events', '$p.maxPerRun', id);
      _conditions(m['conditions'], 'events', '$p.conditions', id, gameFields);
      _modifiers(
        m['weightModifiers'],
        'events',
        '$p.weightModifiers',
        id,
        gameFields,
      );
      final tags = _list(m['tags'], 'events', '$p.tags', id);
      if (m['reviewNote'] != null) {
        _string(m['reviewNote'], 'events', '$p.reviewNote', id);
      }
      for (var j = 0; j < tags.length; j++) {
        _string(tags[j], 'events', '$p.tags[$j]', id);
      }
      final appear = m['onAppear'] == null
          ? <String, dynamic>{}
          : _map(m['onAppear'], 'events', '$p.onAppear', id);
      _keys(
        appear,
        {'callCount', 'admissionCount', 'acuteChangeCount'},
        'events',
        '$p.onAppear',
        id,
        required: {},
      );
      for (final k in appear.keys) {
        _nonnegative(appear[k], 'events', '$p.onAppear.$k', id);
      }
      final choices = _list(m['choices'], 'events', '$p.choices', id);
      if (choices.length < 3 || choices.length > 4) {
        _fail('events', '$p.choices', id, 'Expected 3–4 choices');
      }
      final choiceIds = <String>{};
      for (var j = 0; j < choices.length; j++) {
        final cp = '$p.choices[$j]';
        final c = _map(choices[j], 'events', cp, id);
        _keys(
          c,
          {'choiceId', 'label', 'hint', 'actionType', 'outcomes'},
          'events',
          cp,
          id,
        );
        final choiceId = _string(c['choiceId'], 'events', '$cp.choiceId', id);
        if (!choiceIds.add(choiceId)) {
          _fail('events', '$cp.choiceId', id, 'Duplicate choiceId');
        }
        for (final k in ['label', 'hint']) {
          _string(c[k], 'events', '$cp.$k', id);
        }
        if (!{
          'work',
          'coordination',
          'selfCare',
          'rest',
        }.contains(c['actionType'])) {
          _fail('events', '$cp.actionType', id, 'Unknown actionType');
        }
        final outcomes = _list(c['outcomes'], 'events', '$cp.outcomes', id);
        if (outcomes.isEmpty || outcomes.length > 3) {
          _fail('events', '$cp.outcomes', id, 'Expected 1–3 outcomes');
        }
        final outcomeIds = <String>{};
        for (var k = 0; k < outcomes.length; k++) {
          final op = '$cp.outcomes[$k]';
          final o = _map(outcomes[k], 'events', op, id);
          _keys(
            o,
            {'outcomeId', 'weight', 'text', 'effects', 'weightModifiers'},
            'events',
            op,
            id,
            required: {'outcomeId', 'weight', 'text', 'effects'},
          );
          final outcomeId = _string(
            o['outcomeId'],
            'events',
            '$op.outcomeId',
            id,
          );
          if (!outcomeIds.add(outcomeId)) {
            _fail('events', '$op.outcomeId', id, 'Duplicate outcomeId');
          }
          _positiveWeight(o['weight'], 'events', '$op.weight', id);
          _string(o['text'], 'events', '$op.text', id);
          _modifiers(
            o['weightModifiers'],
            'events',
            '$op.weightModifiers',
            id,
            gameFields,
          );
          _effects(o['effects'], 'events', '$op.effects', id);
        }
      }
    }
    return ContentBundle(
      e['contentVersion'],
      b['balanceVersion'],
      balance,
      List.unmodifiable(items.map(EventDefinition.fromJson)),
      List.unmodifiable(titleItems.map(TitleDefinition.fromJson)),
    );
  }

  static Map<String, dynamic> _decode(String source, String file) {
    try {
      return _map(jsonDecode(source), file, '\$', '<unknown>');
    } on FormatException {
      _fail(file, '\$', '<unknown>', 'Invalid JSON syntax');
    }
  }

  static const gameFields = {
    'timeMinutes',
    'meters.hp',
    'meters.mental',
    'meters.bladder',
    'meters.hunger',
    'scores.patient',
    'scores.team',
    'scores.risk',
    'tasks.record',
    'tasks.coordination',
    'tasks.care',
    'tasks.total',
    'counters.breakMinutes',
    'flags.hasRested',
    'flags.teamSupport',
  };
  static Never _fail(
    String file,
    String path,
    String eventId,
    String message,
  ) => throw ContentException('$file:$path', eventId, message);
  static Map<String, dynamic> _map(dynamic v, String f, String p, String id) {
    if (v is! Map<String, dynamic>) _fail(f, p, id, 'Expected object');
    return v;
  }

  static List<dynamic> _list(dynamic v, String f, String p, String id) {
    if (v is! List) _fail(f, p, id, 'Expected array');
    return v;
  }

  static String _string(dynamic v, String f, String p, String id) {
    if (v is! String || v.isEmpty) _fail(f, p, id, 'Expected nonempty string');
    return v;
  }

  static int _int(dynamic v, String f, String p, String id) {
    if (v is! int) _fail(f, p, id, 'Expected integer');
    return v;
  }

  static int _nonnegative(dynamic v, String f, String p, String id) {
    final n = _int(v, f, p, id);
    if (n < 0) _fail(f, p, id, 'Expected nonnegative integer');
    return n;
  }

  static int _positive(dynamic v, String f, String p, String id) {
    final n = _int(v, f, p, id);
    if (n <= 0) _fail(f, p, id, 'Expected positive integer');
    return n;
  }

  static void _eq(
    dynamic actual,
    Object expected,
    String f,
    String p,
    String id,
  ) {
    if (actual != expected) _fail(f, p, id, 'Expected $expected');
  }

  static double _positiveWeight(dynamic v, String f, String p, String id) {
    if (v is! num || !v.toDouble().isFinite || v <= 0) {
      _fail(f, p, id, 'Expected positive finite weight');
    }
    return v.toDouble();
  }

  static void _keys(
    Map<String, dynamic> m,
    Set<String> allowed,
    String f,
    String p,
    String id, {
    Set<String>? required,
  }) {
    final req = required ?? allowed;
    for (final k in req) {
      if (!m.containsKey(k)) _fail(f, '$p.$k', id, 'Missing field');
    }
    for (final k in m.keys) {
      if (!allowed.contains(k)) _fail(f, '$p.$k', id, 'Unknown field');
    }
  }

  static void _conditions(
    dynamic v,
    String f,
    String p,
    String id,
    Set<String> fields,
  ) {
    final l = _list(v, f, p, id);
    for (var i = 0; i < l.length; i++) {
      final path = '$p[$i]';
      final m = _map(l[i], f, path, id);
      _keys(m, {'field', 'op', 'value'}, f, path, id);
      final field = m['field'];
      if (!fields.contains(field)) {
        _fail(f, '$path.field', id, 'Unknown condition field');
      }
      final op = m['op'];
      if (!{'eq', 'gte', 'lte'}.contains(op)) {
        _fail(f, '$path.op', id, 'Unknown condition op');
      }
      final value = m['value'];
      if (field.toString().startsWith('flags.')) {
        if (op != 'eq' || value is! bool) {
          _fail(f, '$path.value', id, 'Expected boolean equality');
        }
      } else if (field == 'reason') {
        if (op != 'eq' || !{'normal', 'forcedRelief'}.contains(value)) {
          _fail(f, '$path.value', id, 'Expected ending reason');
        }
      } else {
        _int(value, f, '$path.value', id);
      }
    }
  }

  static void _modifiers(
    dynamic v,
    String f,
    String p,
    String id,
    Set<String> fields,
  ) {
    if (v == null) return;
    final l = _list(v, f, p, id);
    for (var i = 0; i < l.length; i++) {
      final path = '$p[$i]';
      final m = _map(l[i], f, path, id);
      _keys(m, {'conditions', 'factor'}, f, path, id);
      _conditions(m['conditions'], f, '$path.conditions', id, fields);
      _positiveWeight(m['factor'], f, '$path.factor', id);
    }
  }

  static void _taskMap(dynamic v, String f, String p, String id) {
    if (v == null) return;
    final m = _map(v, f, p, id);
    _keys(m, {'record', 'coordination', 'care'}, f, p, id, required: {});
    for (final k in m.keys) {
      _nonnegative(m[k], f, '$p.$k', id);
    }
  }

  static void _effects(dynamic v, String f, String p, String id) {
    final m = _map(v, f, p, id);
    _keys(
      m,
      {
        'durationMinutes',
        'meterDelta',
        'scoreDelta',
        'createTasks',
        'completeTasks',
        'transferTasks',
        'setBladderAfter',
        'counters',
        'setFlags',
      },
      f,
      p,
      id,
      required: {'durationMinutes'},
    );
    final duration = _positive(
      m['durationMinutes'],
      f,
      '$p.durationMinutes',
      id,
    );
    for (final pair in [
      ('meterDelta', {'hp', 'mental', 'bladder', 'hunger'}),
      ('scoreDelta', {'patient', 'team', 'risk'}),
    ]) {
      final key = pair.$1;
      if (m[key] != null) {
        final data = _map(m[key], f, '$p.$key', id);
        _keys(data, pair.$2, f, '$p.$key', id, required: {});
        for (final k in data.keys) {
          _int(data[k], f, '$p.$key.$k', id);
        }
      }
    }
    for (final key in ['createTasks', 'completeTasks', 'transferTasks']) {
      _taskMap(m[key], f, '$p.$key', id);
    }
    final created = m['createTasks'] == null
        ? <String, dynamic>{}
        : _map(m['createTasks'], f, '$p.createTasks', id);
    final completed = m['completeTasks'] == null
        ? <String, dynamic>{}
        : _map(m['completeTasks'], f, '$p.completeTasks', id);
    final transferred = m['transferTasks'] == null
        ? <String, dynamic>{}
        : _map(m['transferTasks'], f, '$p.transferTasks', id);
    if ((transferred['record'] ?? 0) > 0) {
      _fail(f, '$p.transferTasks.record', id, 'Record transfer forbidden');
    }
    for (final k in ['record', 'coordination', 'care']) {
      if ((created[k] ?? 0) > 0 &&
          ((completed[k] ?? 0) > 0 || (transferred[k] ?? 0) > 0)) {
        _fail(f, '$p.createTasks.$k', id, 'Create and remove same task kind');
      }
    }
    final taskMinutes =
        6 * ((completed['record'] ?? 0) as int) +
        8 * ((completed['coordination'] ?? 0) as int) +
        10 * ((completed['care'] ?? 0) as int);
    final counters = m['counters'] == null
        ? <String, dynamic>{}
        : _map(m['counters'], f, '$p.counters', id);
    _keys(
      counters,
      {'breakMinutes', 'toiletCount'},
      f,
      '$p.counters',
      id,
      required: {},
    );
    for (final k in counters.keys) {
      _nonnegative(counters[k], f, '$p.counters.$k', id);
    }
    final breaks = (counters['breakMinutes'] ?? 0) as int,
        toilet = (counters['toiletCount'] ?? 0) as int;
    if (toilet > 1) {
      _fail(f, '$p.counters.toiletCount', id, 'At most one toilet success');
    }
    if ((m['setBladderAfter'] != null) != (toilet == 1)) {
      _fail(
        f,
        '$p.setBladderAfter',
        id,
        'Toilet success and bladder reset mismatch',
      );
    }
    if (m['setBladderAfter'] != null) {
      _eq(m['setBladderAfter'], 1000, f, '$p.setBladderAfter', id);
    }
    if (breaks + 3 * toilet + taskMinutes > duration) {
      _fail(f, p, id, 'Duration below break, toilet, or task minimum');
    }
    if (m['setFlags'] != null) {
      final flags = _map(m['setFlags'], f, '$p.setFlags', id);
      _keys(
        flags,
        {'hasRested', 'teamSupport'},
        f,
        '$p.setFlags',
        id,
        required: {},
      );
      for (final k in flags.keys) {
        if (flags[k] is! bool) {
          _fail(f, '$p.setFlags.$k', id, 'Expected boolean');
        }
      }
    }
  }
}
