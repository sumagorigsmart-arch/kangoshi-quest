import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'application/game_controller.dart';
import 'content/content_loader.dart';
import 'ui/quest_app.dart';

Future<GameController> loadGame() async {
  final files = await Future.wait([
    rootBundle.loadString('assets/content/balance_v1.json'),
    rootBundle.loadString('assets/content/titles_v1.json'),
    rootBundle.loadString('assets/content/events_phase3.json'),
  ]);
  return GameController(
    ContentLoader.load(files[0], files[1], files[2]),
    MemoryShiftStore(),
  );
}

void main() => runApp(const KangoshiQuestApp());

class KangoshiQuestApp extends StatefulWidget {
  final GameController? controller;
  const KangoshiQuestApp({super.key, this.controller});

  @override
  State<KangoshiQuestApp> createState() => _KangoshiQuestAppState();
}

class _KangoshiQuestAppState extends State<KangoshiQuestApp> {
  late final Future<GameController> _controller = widget.controller == null
      ? loadGame()
      : Future.value(widget.controller);

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '看護師クエスト',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
    home: FutureBuilder<GameController>(
      future: _controller,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('読み込みに失敗しました: ${snapshot.error}')),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return QuestApp(controller: snapshot.data!);
      },
    ),
  );
}
