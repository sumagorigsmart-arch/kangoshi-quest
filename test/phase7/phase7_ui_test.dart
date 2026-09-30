import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/application/game_controller.dart';
import 'package:kangoshi_quest/application/shift_summary.dart';
import 'package:kangoshi_quest/main.dart';

import '../application/game_controller_test.dart' show fixtureController;
import '../phase4/result_ui_test.dart' show completedController;

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  test(
    'two completed shifts produce two records and updated analysis',
    () async {
      final controller = fixtureController();
      await controller.history.load();
      for (var run = 0; run < 2; run++) {
        controller.startNew(seed: 42 + run);
        expect(controller.state!.timeMinutes, 510);
        expect(controller.state!.turnCount, 0);
        for (final choice in ['focused', 'quick', 'quick', 'short']) {
          expect(
            controller.select(controller.state!.eventInstanceId!, choice),
            isTrue,
          );
          expect(controller.next(), isTrue);
        }
        await controller.lastArchive;
        expect(controller.state!.phase, 'completed');
      }
      expect(controller.history.records, hasLength(2));
      expect(ShiftSummary.fromRecords(controller.history.records).total, 2);
    },
  );

  testWidgets('first home explains goal and time, then first choice is clear', (
    tester,
  ) async {
    await tester.pumpWidget(KangoshiQuestApp(controller: fixtureController()));
    await tester.pumpAndSettle();
    expect(find.text('看護師クエスト'), findsWidgets);
    expect(find.text('今日も無事に定時で帰れ。'), findsOneWidget);
    expect(find.textContaining('1勤務は数分から'), findsOneWidget);
    await tapVisible(tester, find.text('勤務をはじめる'));
    expect(find.text('08:30'), findsOneWidget);
    expect(find.textContaining('定時まであと'), findsOneWidget);
    expect(find.textContaining('残務'), findsWidgets);
    expect(find.textContaining('どう動く？ ひとつ選ぶと進みます'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('choice-focused')));
    expect(find.textContaining('選んだ行動：'), findsOneWidget);
    expect(find.text('経過時間 479分'), findsOneWidget);
  });

  testWidgets('saved shift is the primary home action', (tester) async {
    final store = MemoryShiftStore();
    fixtureController(store).startNew(seed: 42);
    final controller = fixtureController(store);
    await tester.pumpWidget(KangoshiQuestApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('勤務を再開する'), findsOneWidget);
    expect(find.text('勤務をはじめる'), findsNothing);
    await tapVisible(tester, find.text('勤務を再開する'));
    expect(controller.state!.seed, 42);
  });

  testWidgets('result offers replay before secondary details at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = completedController('normal', 0);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: KangoshiQuestApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('退勤時刻'), findsOneWidget);
    expect(find.text('4軸評価'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('もう一度勤務する'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tapVisible(tester, find.text('もう一度勤務する'));
    expect(controller.hasActiveShift, isTrue);
    expect(controller.state!.timeMinutes, 510);
  });
}
