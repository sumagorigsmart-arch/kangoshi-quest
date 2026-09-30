import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/content_loader.dart';
import '../domain/models.dart';
import 'game_controller.dart';

/// One complete transition per value. The previous valid value is retained.
class PersistentShiftStore implements ShiftStore {
  static const key = 'active_shift_v1';
  static const backupKey = 'active_shift_v1_backup';
  final SharedPreferencesAsync preferences;
  final ContentBundle content;
  PersistentShiftStore(this.preferences, this.content);

  GameState? _current;
  OutcomeView? _outcomeView;
  int? _startedAtMillis;
  @override
  String? error;
  @override
  bool get durable => true;
  bool _blocked = false;
  bool _backupAvailable = false;
  @override
  bool get canRestoreBackup => _backupAvailable;
  Future<void> _pending = Future.value();
  VoidCallback? _onChanged;
  @override
  void setOnChanged(VoidCallback callback) => _onChanged = callback;

  @override
  GameState? get current => _current;
  @override
  OutcomeView? get outcomeView => _outcomeView;
  @override
  int? get startedAtMillis => _startedAtMillis;
  @override
  void setStartedAtMillis(int value) => _startedAtMillis = value;

  Map<String, dynamic> _decode(String raw) {
    final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (data['schemaVersion'] != 1) throw const FormatException('schema');
    final state = GameState.fromJson(data['state']);
    final counters = Map<String, dynamic>.from(
      Map<String, dynamic>.from(data['state'] as Map)['counters'] as Map,
    );
    if (state.schemaVersion != 1 ||
        state.contentVersion != content.contentVersion ||
        state.balanceVersion != content.balanceVersion ||
        state.runId.isEmpty ||
        state.seed <= 0 ||
        state.seed > 0xffffffff ||
        state.rngState < 0 ||
        state.rngState > 0xffffffff ||
        !{
          'awaitingChoice',
          'showingOutcome',
          'completed',
        }.contains(state.phase) ||
        (state.phase != 'completed' &&
            (state.currentEventId == null || state.eventInstanceId == null)) ||
        (state.phase == 'showingOutcome' &&
            (state.currentOutcomeId == null || state.currentOutcome == null)) ||
        (state.phase == 'completed' && state.result == null) ||
        (state.phase == 'showingOutcome' && data['outcomeView'] == null) ||
        !state.flags.keys.toSet().containsAll({'hasRested', 'teamSupport'}) ||
        !counters.keys.toSet().containsAll({
          'breakMinutes',
          'toiletCount',
          'callCount',
          'admissionCount',
          'acuteChangeCount',
          'completedRecord',
          'completedCoordination',
          'completedCare',
          'transferredCoordination',
          'transferredCare',
          'handoverAttempts',
        }) ||
        !state.meters.keys.toSet().containsAll({
          'hp',
          'mental',
          'bladder',
          'hunger',
        }) ||
        !state.scores.keys.toSet().containsAll({'patient', 'team', 'risk'})) {
      throw const FormatException('Invalid shift');
    }
    final started = data['startedAtMillis'] as int;
    if (started <= 0) throw const FormatException('Invalid start');
    if (data['outcomeView'] != null) {
      final v = Map<String, dynamic>.from(data['outcomeView'] as Map);
      final changes = Map<String, int>.from(v['meterChanges'] as Map);
      if (!changes.keys.toSet().containsAll({
        'hp',
        'mental',
        'bladder',
        'hunger',
      })) {
        throw const FormatException('Invalid outcome view');
      }
      OutcomeView(
        v['elapsedMinutes'] as int,
        changes,
        TaskState.fromJson(v['taskChanges']),
        v['patientChange'] as int,
        v['teamChange'] as int,
      );
    }
    return data;
  }

  void _apply(Map<String, dynamic> data) {
    _current = GameState.fromJson(data['state']);
    _startedAtMillis = data['startedAtMillis'] as int;
    final raw = data['outcomeView'];
    if (raw == null) {
      _outcomeView = null;
    } else {
      final v = Map<String, dynamic>.from(raw as Map);
      _outcomeView = OutcomeView(
        v['elapsedMinutes'] as int,
        Map<String, int>.from(v['meterChanges'] as Map),
        TaskState.fromJson(v['taskChanges']),
        v['patientChange'] as int,
        v['teamChange'] as int,
      );
    }
  }

  Future<void> load() async {
    final primary = await preferences.getString(key);
    if (primary == null) return;
    try {
      _apply(_decode(primary));
    } catch (_) {
      final backup = await preferences.getString(backupKey);
      if (backup != null) {
        try {
          _apply(_decode(backup));
          // Keep the corrupt primary intact until the user explicitly clears it.
          _blocked = true;
          _backupAvailable = true;
          error = '進行中勤務の保存データが破損しています。バックアップから復元できます。';
          return;
        } catch (_) {}
      }
      _blocked = true;
      error = '進行中勤務を読み込めませんでした。保存データは変更していません。';
    }
  }

  @override
  Future<void> restoreBackup() async {
    if (!_backupAvailable) throw StateError('バックアップがありません');
    final backup = await preferences.getString(backupKey);
    if (backup == null) throw StateError('バックアップがありません');
    _decode(backup);
    // Explicit recovery preserves the invalid primary for support/export.
    final invalid = await preferences.getString(key);
    if (invalid != null) await preferences.setString('${key}_corrupt', invalid);
    await preferences.setString(key, backup);
    _blocked = false;
    _backupAvailable = false;
    error = null;
    _onChanged?.call();
  }

  @override
  void save(GameState state, OutcomeView? outcomeView) {
    if (_blocked) throw StateError(error ?? '保存できません');
    _current = state;
    _outcomeView = outcomeView;
    final raw = jsonEncode({
      'schemaVersion': 1,
      'startedAtMillis': _startedAtMillis,
      'state': state.toJson(),
      'outcomeView': outcomeView == null
          ? null
          : {
              'elapsedMinutes': outcomeView.elapsedMinutes,
              'meterChanges': outcomeView.meterChanges,
              'taskChanges': outcomeView.taskChanges.toJson(),
              'patientChange': outcomeView.patientChange,
              'teamChange': outcomeView.teamChange,
            },
    });
    _pending = _pending
        .then((_) async {
          final previous = await preferences.getString(key);
          if (previous != null) {
            _decode(previous);
            await preferences.setString(backupKey, previous);
          }
          await preferences.setString(key, raw);
        })
        .catchError((Object _) {
          error = '進行中勤務を保存できませんでした';
          _blocked = true;
          _onChanged?.call();
        });
  }

  @override
  Future<void> flush() async {
    await _pending;
    if (error != null) throw StateError(error!);
  }

  @override
  void clear() {
    _current = null;
    _outcomeView = null;
    _startedAtMillis = null;
  }

  @override
  Future<void> clearPersisted() async {
    await _pending;
    await preferences.remove(key);
    await preferences.remove(backupKey);
    clear();
    error = null;
    _blocked = false;
    _backupAvailable = false;
    await preferences.remove('${key}_corrupt');
    _onChanged?.call();
  }
}
