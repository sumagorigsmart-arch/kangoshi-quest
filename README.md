# 看護師クエスト Phase 2

架空の日勤病棟のお仕事RPG。コピーは「今日も無事に定時で帰れ。」。仕様の正本は一階層上の `kangoshi-quest-mvp-v1.md`。Phase 1 の domain/content に Phase 2 の操作画面を重ねています。

## 環境と起動

- 採用: Flutter stable 3.47.4、Dart 3.13.3。Windows上で作成。Android先行。
- SDKはこの開発機では `C:\tools\flutter` にあります。PATHにない場合は下記をフルパスで実行します。

```powershell
& C:\tools\flutter\bin\flutter.bat pub get
& C:\tools\flutter\bin\flutter.bat run
& C:\tools\flutter\bin\flutter.bat analyze
& C:\tools\flutter\bin\flutter.bat test --no-test-assets test/domain test/content test/application test/ui
& C:\tools\flutter\bin\flutter.bat build apk --debug
```

Androidの仮開発用applicationIdは `dev.kangoshiquest.kangoshi_quest`。正式ID、署名、Git remoteは未指定です。公開前に所有者が確定してください。外部アカウントやリポジトリは作成していません。

debug APK は通常 `build/app/outputs/flutter-apk/app-debug.apk` に出力されます。Phase 2 最終版は OneDrive が既存の Gradle 中間ファイルをロックしたため、一時ディレクトリの同一ソースからビルドし、`artifacts/app-debug-phase2.apk` にコピーしました。正式署名と公開設定はありません。

## Phase 2 の画面と操作

- ホーム: 勤務開始、進行中勤務の再開、遊び方。新規開始で進行中の勤務を置き換える場合は確認します。
- 遊び方: 架空の日勤病棟の説明、競合する状態、読む間はゲーム内時間が止まることを表示します。
- ゲーム: 時刻・定時・残り時間、2×2の4ゲージ、残務内訳、コール数、イベント本文、選択肢を縦スクロールで表示します。
- 行動結果: 確定結果文と行動前後の実測差分を同じ画面に表示し、「次へ」でのみ進みます。
- 終業処理カード: domain が提示する記録・調整・ケア、合意引継ぎ相談、最終申し送りを選べます。終了時は簡易表示です。

ゲーム中に戻ると中断確認を表示します。ホームへ戻っても同一アプリ起動中は「勤務のつづき」で再開できます。

## controller と保存

`lib/application/game_controller.dart` の `GameController` が domain command を発行し、返された `GameState` をそのまま公開します。時刻・ゲージ・タスク・乱数の更新は domain に委ねています。結果の差分は選択前後の状態から表示専用の `OutcomeView` に記録します。二重選択と「次へ」の重複を phase と eventInstanceId で拒否します。

`ShiftStore` は保存インターフェース、`MemoryShiftStore` はメモリ実装です。状態と行動結果の表示用差分を遷移ごとに保存しますが、アプリプロセス終了時には消えます。実ファイル保存や保存プラグインは Phase 2 では扱いません。

## headless再現

プロジェクト直下で実行します。第1引数がseed、第2引数がカンマ区切りの選択IDです。引数なしは定時例です。

```powershell
& C:\tools\flutter\bin\dart.bat run bin/headless.dart
& C:\tools\flutter\bin\dart.bat run bin/headless.dart 42 focused,quick,slow,short
& C:\tools\flutter\bin\dart.bat run bin/headless.dart 42 overrun
```

- `focused,quick,quick,short`: 17:15通常退勤。
- `focused,quick,slow,short`: 17:21通常退勤、6分残業。
- `overrun`: 20:30途中上限、応援終了。通常の枝効果は不適用。

fixtureの朝の479分行動は、22枠の飛越や退勤境界を少数イベントで再現するための検証専用データです。正式な遊びのテンポを表すものではありません。

## 構造

- `lib/domain/models.dart`: 不変状態、イベント・効果・評価・設定のモデル、JSON往復。
- `lib/domain/engine.dart`: command + state → transition。時刻、抽選、消耗、残務、退勤、称号。FlutterとI/Oに依存しません。
- `lib/content/content_loader.dart`: JSONの厳格検証。失敗時はファイル種別、JSONパス、eventIdを返します。呼び出し側が読み込んだ文字列を渡します。
- `lib/application/game_controller.dart`: domain と画面の橋渡し、メモリ保存。
- `lib/ui/quest_app.dart`: ホーム、遊び方、ゲーム、行動結果、終業処理。
- `assets/content/*.schema.json`: イベント、調整値、称号の機械可読JSON Schema。複数フィールド間の制約、一意性、最低処理時間はローダーで追加検証します。
- `assets/content/balance_v1.json`、`titles_v1.json`、`fixture_events.json`: 調整値、称号、3件の検証イベント。
- `bin/headless.dart`: 固定seed・選択列の再現。
- `test/domain`、`test/content`: ゲーム規則と不正JSONのテスト。
- `test/application`、`test/ui`: 二重操作、保存、戻る確認、通し操作、320dp・文字拡大。

## 判断と未検証

- 17:00は最後の提示枠です。16:52から進むと17:00のイベントを提示し、その選択が終わって終業処理へ入ります。行動そのものが17:00に達した場合はその枠を通過したものとして終業処理へ入れます。
- 17:15前に申し送りを終えた待機時間にも自然消耗を適用します。仕様の「全経過分」に従うためです。
- `reviewNote`は開発用メモとして検証時に許可しますが、モデルとゲーム状態には保持しません。画面には出しません。
- fixtureのみで正式50イベント、実プレイ時間、定時率15〜20%は検証できません。Phase 3のデータ投入後に計測が必要です。
- Android cmdline-tools は公式配布 ZIP の SHA-256 を照合して SDK に追加済みです。debug APK はビルド済みです。`flutter doctor` は未受諾の Android ライセンスを報告します。Android実機での文字拡大・操作感、iOS、正式署名は未検証です。
- このOneDrive配下ではFlutterが既存の `build/unit_test_assets` を削除できない場合があります。対象テストはファイルを直接読むため、`--no-test-assets` で実行できます。
- fixture の 479 分行動は勤務境界テスト専用です。通常のテンポや完成コンテンツではありません。
- Phase 3 で正式イベントを入れるまでは選択肢の幅や長文を追加コンテンツで再検証してください。完成版結果画面、称号コレクション、共有、累計、永続保存、分析は未実装です。
