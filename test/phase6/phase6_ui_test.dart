import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/main.dart';

import '../application/game_controller_test.dart' show fixtureController;
import '../phase4/shift_history_test.dart' show record;

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('first visit explains the game and uses the start CTA', (
    tester,
  ) async {
    await tester.pumpWidget(KangoshiQuestApp(controller: fixtureController()));
    await tester.pumpAndSettle();
    expect(find.text('今日も無事に定時で帰れ。'), findsOneWidget);
    expect(find.textContaining('お仕事RPG'), findsOneWidget);
    expect(find.text('勤務をはじめる'), findsOneWidget);
  });

  testWidgets('17:15 milestone, outcome changes, result and fresh replay', (
    tester,
  ) async {
    final controller = fixtureController();
    await tester.pumpWidget(KangoshiQuestApp(controller: controller));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('勤務をはじめる'));
    await tapVisible(tester, find.byKey(const Key('choice-focused')));
    expect(find.text('行動結果'), findsOneWidget);
    expect(find.text('経過時間 479分'), findsOneWidget);
    expect(find.textContaining('残タスク'), findsWidgets);
    await tapVisible(tester, find.byKey(const Key('next')));
    await tapVisible(tester, find.byKey(const Key('choice-quick')));
    await tapVisible(tester, find.byKey(const Key('next')));
    await tapVisible(tester, find.byKey(const Key('choice-slow')));
    await tapVisible(tester, find.byKey(const Key('next')));
    expect(find.text('定時です。'), findsOneWidget);
    for (final id in ['short']) {
      await tapVisible(tester, find.byKey(Key('choice-$id')));
      await tapVisible(tester, find.byKey(const Key('next')));
    }
    expect(find.byKey(const Key('resultScroll')), findsOneWidget);
    final previousRun = controller.state!.runId;
    await tester.scrollUntilVisible(
      find.text('もう一度勤務する'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapVisible(tester, find.text('もう一度勤務する'));
    expect(controller.state!.runId, isNot(previousRun));
    expect(controller.state!.timeMinutes, 510);
  });

  testWidgets(
    'history and analysis are readable, deletion needs confirmation',
    (tester) async {
      final controller = fixtureController();
      await controller.history.load();
      await tester.pumpWidget(KangoshiQuestApp(controller: controller));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('記録帳'));
      expect(find.text('まだ勤務記録がありません'), findsOneWidget);
      await tapVisible(tester, find.byTooltip('戻る'));
      await controller.history.add(record('one', 2000));
      await tapVisible(tester, find.text('勤務のふりかえり'));
      expect(find.text('総勤務回数'), findsOneWidget);
      expect(find.text('1回'), findsOneWidget);
      await tapVisible(tester, find.byTooltip('戻る'));
      await tapVisible(tester, find.text('すべての記録を削除'));
      expect(find.text('元に戻せません。', findRichText: true), findsNothing);
      expect(find.textContaining('元に戻せません'), findsOneWidget);
      await tapVisible(tester, find.text('キャンセル'));
      expect(controller.history.records, hasLength(1));
      await tapVisible(tester, find.text('すべての記録を削除'));
      await tapVisible(tester, find.text('削除する'));
      expect(controller.history.records, isEmpty);
    },
  );
}
