import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/application/game_controller.dart';
import 'package:kangoshi_quest/application/shift_history.dart';
import 'package:kangoshi_quest/content/content_loader.dart';
import 'package:kangoshi_quest/ui/quest_app.dart';

import '../phase4/shift_history_test.dart' show record;

void main() {
  testWidgets('long title fits in offline share card', (tester) async {
    final original = record('long', 2000);
    final longRecord = ShiftRecord(
      id: original.id,
      contentVersion: original.contentVersion,
      balanceVersion: original.balanceVersion,
      title: 'とても長い称号' * 35,
      seed: original.seed,
      startedAtMillis: original.startedAtMillis,
      endedAtMillis: original.endedAtMillis,
      startMinutes: original.startMinutes,
      eventCount: original.eventCount,
      result: original.result,
      choices: original.choices,
    );
    final history = ShiftHistory(MemoryHistoryStore());
    await history.load();
    await history.add(longRecord);
    final content = ContentLoader.load(
      File('assets/content/balance_v1.json').readAsStringSync(),
      File('assets/content/titles_v1.json').readAsStringSync(),
      File('assets/content/fixture_events.json').readAsStringSync(),
    );
    final controller = GameController(
      content,
      MemoryShiftStore(),
      history: history,
    );
    await tester.pumpWidget(
      MaterialApp(home: QuestApp(controller: controller)),
    );
    await tester.tap(find.text('記録帳'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('共有画像を作る'),
      350,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('共有画像を作る'));
    await tester.pumpAndSettle();
    expect(find.text('看護師クエスト'), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(tester.takeException(), isNull);
  });
}
