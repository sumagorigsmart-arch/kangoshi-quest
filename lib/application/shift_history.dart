import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import 'workday_view.dart';

/// Immutable display snapshot. Schema 1 deliberately does not deserialize GameState.
class ShiftRecord {
  final String id, contentVersion, balanceVersion, title;
  final int seed, startedAtMillis, endedAtMillis, startMinutes, eventCount;
  final GameResult result;
  final DaySummary? daySummary;
  final List<String> choices;
  const ShiftRecord({
    required this.id,
    required this.contentVersion,
    required this.balanceVersion,
    required this.title,
    required this.seed,
    required this.startedAtMillis,
    required this.endedAtMillis,
    required this.startMinutes,
    required this.eventCount,
    required this.result,
    this.daySummary,
    required this.choices,
  });

  factory ShiftRecord.completed(
    GameState state,
    DateTime startedAt,
    DateTime endedAt,
    List<TitleDefinition> titles,
  ) {
    if (state.phase != 'completed' || state.result == null) {
      throw StateError('Only completed shifts can be archived');
    }
    final titleId = state.result!.primaryTitleId;
    final title = titles.where((t) => t.id == titleId).firstOrNull;
    return ShiftRecord(
      id: state.runId,
      contentVersion: state.contentVersion,
      balanceVersion: state.balanceVersion,
      title: title?.name ?? '称号なし',
      seed: state.seed,
      startedAtMillis: startedAt.millisecondsSinceEpoch,
      endedAtMillis: endedAt.millisecondsSinceEpoch,
      startMinutes: 510,
      eventCount: state.playedEventIds.length,
      result: state.result!,
      daySummary: state.unifiedShift == null
          ? null
          : DaySummary.fromState(state),
      choices: List.unmodifiable(state.choiceHistory),
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'contentVersion': contentVersion,
    'balanceVersion': balanceVersion,
    'title': title,
    'seed': seed,
    'startedAtMillis': startedAtMillis,
    'endedAtMillis': endedAtMillis,
    'startMinutes': startMinutes,
    'eventCount': eventCount,
    'result': result.toJson(),
    if (daySummary != null) 'daySummary': daySummary!.toJson(),
    'choices': choices,
  };

  factory ShiftRecord.fromJson(dynamic value) {
    final m = Map<String, dynamic>.from(value as Map);
    if (m['schemaVersion'] != 1) {
      throw const FormatException('Unknown record version');
    }
    final record = ShiftRecord(
      id: m['id'] as String,
      contentVersion: m['contentVersion'] as String,
      balanceVersion: m['balanceVersion'] as String,
      title: m['title'] as String,
      seed: m['seed'] as int,
      startedAtMillis: m['startedAtMillis'] as int,
      endedAtMillis: m['endedAtMillis'] as int,
      startMinutes: m['startMinutes'] as int,
      eventCount: m['eventCount'] as int,
      result: GameResult.fromJson(m['result']),
      daySummary: m['daySummary'] == null
          ? null
          : DaySummary.fromJson(m['daySummary']),
      choices: List<String>.from(m['choices'] as List),
    );
    if (record.id.isEmpty ||
        record.endedAtMillis < record.startedAtMillis ||
        record.seed <= 0 ||
        record.eventCount < 0 ||
        !{'normal', 'forcedRelief'}.contains(record.result.reason) ||
        record.result.axisScores.keys.toSet().containsAll({
              'patient',
              'team',
              'health',
              'safety',
            }) ==
            false ||
        record.result.grades.keys.toSet().containsAll({
              'patient',
              'team',
              'health',
              'safety',
            }) ==
            false) {
      throw const FormatException('Invalid record');
    }
    return record;
  }
}

abstract class HistoryStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class PreferencesHistoryStore implements HistoryStore {
  static const key = 'shift_history_v1';
  final SharedPreferencesAsync preferences;
  PreferencesHistoryStore(this.preferences);
  @override
  Future<String?> read() => preferences.getString(key);
  @override
  Future<void> write(String value) => preferences.setString(key, value);
  @override
  Future<void> clear() => preferences.remove(key);
}

class MemoryHistoryStore implements HistoryStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async => value = null;
}

/// Serializes updates and rejects duplicate run IDs, including concurrent calls.
class ShiftHistory extends ChangeNotifier {
  final HistoryStore store;
  ShiftHistory(this.store);
  List<ShiftRecord> _records = [];
  List<ShiftRecord> get records => List.unmodifiable(_records);
  String? error;
  Future<void> _pending = Future.value();

  Future<void> load() async {
    try {
      final raw = await store.read();
      if (raw == null || raw.isEmpty) {
        _records = [];
        error = raw == null ? null : '空の保存データを検出しました';
      } else {
        final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (data['schemaVersion'] != 1) {
          throw const FormatException('Unknown history version');
        }
        final entries = (data['records'] as List)
            .map(ShiftRecord.fromJson)
            .toList();
        if (entries.map((e) => e.id).toSet().length != entries.length) {
          throw const FormatException('Duplicate record ID');
        }
        _records = entries
          ..sort((a, b) => b.endedAtMillis.compareTo(a.endedAtMillis));
        error = null;
      }
    } catch (e) {
      _records = [];
      error = '勤務記録を読み込めませんでした。保存データは変更していません。';
    }
    notifyListeners();
  }

  Future<void> add(ShiftRecord record) {
    final operation = _pending.then((_) async {
      if (error != null) throw StateError(error!);
      if (_records.any((r) => r.id == record.id)) return;
      final next = [..._records, record]
        ..sort((a, b) => b.endedAtMillis.compareTo(a.endedAtMillis));
      await store.write(
        jsonEncode({
          'schemaVersion': 1,
          'records': next.map((e) => e.toJson()).toList(),
        }),
      );
      _records = next;
      notifyListeners();
    });
    _pending = operation.catchError((Object _) {
      error = '勤務記録を保存できませんでした';
      notifyListeners();
    });
    return operation;
  }

  Future<void> clear() async {
    await _pending;
    await store.clear();
    _records = [];
    error = null;
    notifyListeners();
  }
}
