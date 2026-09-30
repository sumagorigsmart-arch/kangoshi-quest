import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/main.dart';

import '../application/game_controller_test.dart' show fixtureController;

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('rapid taps select and advance only once', (tester) async {
    final c = fixtureController();
    await tester.pumpWidget(KangoshiQuestApp(controller: c));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('勤務をはじめる'));
    final choice = find.byKey(const Key('choice-focused'));
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(c.state!.turnCount, 1);
    expect(c.state!.choiceHistory, hasLength(1));
    expect(find.byKey(const Key('choice-slow')), findsNothing);
    final next = find.byKey(const Key('next'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(c.state!.currentEventId, 'f02');
    expect(c.state!.presentationCount, 2);
  });

  testWidgets('back asks before leaving; resume and new shift confirmation', (
    tester,
  ) async {
    final c = fixtureController();
    await tester.pumpWidget(KangoshiQuestApp(controller: c));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('勤務をはじめる'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('勤務を中断しますか？'), findsOneWidget);
    await tapVisible(tester, find.text('ゲームを続ける'));
    expect(c.state!.phase, 'awaitingChoice');
    await tapVisible(tester, find.byTooltip('戻る'));
    await tapVisible(tester, find.text('勤務を中断してホームへ戻る'));
    expect(find.text('勤務を再開する'), findsOneWidget);
    await tapVisible(tester, find.text('最初からやり直す'));
    expect(find.text('進行中の勤務があります'), findsOneWidget);
    await tapVisible(tester, find.text('キャンセル'));
    await tapVisible(tester, find.text('勤務を再開する'));
    expect(c.state!.timeMinutes, 510);
  });

  testWidgets('fixture plays from home through result and closing to finish', (
    tester,
  ) async {
    final c = fixtureController();
    await tester.pumpWidget(KangoshiQuestApp(controller: c));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('勤務をはじめる'));
    expect(find.text('朝の段取り'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('choice-focused')));
    expect(find.text('行動結果'), findsOneWidget);
    expect(find.text('経過時間 479分'), findsOneWidget);
    expect(find.byKey(const Key('choice-slow')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('next')));
    expect(find.text('夕方の連絡'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('choice-quick')));
    await tapVisible(tester, find.byKey(const Key('next')));
    expect(find.text('最後の確認'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('choice-quick')));
    await tapVisible(tester, find.byKey(const Key('next')));
    expect(find.text('最終申し送り'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('choice-short')));
    await tapVisible(tester, find.byKey(const Key('next')));
    expect(find.byKey(const Key('resultScroll')), findsOneWidget);
    expect(c.state!.result?.reason, 'normal');
  });

  testWidgets(
    '320dp and enlarged text keep choices readable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixtureController();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: KangoshiQuestApp(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('勤務をはじめる'));
      expect(find.textContaining('ゲーム内時刻'), findsOneWidget);
      expect(find.textContaining('定時 17:00'), findsOneWidget);
      expect(find.textContaining('残務 6件'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('累計ナースコール'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('累計ナースコール'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('choice-overrun')),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('大きな作業を始める'), findsOneWidget);
      final scaler = MediaQuery.textScalerOf(
        tester.element(find.text('大きな作業を始める')),
      );
      expect(scaler.scale(14), closeTo(21, 0.01));
    },
  );
}
