import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/application/game_controller.dart';
import 'package:kangoshi_quest/content/content_loader.dart';
import 'package:kangoshi_quest/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final content = ContentLoader.load(
    File('assets/content/balance_v1.json').readAsStringSync(),
    File('assets/content/titles_v1.json').readAsStringSync(),
    File('assets/content/events_phase3.json').readAsStringSync(),
  );

  testWidgets(
    'patient task screen shows work, schedule and 17:00 backlog at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GameController(content, MemoryShiftStore());
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: KangoshiQuestApp(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('勤務をはじめる'));
      await tester.pumpAndSettle();
      expect(find.text('08:30'), findsOneWidget);
      expect(find.text('朝の申し送り'), findsWidgets);
      expect(find.text('今処理するTask'), findsOneWidget);
      expect(find.text('次の予定業務'), findsOneWidget);
      expect(find.textContaining('301-A'), findsWidgets);
      expect(find.byKey(const Key('unifiedPending')), findsOneWidget);
      controller.advanceWorkClock(510);
      await tester.pumpAndSettle();
      expect(find.textContaining('定時到達'), findsWidgets);
      expect(find.byKey(const Key('unifiedOverdue')), findsOneWidget);
      expect(find.byKey(const Key('unifiedRecords')), findsOneWidget);
      expect(find.byKey(const Key('unifiedUrgent')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'official choice produces Task Queue work, then returns to task selection',
    () {
      final controller = GameController(content, MemoryShiftStore())
        ..startNew(seed: 42);
      for (
        var i = 0;
        i < 100 && controller.state!.phase == 'taskSelection';
        i++
      ) {
        controller.advanceWorkClock(5);
      }
      expect(controller.state!.phase, 'awaitingChoice');
      final eventId = controller.state!.currentEventId!;
      final before = controller.state!.workQueue!.tasks.length;
      expect(
        controller.select(
          controller.state!.eventInstanceId!,
          controller.choices.first.choiceId,
        ),
        isTrue,
      );
      expect(controller.state!.workQueue!.tasks.length, greaterThan(before));
      expect(
        controller.state!.workQueue!.tasks.any(
          (t) => t.sourceEventId == eventId,
        ),
        isTrue,
      );
      expect(controller.next(), isTrue);
      expect(controller.state!.phase, 'taskSelection');
      expect(controller.state!.tasks.total, 0);
    },
  );
}
