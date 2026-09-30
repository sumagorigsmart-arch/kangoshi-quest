import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'dart:ui' as ui;

import '../application/game_controller.dart';
import '../application/shift_history.dart';
import '../application/shift_summary.dart';
import '../domain/models.dart';
import 'share_bridge.dart';
import 'quest_theme.dart';

String gameTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
String signed(int value) => value > 0 ? '+$value' : '$value';
String qualitative(String subject, int change) => change == 0
    ? '$subjectに変化なし'
    : '$subjectが${change > 0 ? '少し良くなった' : '少し悪くなった'}';

class QuestApp extends StatefulWidget {
  final GameController controller;
  const QuestApp({super.key, required this.controller});
  @override
  State<QuestApp> createState() => _QuestAppState();
}

class _QuestAppState extends State<QuestApp> {
  String page = 'home';
  ShiftRecord? selectedRecord;
  final GlobalKey _cardKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    if (widget.controller.state?.phase == 'completed') page = 'result';
    widget.controller.addListener(_refresh);
    widget.controller.history.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    widget.controller.history.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  Widget _pageFrame({required Widget child}) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: QuestSpace.maxWidth),
      child: child,
    ),
  );

  Widget _panel({required Widget child, EdgeInsets? padding}) => Card(
    child: Padding(
      padding: padding ?? const EdgeInsets.all(QuestSpace.medium),
      child: child,
    ),
  );

  Future<void> _start() async {
    if (widget.controller.hasActiveShift) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('進行中の勤務があります'),
          content: const Text('新しい勤務を始めると、進行中の勤務は破棄されます。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('最初からやり直す'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
      await widget.controller.replaceShift();
    } else {
      await widget.controller.lastArchive;
      widget.controller.startNew();
    }
    setState(() => page = 'game');
  }

  Future<void> _back() async {
    if (page == 'detail') {
      setState(() => page = 'history');
      return;
    }
    if (page == 'history' || page == 'result' || page == 'analysis') {
      setState(() => page = 'home');
      return;
    }
    if (page == 'how') {
      setState(() => page = 'home');
      return;
    }
    if (page != 'game') return;
    if (widget.controller.state?.phase == 'completed') {
      setState(() => page = 'home');
      return;
    }
    if (widget.controller.hasActiveShift) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('勤務を中断しますか？'),
          content: const Text('進行状況は保存され、次回も続きから遊べます。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ゲームを続ける'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('勤務を中断してホームへ戻る'),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    setState(() => page = 'home');
  }

  @override
  Widget build(BuildContext context) {
    if (page == 'game' && widget.controller.state?.phase == 'completed') {
      page = 'result';
    }
    return PopScope(
      canPop: page == 'home',
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (page) {
            'how' => '遊び方',
            'history' => '記録帳',
            'analysis' => '勤務のふりかえり',
            'detail' => '勤務記録',
            'result' => '勤務結果',
            _ => '看護師クエスト',
          }),
          leading: page == 'home'
              ? null
              : IconButton(
                  tooltip: '戻る',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _back,
                ),
        ),
        body: switch (page) {
          'how' => _how(),
          'game' => _game(),
          'result' => _result(),
          'history' => _history(),
          'analysis' => _analysis(),
          'detail' =>
            selectedRecord == null
                ? _history()
                : _recordDetail(selectedRecord!),
          _ => _home(),
        },
      ),
    );
  }

  Widget _home() => SafeArea(
    child: _pageFrame(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: QuestSpace.maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.medical_services_outlined,
                size: 42,
                color: QuestColors.teal,
              ),
              const SizedBox(height: 18),
              Text(
                '看護師クエスト',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '今日も無事に定時で帰れ。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 28),
              _panel(
                child: const Text(
                  '病棟の出来事に選択肢で対応し、定時退勤を目指すお仕事RPG。\n1勤務は数分から。',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              if (widget.controller.hasActiveShift) ...[
                FilledButton.icon(
                  onPressed: widget.controller.store.error == null
                      ? () => setState(() => page = 'game')
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('勤務を再開する'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: widget.controller.canStartNew ? _start : null,
                  child: const Text('最初からやり直す'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: widget.controller.canStartNew ? _start : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('勤務をはじめる'),
                ),
              if (widget.controller.store.error != null)
                Text(
                  widget.controller.store.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (widget.controller.archiveError != null)
                Text(
                  widget.controller.archiveError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (widget.controller.store.canRestoreBackup)
                OutlinedButton(
                  onPressed: () async {
                    await widget.controller.store.restoreBackup();
                    if (mounted) setState(() {});
                  },
                  child: const Text('バックアップから復元'),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => page = 'how'),
                child: const Text('遊び方'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => setState(() => page = 'history'),
                child: const Text('記録帳'),
              ),
              OutlinedButton(
                onPressed: () => setState(() => page = 'analysis'),
                child: const Text('勤務のふりかえり'),
              ),
              TextButton(onPressed: _deleteAll, child: const Text('すべての記録を削除')),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _how() => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Text('架空の日勤病棟を題材にした、風刺的なお仕事RPGです。'),
        SizedBox(height: 16),
        Text(
          '患者対応、チームとの関係、自分の体力やメンタル、残務が競合します。選択を重ね、終業時には記録・調整・ケアを処理して申し送りします。',
        ),
        SizedBox(height: 16),
        Text('イベントを読む時間やアプリを閉じている時間では、ゲーム内時刻は進みません。選択と「次へ」で進みます。'),
      ],
    ),
  );

  Widget _game() {
    final s = widget.controller.state;
    if (s == null) return const Center(child: Text('勤務がありません'));
    final finish = widget.controller.content.balance.plannedFinish;
    final remaining = finish - s.timeMinutes;
    final reached = remaining <= 0;
    return SafeArea(
      child: _pageFrame(
        child: ListView(
          key: const Key('gameScroll'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ゲーム内時刻　定時 17:15',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      gameTime(s.timeMinutes),
                      key: ValueKey(s.timeMinutes),
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            color: reached && s.tasks.total > 0
                                ? QuestColors.danger
                                : QuestColors.teal,
                          ),
                    ),
                  ),
                  Text(
                    reached
                        ? s.tasks.total > 0
                              ? '定時を過ぎました。残務${s.tasks.total}件を片づけて退勤へ。'
                              : '定時です。最後の申し送りで退勤へ。'
                        : '定時まであと$remaining分',
                    style: TextStyle(
                      color: reached && s.tasks.total > 0
                          ? QuestColors.danger
                          : QuestColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _meters(s),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              key: const Key('tasks'),
              tilePadding: EdgeInsets.zero,
              title: Text('残務 ${s.tasks.total}件'),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '記録 ${s.tasks.record}件　調整 ${s.tasks.coordination}件　ケア ${s.tasks.care}件',
                  ),
                ),
              ],
            ),
            Text(
              '累計ナースコール ${s.counters.callCount}件',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.controller.store.error != null)
              Text(
                widget.controller.store.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            if (s.phase == 'completed')
              _completed(s)
            else if (s.phase == 'showingOutcome')
              _outcome(s)
            else
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey(s.eventInstanceId),
                  child: _event(s),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _meters(GameState s) {
    Widget meter(String name, String key, bool reverse) {
      final value = s.meters[key]!;
      final trouble = reverse ? value >= 7500 : value <= 2500;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$name ${reverse ? (value >= 7500 ? 'つらい' : '余裕あり') : (value <= 2500 ? '危険' : '維持中')}',
                softWrap: true,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: value / 10000,
                minHeight: 7,
                color: trouble
                    ? QuestColors.danger
                    : reverse
                    ? QuestColors.amber
                    : QuestColors.teal,
                backgroundColor: const Color(0xffe2e5dd),
                semanticsLabel: '$name $value / 10000',
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [meter('体力', 'hp', false), meter('メンタル', 'mental', false)],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [meter('膀胱', 'bladder', true), meter('空腹', 'hunger', true)],
        ),
      ],
    );
  }

  Widget _event(GameState s) {
    final closing = s.currentEventId == 'closing_tasks';
    final handover = s.currentEventId == 'final_handover';
    final event = widget.controller.event;
    final title = closing
        ? '終業処理'
        : handover
        ? '最終申し送り'
        : event?.title ?? '通常業務';
    final description = closing
        ? '残っている記録・調整・ケアを処理します。調整とケアは合意のある引継ぎを相談できます。'
        : handover
        ? '残務を確認し、最後の申し送りをします。'
        : event?.description ?? '通常業務を進めます。';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.timeMinutes >= widget.controller.content.balance.plannedFinish)
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('定時です。', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  s.tasks.total == 0
                      ? '残務はありません。最後の申し送りをして帰りましょう。'
                      : '残務は${s.tasks.total}件。片づけるか、相談して引き継ぎましょう。',
                ),
              ],
            ),
          ),
        if (s.timeMinutes >= widget.controller.content.balance.plannedFinish)
          const SizedBox(height: 12),
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                closing || handover ? '終業処理カード' : (event?.category ?? '病棟の出来事'),
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: QuestColors.teal),
              ),
              const SizedBox(height: 8),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              Text(description, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'どう動く？ ひとつ選ぶと進みます',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final choice in widget.controller.choices) ...[
          OutlinedButton(
            key: Key('choice-${choice.choiceId}'),
            onPressed: widget.controller.sending
                ? null
                : () => widget.controller.select(
                    s.eventInstanceId!,
                    choice.choiceId,
                  ),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              backgroundColor: QuestColors.paper,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              minimumSize: const Size.fromHeight(64),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(choice.label, softWrap: true),
                Text(
                  choice.hint,
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _outcome(GameState s) {
    final view = widget.controller.outcomeView;
    final selectedId = s.choiceHistory.isEmpty
        ? null
        : s.choiceHistory.last.split(':').elementAtOrNull(1);
    String? selectedLabel;
    for (final choice in widget.controller.engine.choices(
      s.copyWith(phase: 'awaitingChoice'),
    )) {
      if (choice.choiceId == selectedId) selectedLabel = choice.label;
    }
    selectedLabel ??= switch ((s.currentEventId, selectedId)) {
      ('closing_tasks', 'record') => '記録を終える',
      ('closing_tasks', 'coordination') => '調整を終える',
      ('closing_tasks', 'care') => 'ケアの残務を終える',
      ('closing_tasks', 'consult') => '合意引継ぎを相談',
      _ => null,
    };
    final changes = <String>[
      if (view != null) ...[
        for (final entry in {
          'hp': '体力',
          'mental': 'メンタル',
          'bladder': '膀胱',
          'hunger': '空腹',
        }.entries)
          if (view.meterChanges[entry.key] != 0)
            '${entry.value} ${signed(view.meterChanges[entry.key]!)}',
        if (view.taskChanges.total != 0)
          '残タスク ${signed(view.taskChanges.total)}',
        if (view.patientChange != 0) '患者対応 ${signed(view.patientChange)}',
        if (view.teamChange != 0) 'チーム ${signed(view.teamChange)}',
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('行動結果', style: Theme.of(context).textTheme.headlineSmall),
              if (selectedLabel != null) ...[
                const SizedBox(height: 6),
                Text('選んだ行動：$selectedLabel'),
              ],
              const SizedBox(height: 10),
              Text(
                s.outcomeText ?? s.currentOutcome?.text ?? '',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              if (view != null) ...[
                Text(
                  '+${view.elapsedMinutes}分',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(color: QuestColors.amber),
                ),
                Text(
                  '経過時間 ${view.elapsedMinutes}分',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in changes) Chip(label: Text(item)),
                  ],
                ),
              ] else
                const Text('結果の変化は再開前の画面で確認できます。'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('next'),
          onPressed: widget.controller.sending ? null : widget.controller.next,
          child: const Text('次へ'),
        ),
      ],
    );
  }

  Widget _completed(GameState s) => const Text('勤務終了');

  Widget _result() {
    final state = widget.controller.state!;
    final record =
        widget.controller.history.records
            .where((e) => e.id == state.runId)
            .firstOrNull ??
        ShiftRecord.completed(
          state,
          DateTime.now(),
          DateTime.now(),
          widget.controller.content.titles,
        );
    return _recordView(record, live: true);
  }

  Widget _recordDetail(ShiftRecord record) => _recordView(record, live: false);

  Widget _recordView(ShiftRecord record, {required bool live}) {
    final result = record.result;
    final label = result.reason == 'forcedRelief'
        ? '応援を呼んで勤務終了'
        : result.overtimeMinutes == 0
        ? '定時退勤！'
        : '本日の退勤 ${gameTime(result.finishTime)}';
    const axes = {
      'patient': '患者対応',
      'team': 'チーム',
      'health': '自分の健康',
      'safety': '安全',
    };
    return SafeArea(
      child: _pageFrame(
        child: ListView(
          key: Key(live ? 'resultScroll' : 'detailScroll'),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('看護師クエスト　勤務結果'),
                  const SizedBox(height: 16),
                  Text('退勤時刻', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    gameTime(result.finishTime),
                    style: Theme.of(context).textTheme.headlineLarge
                        ?.copyWith(fontSize: 52, color: QuestColors.teal),
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(
                    result.overtimeMinutes == 0
                        ? '残業時間　0分'
                        : '残業時間　${result.overtimeMinutes}分',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text('4軸評価', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _panel(
              child: Column(
                children: [
                  for (final entry in axes.entries) ...[
                    Row(
                      children: [
                        Expanded(child: Text(entry.value)),
                        Text(
                          '${result.grades[entry.key]}　${result.axisScores[entry.key]}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: ((result.axisScores[entry.key] ?? 0) / 10000)
                          .clamp(0, 1),
                      minHeight: 6,
                    ),
                    if (entry.key != 'safety') const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('本日の称号'),
                  const SizedBox(height: 4),
                  Text(
                    record.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    result.reason == 'forcedRelief'
                        ? '残務を応援へ引き継いで勤務を終えました。'
                        : result.overtimeMinutes == 0
                        ? '最終申し送りを終え、定時で退勤しました。'
                        : '最終申し送りを終え、今日の勤務を締めくくりました。',
                  ),
                ],
              ),
            ),
            if (live) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: widget.controller.canStartNew ? _start : null,
                child: const Text('もう一度勤務する'),
              ),
            ],
            const SizedBox(height: 18),
            Text('今日のふりかえり', style: Theme.of(context).textTheme.titleLarge),
            Text(
              '勤務 ${gameTime(record.startMinutes)} → ${gameTime(result.finishTime)} ・イベント ${record.eventCount}件',
            ),
            Text(
              '行動 ${record.choices.length}回 ・休憩 ${result.counters.breakMinutes}分 ・最終残務 ${result.remainingTasks.total}件',
            ),
            const SizedBox(height: 12),
            if (live && widget.controller.history.error != null)
              Text(
                widget.controller.history.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (live && widget.controller.store.error != null)
              Text(
                widget.controller.store.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (live && widget.controller.archiveError != null)
              Text(
                widget.controller.archiveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final message = await shareResultText(shareText(record));
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(message)));
                }
              },
              icon: const Icon(Icons.share),
              label: const Text('結果をテキストで共有'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showShareCard(record),
              icon: const Icon(Icons.image),
              label: const Text('共有画像を作る'),
            ),
            if (live) ...[
              OutlinedButton(
                onPressed: () => setState(() => page = 'home'),
                child: const Text('ホームへ戻る'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _history() {
    final history = widget.controller.history;
    return SafeArea(
      child: _pageFrame(
        child: ListView(
          key: const Key('historyScroll'),
          padding: const EdgeInsets.all(16),
          children: [
            if (history.error != null)
              Text(
                history.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (history.records.isEmpty) ...[
              const SizedBox(height: 60),
              const Icon(
                Icons.menu_book_outlined,
                size: 48,
                color: QuestColors.teal,
              ),
              const SizedBox(height: 12),
              const Text('まだ勤務記録がありません', textAlign: TextAlign.center),
              const Text('最初の勤務から、ここに記録が残ります。', textAlign: TextAlign.center),
            ],
            for (final record in history.records)
              Card(
                child: ListTile(
                  onTap: () => setState(() {
                    selectedRecord = record;
                    page = 'detail';
                  }),
                  title: Text(
                    '${record.endedAtMillis == 0 ? '' : _date(record.endedAtMillis)}　${gameTime(record.result.finishTime)}',
                  ),
                  subtitle: Text('${_kind(record.result)}　${record.title}'),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _analysis() {
    final data = ShiftSummary.fromRecords(
      widget.controller.history.records,
      titleNames: {
        for (final title in widget.controller.content.titles)
          title.id: title.name,
      },
    );
    return SafeArea(
      child: _pageFrame(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('勤務のふりかえり', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            if (data.total == 0)
              _panel(child: const Text('まだ勤務記録がありません。勤務を終えると、ここに記録が集まります。')),
            if (data.total > 0) ...[
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _stat('総勤務回数', '${data.total}回'),
                    _stat('定時退勤率', '${data.onTimeRate.toStringAsFixed(1)}%'),
                    _stat('総残業時間', '${data.overtimeMinutes}分'),
                    _stat(
                      '平均残業時間',
                      '${data.averageOvertime.toStringAsFixed(1)}分',
                    ),
                    _stat('応援終了回数', '${data.relief}回'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('4軸の平均', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final axis in axisLabels.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: _stat(
                          axis.value,
                          '${data.axisAverages[axis.key]!.toStringAsFixed(0)} / 10000',
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('獲得した称号', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final title in data.titleCounts.entries)
                      _stat(title.key, '${title.value}回'),
                    if (data.titleCounts.isEmpty) const Text('まだ称号がありません'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('すべての記録を削除'),
        content: const Text('進行中勤務・勤務履歴・累計をこの端末から削除します。元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.deleteAllRecords();
      if (mounted) {
        setState(() {
          selectedRecord = null;
          page = 'home';
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('削除できませんでした')));
      }
    }
  }

  Future<void> _showShareCard(ShiftRecord record) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.all(12),
        content: SizedBox(
          width: (MediaQuery.sizeOf(context).width - 80).clamp(0.0, 360.0),
          child: SingleChildScrollView(
            child: RepaintBoundary(key: _cardKey, child: _shareCard(record)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
          FilledButton(
            onPressed: () async {
              final boundary =
                  _cardKey.currentContext?.findRenderObject()
                      as RenderRepaintBoundary?;
              if (boundary == null) return;
              final image = await boundary.toImage(pixelRatio: 2.5);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (data == null) return;
              final message = await shareResultPng(data.buffer.asUint8List());
              if (mounted) {
                ScaffoldMessenger.of(this.context)
                    .showSnackBar(SnackBar(content: Text(message)));
              }
            },
            child: const Text('画像を共有・保存'),
          ),
        ],
      ),
    );
  }

  Widget _shareCard(ShiftRecord record) {
    final r = record.result;
    return Container(
      color: QuestColors.paper,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '看護師クエスト',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const Text('今日も無事に定時で帰れ。', style: TextStyle(fontSize: 15)),
          const SizedBox(height: 24),
          const Text('退勤時刻'),
          Text(
            shiftTime(r.finishTime),
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              color: QuestColors.teal,
            ),
          ),
          Text(
            '残業時間  ${r.overtimeMinutes}分',
            style: const TextStyle(fontSize: 21),
          ),
          const SizedBox(height: 24),
          const Text('4軸評価'),
          for (final axis in axisLabels.entries)
            Text(
              '${axis.value}  ${r.axisScores[axis.key]} / 10000  ${r.grades[axis.key]}',
              style: const TextStyle(fontSize: 16),
            ),
          const SizedBox(height: 24),
          const Text('本日の称号'),
          Text(
            record.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _date(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  String _kind(GameResult r) => r.reason == 'forcedRelief'
      ? '応援終了'
      : r.overtimeMinutes == 0
      ? '定時'
      : '残業';
}
