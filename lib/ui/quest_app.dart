import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../application/shift_history.dart';
import '../domain/models.dart';

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
              child: const Text('新しい勤務を始める'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
      widget.controller.replaceShift();
    } else {
      widget.controller.startNew();
    }
    setState(() => page = 'game');
  }

  Future<void> _back() async {
    if (page == 'detail') {
      setState(() => page = 'history');
      return;
    }
    if (page == 'history' || page == 'result') {
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
          content: const Text('進行状況は、このアプリを開いている間メモリに保持します。'),
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
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '看護師クエスト',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              const Text('今日も無事に定時で帰れ。', textAlign: TextAlign.center),
              const SizedBox(height: 32),
              FilledButton(onPressed: _start, child: const Text('勤務を始める')),
              if (widget.controller.hasActiveShift) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => setState(() => page = 'game'),
                  child: const Text('勤務のつづき'),
                ),
              ],
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
              const SizedBox(height: 20),
              const Text(
                '正式イベント50件から、今日の勤務が始まります。',
                textAlign: TextAlign.center,
              ),
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
    return SafeArea(
      child: ListView(
        key: const Key('gameScroll'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'ゲーム内時刻 ${gameTime(s.timeMinutes)}　定時 17:15',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '残り時間 ${s.timeMinutes < finish ? '${finish - s.timeMinutes}分' : '0分（定時後）'}',
          ),
          const SizedBox(height: 12),
          _meters(s),
          const SizedBox(height: 8),
          ExpansionTile(
            key: const Key('tasks'),
            tilePadding: EdgeInsets.zero,
            title: Text(
              '残務 ${s.tasks.total}件　記録 ${s.tasks.record}・調整 ${s.tasks.coordination}・ケア ${s.tasks.care}',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '記録 ${s.tasks.record}件　調整 ${s.tasks.coordination}件　ケア ${s.tasks.care}件',
                ),
              ),
            ],
          ),
          Text('累計ナースコール ${s.counters.callCount}件'),
          const SizedBox(height: 20),
          if (s.phase == 'completed')
            _completed(s)
          else if (s.phase == 'showingOutcome')
            _outcome(s)
          else
            _event(s),
        ],
      ),
    );
  }

  Widget _meters(GameState s) {
    Widget meter(String name, String key, bool reverse) {
      final value = s.meters[key]!;
      return Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name $value / 10000', softWrap: true),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: value / 10000,
                  color: reverse ? Colors.orange : Colors.teal,
                ),
              ],
            ),
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
        if (closing || handover) const Text('終業処理カード'),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(description),
        const SizedBox(height: 16),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('行動結果', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(s.outcomeText ?? s.currentOutcome?.text ?? ''),
        const SizedBox(height: 12),
        if (view != null) ...[
          Text('経過時間 ${view.elapsedMinutes}分'),
          Text(
            '体力 ${signed(view.meterChanges['hp']!)}　メンタル ${signed(view.meterChanges['mental']!)}',
          ),
          Text(
            '膀胱 ${signed(view.meterChanges['bladder']!)}　空腹 ${signed(view.meterChanges['hunger']!)}',
          ),
          Text(
            'タスク変化　記録 ${signed(view.taskChanges.record)}　調整 ${signed(view.taskChanges.coordination)}　ケア ${signed(view.taskChanges.care)}',
          ),
          Text(qualitative('患者対応', view.patientChange)),
          Text(qualitative('チーム関係', view.teamChange)),
        ] else
          const Text('結果の変化は再開前の画面で確認できます。'),
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
      child: ListView(
        key: Key(live ? 'resultScroll' : 'detailScroll'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text('勤務終了', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(label, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('本日の称号'),
                  Text(
                    record.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '勤務 ${gameTime(record.startMinutes)} → ${gameTime(result.finishTime)}',
          ),
          Text('予定終了 ${gameTime(result.plannedFinishTime)}'),
          Text(
            result.overtimeMinutes == 0
                ? '残業なし'
                : '残業 ${result.overtimeMinutes}分',
          ),
          const SizedBox(height: 18),
          Text('今日のふりかえり', style: Theme.of(context).textTheme.titleLarge),
          Text('イベント ${record.eventCount}件・行動 ${record.choices.length}回'),
          Text(
            '休憩 ${result.counters.breakMinutes}分・最終残務 ${result.remainingTasks.total}件',
          ),
          Text(
            result.reason == 'forcedRelief'
                ? '残務を応援へ引き継いで終了しました。'
                : '最終申し送りを終えました。',
          ),
          const SizedBox(height: 18),
          Text('4軸評価', style: Theme.of(context).textTheme.titleLarge),
          for (final entry in axes.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.value),
              subtitle: Text(
                '${result.axisScores[entry.key]} / 10000　評価 ${result.grades[entry.key]}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: 12),
          if (live && widget.controller.history.error != null)
            Text(
              widget.controller.history.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (live) ...[
            FilledButton(onPressed: _start, child: const Text('もう一度勤務する')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() => page = 'home'),
              child: const Text('ホームへ戻る'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _history() {
    final history = widget.controller.history;
    return SafeArea(
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
            const Text('まだ勤務記録がありません', textAlign: TextAlign.center),
            const Text('最初の勤務に挑戦してみよう', textAlign: TextAlign.center),
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
