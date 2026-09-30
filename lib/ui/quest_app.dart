import 'package:flutter/material.dart';

import '../application/game_controller.dart';
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
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
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
    if (page == 'how') {
      setState(() => page = 'home');
      return;
    }
    if (page != 'game') return;
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
  Widget build(BuildContext context) => PopScope(
    canPop: page == 'home',
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _back();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(page == 'how' ? '遊び方' : '看護師クエスト'),
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
        _ => _home(),
      },
    ),
  );

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
              const SizedBox(height: 20),
              const Text('現在は検証用の3イベントで遊べます。', textAlign: TextAlign.center),
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

  Widget _completed(GameState s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('勤務終了', style: Theme.of(context).textTheme.headlineSmall),
      Text(
        s.result?.reason == 'forcedRelief'
            ? '応援に引き継いで勤務を終えました。'
            : '最終申し送りを終えました。',
      ),
      Text('退勤 ${gameTime(s.timeMinutes)}'),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => setState(() => page = 'home'),
        child: const Text('ホームへ戻る'),
      ),
    ],
  );
}
