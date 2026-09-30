import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/application/game_controller.dart';
import 'package:kangoshi_quest/application/shift_history.dart';
import 'package:kangoshi_quest/domain/models.dart';
import 'package:kangoshi_quest/main.dart';

import '../application/game_controller_test.dart' show fixtureController;
import 'shift_history_test.dart' show record, result;

GameController completedController(String reason, int overtime) {
  final store = MemoryShiftStore();
  final r = result(reason: reason, overtime: overtime);
  store.save(
    GameState.initial(
      'completed-$reason-$overtime',
      17,
      'test',
      'test',
    ).copyWith(phase: 'completed', timeMinutes: r.finishTime, result: r),
    null,
  );
  return fixtureController(store);
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in [
    ('normal', 0, '定時退勤！'),
    ('normal', 52, '本日の退勤 18:07'),
    ('forcedRelief', 70, '応援を呼んで勤務終了'),
  ]) {
    testWidgets('${kind.$3} is displayed from domain result', (tester) async {
      final c = completedController(kind.$1, kind.$2);
      await tester.pumpWidget(KangoshiQuestApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text(kind.$3), findsOneWidget);
      expect(find.text('4軸評価'), findsOneWidget);
      expect(find.text('本日の称号'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('もう一度勤務する'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tap(tester, find.text('もう一度勤務する'));
      expect(c.hasActiveShift, isTrue);
      expect(c.state!.seed, isNot(17));
    });
  }

  testWidgets('history empty state, list, detail, axes, back and replay', (
    tester,
  ) async {
    final c = fixtureController();
    final history = c.history;
    await history.load();
    await tester.pumpWidget(KangoshiQuestApp(controller: c));
    await tester.pumpAndSettle();
    await tap(tester, find.text('記録帳'));
    expect(find.text('まだ勤務記録がありません'), findsOneWidget);
    await tap(tester, find.byTooltip('戻る'));
    await history.add(record('a', 2000));
    await tap(tester, find.text('記録帳'));
    expect(find.textContaining('今日もなんとか生還した者'), findsOneWidget);
    await tap(tester, find.byType(ListTile).first);
    expect(find.text('4軸評価'), findsOneWidget);
    expect(find.text('本日の称号'), findsOneWidget);
    expect(find.text('患者対応'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.textContaining('今日もなんとか生還した者'), findsOneWidget);
  });

  testWidgets('320dp and text scale 1.5 scroll long title without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixtureController();
    await c.history.load();
    final old = record('long', 2000);
    await c.history.add(
      ShiftRecord(
        id: old.id,
        contentVersion: old.contentVersion,
        balanceVersion: old.balanceVersion,
        title: 'とても長い称号名を持つ今日の勤務の記録' * 5,
        seed: old.seed,
        startedAtMillis: old.startedAtMillis,
        endedAtMillis: old.endedAtMillis,
        startMinutes: old.startMinutes,
        eventCount: old.eventCount,
        result: old.result,
        choices: old.choices,
      ),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: KangoshiQuestApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.text('記録帳'));
    await tap(tester, find.byType(ListTile).first);
    await tester.scrollUntilVisible(
      find.text('安全'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('安全'), findsOneWidget);

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
      child: KangoshiQuestApp(
        key: const ValueKey('completed-result'),
        controller: completedController('forcedRelief', 70),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('応援を呼んで勤務終了'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('安全'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(tester.takeException(), isNull);
  });
}
