import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/application/game_controller.dart';
import 'package:kangoshi_quest/content/content_loader.dart';
import 'package:kangoshi_quest/domain/models.dart';
import 'package:kangoshi_quest/main.dart';

void main() {
  testWidgets('long official-style copy works at 320dp and 1.5 text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final loaded = ContentLoader.load(
      File('assets/content/balance_v1.json').readAsStringSync(),
      File('assets/content/titles_v1.json').readAsStringSync(),
      File('assets/content/events_phase3.json').readAsStringSync(),
    );
    final source = loaded.events.first;
    final long = '患者への説明を続けながら、別の部屋からのコールと記録の締切が同時に近づいています。';
    final choices = [
      for (final c in source.choices)
        ChoiceDefinition(
          c.choiceId,
          '${c.label}。$long$long',
          '${c.hint}。$long',
          c.actionType,
          [
            for (final o in c.outcomes)
              OutcomeDefinition(
                o.outcomeId,
                '$long$long$long',
                o.weight,
                o.effects,
                o.weightModifiers,
              ),
          ],
        ),
    ];
    final event = EventDefinition(
      eventId: source.eventId,
      title: source.title,
      description: '$long$long$long',
      category: source.category,
      minTime: 510,
      maxTime: 510,
      weight: 1,
      tags: source.tags,
      conditions: const [],
      choices: choices,
    );
    final bundle = ContentBundle(
      loaded.contentVersion,
      loaded.balanceVersion,
      loaded.balance,
      [event],
      loaded.titles,
    );
    final controller = GameController(bundle, MemoryShiftStore());
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: KangoshiQuestApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('勤務をはじめる'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final c in choices) {
      final button = find.byKey(Key('choice-${c.choiceId}'));
      await tester.scrollUntilVisible(
        button,
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    }
    final choice = find.byKey(Key('choice-${choices.last.choiceId}'));
    await tester.scrollUntilVisible(
      choice,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(find.text('$long$long$long'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final next = find.byKey(const Key('next'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
