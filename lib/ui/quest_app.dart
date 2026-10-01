import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'dart:ui' as ui;

import '../application/game_controller.dart';
import '../application/shift_history.dart';
import '../application/shift_summary.dart';
import '../application/workday_view.dart';
import '../domain/models.dart';
import '../domain/day_shift.dart';
import 'share_bridge.dart';
import 'quest_theme.dart';

String gameTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
String signed(int value) => value > 0 ? '+$value' : '$value';
String _dynamicKindLabel(String kind) => switch (kind) {
  'call' => 'ナースコール',
  'toileting' => '突発の排泄介助',
  'infusion' => '点滴関連',
  'examination' => '検査呼び出し',
  'order' => '医師追加指示',
  'family' => '家族対応',
  'emergency' => '急変',
  'admission' => '新規入院',
  _ => 'その他',
};
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
  final Set<String> _handoffSelection = {};
  int? _previousQueueCount;
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
                  '患者別の予定業務と割り込みをさばき、定時退勤を目指すお仕事RPG。\n1勤務は数分から。',
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
        Text('患者ごとの予定業務と割り込みを優先順位をつけて処理します。ケアを終えると記録が増え、17:00に残った仕事は残業で処理します。'),
        SizedBox(height: 16),
        Text('イベントを読む時間やアプリを閉じている時間では、ゲーム内時刻は進みません。選択と「次へ」で進みます。'),
      ],
    ),
  );

  Widget _game() {
    final s = widget.controller.state;
    if (s == null) return const Center(child: Text('勤務がありません'));
    if (s.unifiedShift != null) return _unifiedGame(s);
    final finish = s.workQueue == null
        ? widget.controller.content.balance.plannedFinish
        : 1020;
    final remaining = finish - s.timeMinutes;
    final reached = remaining <= 0;
    final pendingWork = s.workQueue?.pendingCount ?? s.tasks.total;
    return SafeArea(
      child: _pageFrame(
        child: SingleChildScrollView(
          key: const Key('gameScroll'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      s.workQueue == null
                          ? 'ゲーム内時刻　定時 17:15'
                          : 'ゲーム内時刻　定時 17:00',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        gameTime(s.timeMinutes),
                        key: ValueKey(s.timeMinutes),
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              color: reached && pendingWork > 0
                                  ? QuestColors.danger
                                  : QuestColors.teal,
                            ),
                      ),
                    ),
                    Text(
                      reached
                          ? pendingWork > 0
                                ? s.workQueue == null
                                      ? '定時を過ぎました。残務${s.tasks.total}件を片づけて退勤へ。'
                                      : '定時到達。未処理$pendingWork件を確認してください。'
                                : '定時です。最後の申し送りで退勤へ。'
                          : '定時まであと$remaining分',
                      style: TextStyle(
                        color: reached && pendingWork > 0
                            ? QuestColors.danger
                            : QuestColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (s.workQueue != null) _workOverview(s),
                    ExpansionTile(
                      key: const Key('conditionMeters'),
                      title: const Text('体調・状態（補助情報）'),
                      tilePadding: EdgeInsets.zero,
                      children: [_meters(s)],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (s.workQueue != null) ...[
                const SizedBox(height: 12),
                _workTaskPanel(s),
              ],
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _unifiedGame(GameState s) {
    if (s.timeMinutes >= 1020 &&
        s.phase == 'taskSelection' &&
        s.unifiedShift!.exitView != 'work') {
      return _exitScreen(s);
    }
    final queue = s.workQueue!;
    final status = s.workStatus!;
    final available = availableTasks(
      queue,
      s.timeMinutes,
      strictDependencies: s.unifiedShift?.consequencesEnabled ?? false,
    );
    final next =
        queue.pending
            .where(
              (t) =>
                  t.taskType == WorkTaskType.routine &&
                  t.scheduledAt != null &&
                  t.scheduledAt! > s.timeMinutes,
            )
            .toList()
          ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
    final pending = queue.pending;
    final overview = QueueOverview.from(queue);
    final previous = _previousQueueCount;
    _previousQueueCount = overview.total;
    final interrupted = pending
        .where((t) => t.status == WorkTaskStatus.interrupted)
        .toList();
    final activeId = s.unifiedShift!.activeTaskId;
    final active = activeId == null
        ? null
        : queue.tasks.where((t) => t.taskId == activeId).firstOrNull;
    final newest = queue.tasks
        .where((t) => t.taskId == 'dynamic-${s.unifiedShift!.interruptSerial}')
        .firstOrNull;
    return SafeArea(
      child: _pageFrame(
        child: SingleChildScrollView(
          key: const Key('unifiedGameScroll'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clockLabel(s.timeMinutes),
                      key: const Key('unifiedClock'),
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(color: QuestColors.teal),
                    ),
                    Text(
                      phaseLabel(s.shiftPhase!),
                      key: const Key('unifiedPhase'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      status.scheduledEndReached
                          ? '残業 ${durationLabel(status.overtimeMinutes)}'
                          : '定時まで ${durationLabel(1020 - s.timeMinutes)}',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          '未処理 ${status.unfinishedTaskCount}',
                          key: const Key('unifiedPending'),
                        ),
                        Text(
                          '期限超過 ${status.overdueCount}',
                          key: const Key('unifiedOverdue'),
                        ),
                        Text(
                          '未記録 ${status.unfinishedRecordCount}',
                          key: const Key('unifiedRecords'),
                        ),
                        Text(
                          '緊急 ${status.urgentCount}',
                          key: const Key('unifiedUrgent'),
                        ),
                      ],
                    ),
                    Text(
                      '残っている仕事 ${overview.total}件',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'ケア ${overview.care} / 記録 ${overview.records} / 中断 ${overview.interrupted} / その他 ${overview.other}',
                    ),
                    if (previous != null && previous != overview.total)
                      Text(
                        '残務 $previous → ${overview.total}',
                        key: const Key('queueChange'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (s.phase == 'awaitingChoice') ...[
                _event(s),
                const SizedBox(height: 12),
              ] else if (s.phase == 'showingOutcome') ...[
                _panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '行動結果',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(s.outcomeText ?? '対応を終えました'),
                      Text(
                        '経過時間 ${widget.controller.outcomeView?.elapsedMinutes ?? 0}分',
                      ),
                      Text(
                        '現在の未処理 ${queue.pendingCount}件・未記録 ${queue.documentationCount}件',
                      ),
                      FilledButton(
                        key: const Key('next'),
                        onPressed: widget.controller.next,
                        child: const Text('次へ'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (active != null)
                _panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        active.status == WorkTaskStatus.interrupted
                            ? '割り込み前の仕事'
                            : 'いま処理中の仕事',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        active.title,
                        key: const Key('activeTask'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        '${taskPriorityLabel(active)}・${active.interruptionCount > 0 ? '${active.interruptionCount}回中断 / ' : ''}あと ${active.remainingDuration ?? s.unifiedShift!.activeTaskRemaining}分',
                      ),
                    ],
                  ),
                ),
              if (s.unifiedShift!.notice != null &&
                  newest != null &&
                  s.timeMinutes - s.unifiedShift!.lastInterruptAt <= 10)
                Card(
                  color: newest.priority == WorkPriority.urgent
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          newest.priority == WorkPriority.urgent
                              ? '🚨 緊急割り込み'
                              : '割り込みが発生しました',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(newest.title),
                        Text(s.unifiedShift!.notice!),
                        if (active != null &&
                            active.status == WorkTaskStatus.interrupted)
                          Text(
                            '${active.title}を中断・残り ${active.remainingDuration}分',
                          ),
                      ],
                    ),
                  ),
                ),
              if (s.unifiedShift!.consequences.isNotEmpty &&
                  s.timeMinutes -
                          s.unifiedShift!.consequences.last.triggeredAt <=
                      10)
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      '${s.unifiedShift!.consequences.last.reason} → '
                      '${queue.tasks.firstWhere((t) => t.taskId == s.unifiedShift!.consequences.last.generatedTaskIds.first).title}が追加されました',
                    ),
                  ),
                ),
              if (s.unifiedShift!.consequencesEnabled &&
                  queue.pending.any((t) => t.taskId == 'break') &&
                  s.timeMinutes >= 755 &&
                  breakBlockReason(queue, s.timeMinutes) != null)
                Text('今は休憩に行けない：${breakBlockReason(queue, s.timeMinutes)}'),
              if (interrupted.isNotEmpty)
                _panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '中断中 ${interrupted.length}件',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final task in interrupted.take(3))
                        Text(
                          '${task.title}・あと ${task.remainingDuration ?? task.estimatedMinutes}分',
                        ),
                    ],
                  ),
                ),
              if (active == null && available.isNotEmpty)
                _panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '次に取りかかれる仕事',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        available.first.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        '${taskPriorityLabel(available.first)}・あと ${available.first.remainingDuration ?? available.first.estimatedMinutes}分',
                      ),
                      if (available.first.interruptionCount > 0)
                        Text(
                          '${available.first.interruptionCount}回中断・残り時間から再開',
                        ),
                    ],
                  ),
                ),
              Text('今処理するTask', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              if (available.isEmpty) const Text('現在選べる業務はありません。次の予定を確認してください。'),
              for (final task in available.take(5))
                Card(
                  color: task.priority == WorkPriority.urgent
                      ? Theme.of(context).colorScheme.errorContainer
                      : deadlineState(task, s.timeMinutes) ==
                            DeadlineState.overdue
                      ? Theme.of(context).colorScheme.tertiaryContainer
                      : null,
                  child: ListTile(
                    key: Key('unified-${task.taskId}'),
                    leading: task.patientId == null
                        ? const Icon(Icons.assignment_outlined)
                        : SizedBox(
                            width: 62,
                            child: Center(
                              child: Text(
                                s.unifiedShift!.patients
                                    .firstWhere(
                                      (p) => p.patientId == task.patientId,
                                    )
                                    .bedLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                    title: Text(
                      task.patientId == null
                          ? task.title
                          : task.title.split(' ').skip(1).join(' '),
                    ),
                    subtitle: Text(
                      '${taskPriorityLabel(task)}・${taskStatusLabel(task)}・あと ${task.remainingDuration ?? task.estimatedMinutes}分'
                      '${task.deadline == null ? '' : '・期限 ${clockLabel(task.deadline!)}'}'
                      '${deadlineState(task, s.timeMinutes) == DeadlineState.overdue ? '・期限超過' : ''}',
                    ),
                    trailing: IconButton(
                      tooltip: '${task.title}を処理',
                      icon: const Icon(Icons.play_arrow),
                      onPressed: s.phase == 'taskSelection'
                          ? () =>
                                widget.controller.completeWorkTask(task.taskId)
                          : null,
                    ),
                  ),
                ),
              if (available.length > 5)
                ExpansionTile(
                  title: Text('ほかの仕事 ${available.length - 5}件'),
                  children: [
                    for (final task in available.skip(5))
                      ListTile(
                        key: Key('unified-${task.taskId}'),
                        title: Text(task.title),
                        subtitle: Text(
                          '${taskPriorityLabel(task)}・${taskStatusLabel(task)}・あと ${task.remainingDuration ?? task.estimatedMinutes}分',
                        ),
                        trailing: IconButton(
                          tooltip: '${task.title}を処理',
                          icon: const Icon(Icons.play_arrow),
                          onPressed: s.phase == 'taskSelection'
                              ? () => widget.controller.completeWorkTask(
                                  task.taskId,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              if (pending.isNotEmpty && s.phase == 'taskSelection')
                TextButton(
                  key: const Key('unifiedLater'),
                  onPressed: () => widget.controller.advanceWorkClock(5),
                  child: const Text('あとでやる（5分進める）'),
                ),
              const SizedBox(height: 12),
              Text('次の予定業務', style: Theme.of(context).textTheme.titleLarge),
              if (next.isEmpty) const Text('新しいRoutine Taskはありません'),
              for (final task in next.take(6))
                Text('${gameTime(task.scheduledAt!)}　${task.title}'),
              if (next.length > 6) Text('ほか ${next.length - 6}件'),
              if (status.scheduledEndReached && s.phase == 'taskSelection')
                FilledButton(
                  key: const Key('leaveShift'),
                  onPressed: () => widget.controller.setExitView('decision'),
                  child: const Text('退勤判断へ'),
                ),
              ExpansionTile(
                title: const Text('体調・状態（補助情報）'),
                children: [_meters(s)],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _exitScreen(GameState s) {
    final queue = s.workQueue!;
    final status = s.workStatus!;
    final view = s.unifiedShift!.exitView;
    final transferable = queue.pending.where(canHandOff).toList();
    final blockers = queue.pending
        .where(
          (t) => t.taskType != WorkTaskType.documentation && !canHandOff(t),
        )
        .toList();
    final overview = QueueOverview.from(queue);
    final patients = {
      for (final p in s.unifiedShift!.patients) p.patientId: p.bedLabel,
    };
    return SafeArea(
      child: _pageFrame(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${clockLabel(s.timeMinutes)}　${s.timeMinutes == 1020 ? '定時になりました' : '退勤判断'}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              s.timeMinutes == 1020
                  ? 'しかし、仕事は終わっていません。'
                  : '残業 ${durationLabel(status.overtimeMinutes)}',
            ),
            const SizedBox(height: 12),
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('今日の仕事', style: Theme.of(context).textTheme.titleLarge),
                  Text(
                    '残っている仕事 ${overview.total}件',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'ケア ${overview.care}件・記録 ${overview.records}件・中断 ${overview.interrupted}件・その他 ${overview.other}件',
                  ),
                  Text(
                    '未処理 ${status.unfinishedTaskCount}件　未記録 ${status.unfinishedRecordCount}件',
                  ),
                  Text(
                    '期限超過 ${status.overdueCount}件　緊急 ${status.urgentCount}件',
                  ),
                  Text('引き継ぎ済み ${queue.handedOff.length}件'),
                ],
              ),
            ),
            if (blockers.isNotEmpty || s.unifiedShift!.activeTaskId != null)
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('この仕事を残しては帰れません'),
                    Text('緊急 ${overview.urgent}件・中断 ${overview.interrupted}件'),
                    for (final task in blockers.take(5))
                      Text('・${task.title}（${taskStatusLabel(task)}）'),
                    if (s.unifiedShift!.activeTaskId != null)
                      const Text('・中断中のTaskがあります'),
                  ],
                ),
              ),
            if (blockers.isEmpty && transferable.isNotEmpty)
              const Text('未処理の仕事は、処理するか夜勤へ引き継いでください。'),
            if (view == 'decision') ...[
              FilledButton(
                onPressed: () => widget.controller.setExitView('work'),
                child: const Text('残って仕事する'),
              ),
              OutlinedButton(
                onPressed: transferable.isEmpty
                    ? null
                    : () => widget.controller.setExitView('handoff'),
                child: Text('引き継げる仕事を見る（${transferable.length}件）'),
              ),
              FilledButton(
                key: const Key('finishShift'),
                onPressed: status.canLeave
                    ? () => widget.controller.setExitView('confirm')
                    : null,
                child: const Text('勤務終了'),
              ),
            ],
            if (view == 'handoff') ...[
              Text('夜勤・遅番へ引き継ぐ', style: Theme.of(context).textTheme.titleLarge),
              const Text('重要な仕事と期限超過を確認して選択してください。'),
              for (final task in transferable)
                CheckboxListTile(
                  key: Key('handoff-${task.taskId}'),
                  value: _handoffSelection.contains(task.taskId),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _handoffSelection.add(task.taskId);
                    } else {
                      _handoffSelection.remove(task.taskId);
                    }
                  }),
                  title: Text(
                    '${patients[task.patientId] ?? '病棟'}　${task.title}',
                  ),
                  subtitle: Text(
                    '${taskPriorityLabel(task)}・予定 ${task.scheduledAt == null ? 'なし' : clockLabel(task.scheduledAt!)}'
                    '・期限 ${task.deadline == null ? 'なし' : clockLabel(task.deadline!)}'
                    '${deadlineState(task, s.timeMinutes) == DeadlineState.overdue ? '・期限超過' : ''}',
                  ),
                ),
              if (blockers.isNotEmpty) ...[
                Text(
                  '引き継げない仕事',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final task in blockers.take(8))
                  Text('・${task.title}（${taskStatusLabel(task)}）'),
              ],
              FilledButton(
                onPressed: _handoffSelection.isEmpty
                    ? null
                    : () {
                        if (widget.controller.handOffTasks(_handoffSelection)) {
                          setState(() => _handoffSelection.clear());
                          widget.controller.setExitView('decision');
                        }
                      },
                child: Text('選択した${_handoffSelection.length}件を夜勤へ引き継ぐ'),
              ),
              TextButton(
                onPressed: () => widget.controller.setExitView('decision'),
                child: const Text('退勤判断に戻る'),
              ),
            ],
            if (view == 'confirm') ...[
              Text(
                '本当に帰りますか？',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '引き継ぎ ${queue.handedOff.length}件　未記録 ${status.unfinishedRecordCount}件',
              ),
              const Text('このまま帰ると勤務評価に影響します。'),
              OutlinedButton(
                onPressed: () => widget.controller.setExitView('decision'),
                child: const Text('まだ残る'),
              ),
              FilledButton(
                key: const Key('confirmExit'),
                onPressed: status.canLeave
                    ? widget.controller.finishUnifiedShift
                    : null,
                child: const Text('今日は帰る'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _workOverview(GameState s) {
    final queue = s.workQueue!;
    final phase = s.shiftPhase!;
    final routine = queue.routine
        .where((t) => t.status == WorkTaskStatus.pending)
        .toList();
    final currentRoutine = routine.where((t) => t.shiftPhase == phase).toList();
    final futureRoutine = routine
        .where((t) => t.scheduledAt != null && t.scheduledAt! >= s.timeMinutes)
        .toList();
    final next = currentRoutine.isNotEmpty
        ? currentRoutine.first
        : futureRoutine.isNotEmpty
        ? futureRoutine.first
        : null;
    final approaching = queue.pending
        .where(
          (t) =>
              t.deadline != null &&
              deadlineState(t, s.timeMinutes) != DeadlineState.comfortable,
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          phaseLabel(phase),
          key: const Key('shiftPhase'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text('次：${next?.title ?? '残務処理'}', key: const Key('nextRoutine')),
        Text(
          '未処理 ${queue.pendingCount}　記録 ${queue.documentationCount}',
          key: const Key('workCounts'),
        ),
        for (final task in approaching.take(2))
          Text(
            '${task.title} ${deadlineState(task, s.timeMinutes) == DeadlineState.overdue ? '期限超過' : 'あと${task.deadline! - s.timeMinutes}分'}',
            key: Key('deadline-${task.taskId}'),
            style: const TextStyle(color: QuestColors.danger),
          ),
      ],
    );
  }

  Widget _workTaskPanel(GameState s) {
    final queue = s.workQueue!;
    final available = availableTasks(
      queue,
      s.timeMinutes,
      strictDependencies: s.unifiedShift?.consequencesEnabled ?? false,
    );
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('いま処理できる業務', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final task in available.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: OutlinedButton(
                key: Key('work-${task.taskId}'),
                onPressed: () =>
                    widget.controller.completeWorkTask(task.taskId),
                child: Text('${task.title}　${task.estimatedMinutes}分'),
              ),
            ),
          if (available.isEmpty) const Text('今すぐ処理できる業務はありません'),
          TextButton(
            key: const Key('workLater'),
            onPressed: () => widget.controller.advanceWorkClock(5),
            child: const Text('あとでやる（5分進める）'),
          ),
        ],
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
    final day =
        record.daySummary ??
        (live && widget.controller.state?.unifiedShift != null
            ? DaySummary.fromState(widget.controller.state!)
            : null);
    final exitLabel = switch (result.exitType) {
      'cleanExit' => '完全退勤',
      'handedOffExit' => '引き継いで退勤',
      'incompleteRecordExit' => '記録を残して退勤',
      'handedOffAndIncompleteRecordExit' => '全部置いて帰宅',
      _ => null,
    };
    final label = result.reason == 'forcedRelief'
        ? '応援を呼んで勤務終了'
        : result.overtimeMinutes == 0
        ? '定時退勤！'
        : '本日の退勤 ${clockLabel(result.finishTime)}';
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
                    clockLabel(result.finishTime),
                    style: Theme.of(context).textTheme.headlineLarge
                        ?.copyWith(fontSize: 52, color: QuestColors.teal),
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: Theme.of(context).textTheme.headlineSmall),
                  if (exitLabel != null) ...[
                    Text(
                      exitLabel,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(switch (result.exitType) {
                      'cleanExit' => '全部終わらせて帰宅。',
                      'handedOffExit' =>
                        '残り${result.handedOffTaskCount}件を夜勤へ託した。',
                      'incompleteRecordExit' => '身体は帰った。記録は残った。',
                      _ => '仕事は終わっていない。でもあなたの勤務は終わった。',
                    }),
                    Text(
                      '完了 ${result.completedTaskCount}件　引き継ぎ ${result.handedOffTaskCount}件',
                    ),
                    Text(
                      '未記録 ${result.incompleteRecordCount}件　期限超過 ${result.overdueTaskCount}件',
                    ),
                    Text('緊急対応 ${result.urgentResponseCount}件'),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    result.overtimeMinutes == 0
                        ? '残業時間　0分'
                        : '残業時間　${durationLabel(result.overtimeMinutes)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            if (day != null) ...[
              const SizedBox(height: 14),
              Text('今日の勤務', style: Theme.of(context).textTheme.titleLarge),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('担当患者 ${day.patientsStart}人 → ${day.patientsEnd}人'),
                    Text('完了 ${day.completed}件 / 引き継ぎ ${day.handedOff}件'),
                    Text('未記録 ${day.undocumented}件 / 期限超過 ${day.overdue}件'),
                    Text('割り込み ${day.events}件 / 中断 ${day.interruptions}回'),
                    Text(
                      '業務連鎖 ${day.consequenceCount}件 / 再コール ${day.repeatedCallCount}件',
                    ),
                    Text(
                      '取れなかった休憩 ${day.missedBreakMinutes}分 / 休憩中断 ${day.interruptedBreakCount}回',
                    ),
                  ],
                ),
              ),
              Text('今日起きたこと', style: Theme.of(context).textTheme.titleLarge),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in day.eventCounts.entries)
                      Text('${_dynamicKindLabel(entry.key)} ${entry.value}件'),
                    if (day.eventCounts.isEmpty) const Text('記録されたイベントはありません'),
                  ],
                ),
              ),
              Text(
                '今日、帰れなかった主な理由',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (day.eventCounts['admission'] != null)
                      Text('新規入院が${day.eventCounts['admission']}件ありました'),
                    if (day.eventCounts['emergency'] != null)
                      Text('急変対応が${day.eventCounts['emergency']}件ありました'),
                    if (day.events > 0) Text('${day.events}件の割り込みが発生しました'),
                    if (day.interruptions > 0)
                      Text('${day.interruptions}回、仕事を中断しました'),
                    if (day.undocumented > 0)
                      Text('未記録の仕事が${day.undocumented}件残りました'),
                    if (day.documentationOvertime) const Text('記録残業が主な理由です'),
                    if (day.events == 0 &&
                        day.undocumented == 0 &&
                        day.interruptions == 0)
                      const Text('目立った割り込みや未記録はありませんでした'),
                  ],
                ),
              ),
              if (day.majorCascades.isNotEmpty) ...[
                Text('主な業務連鎖', style: Theme.of(context).textTheme.titleLarge),
                _panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final chain in day.majorCascades) Text(chain),
                    ],
                  ),
                ),
              ],
              ExpansionTile(
                title: const Text('一日のタイムライン'),
                children: [
                  for (final item in day.timeline)
                    ListTile(
                      dense: true,
                      leading: Text(clockLabel(item.at)),
                      title: Text(item.title),
                    ),
                ],
              ),
            ],
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
