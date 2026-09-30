import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/main.dart';

import '../application/game_controller_test.dart' show fixtureController;

void main() {
  testWidgets(
    'task first screen follows the day shift and survives narrow text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = fixtureController();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: KangoshiQuestApp(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('勤務をはじめる'));
      await tester.pumpAndSettle();
      expect(find.text('朝の申し送り'), findsWidgets);
      expect(find.textContaining('未処理'), findsWidgets);
      expect(find.textContaining('記録'), findsWidgets);
      expect(controller.completeWorkTask('morning_handoff'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('午前のケア'), findsOneWidget);
      expect(controller.completeWorkTask('morning_vitals'), isTrue);
      await tester.pumpAndSettle();
      expect(controller.state!.workQueue!.documentationCount, 1);
    controller.advanceWorkClock(145);
    await tester.pumpAndSettle();
    expect(find.text('昼食業務'), findsOneWidget);
    expect(find.textContaining('点滴交換 期限超過'), findsOneWidget);
      controller.advanceWorkClock(90);
      await tester.pumpAndSettle();
      expect(find.text('午後のケア'), findsOneWidget);
      controller.advanceWorkClock(150);
      await tester.pumpAndSettle();
      expect(find.text('午後の申し送り'), findsWidgets);
      controller.advanceWorkClock(20);
      await tester.pumpAndSettle();
      expect(find.text('残務処理'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
