import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/main.dart';

import '../application/game_controller_test.dart' show fixtureController;
import '../phase4/result_ui_test.dart' show completedController;
import '../phase4/shift_history_test.dart' show record;

Future<void> visibleTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets('${width.toInt()}dp mobile flow at textScale 1.5', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = fixtureController();
      await controller.history.load();
      await controller.history.add(record('older', 1000));
      await controller.history.add(record('newer', 2000));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: KangoshiQuestApp(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await visibleTap(tester, find.text('勤務をはじめる'));
      final choices = find.byKey(const Key('gameScroll'));
      expect(choices, findsOneWidget);
      final firstChoice = find.byKey(
        Key('choice-${controller.choices.first.choiceId}'),
      );
      await tester.scrollUntilVisible(
        firstChoice,
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await visibleTap(tester, firstChoice);
      await visibleTap(tester, find.byKey(const Key('next')));

      await visibleTap(tester, find.byTooltip('戻る'));
      await visibleTap(tester, find.text('勤務を中断してホームへ戻る'));
      await visibleTap(tester, find.text('記録帳'));
      expect(find.byType(ListTile), findsNWidgets(2));
      final history = controller.history.records;
      expect(history.map((r) => r.id), ['newer', 'older']);
      await visibleTap(tester, find.byType(ListTile).first);
      expect(find.byKey(const Key('detailScroll')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('安全'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: KangoshiQuestApp(
            key: ValueKey('result-$width'),
            controller: completedController('forcedRelief', 70),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('resultScroll')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('ホームへ戻る'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
