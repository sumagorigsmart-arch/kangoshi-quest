# 看護師クエスト Phase 3

「今日も無事に定時で帰れ。」架空の日勤病棟で、患者・チーム・時間・自分の状態をやりくりする風刺系お仕事RPGです。勤務は8:30開始、定時は17:15です。正式コンテンツは `assets/content/events_phase3.json` の **50イベント**で、1勤務には状態・時間帯・重みに応じた一部だけが現れます。検証専用の `fixture_events.json` は正式件数に含めず、アプリからも読み込みません。

## 起動・テスト

この開発機のFlutter SDKは `C:\tools\flutter` です。プロジェクト直下で実行します。

```powershell
& C:\tools\flutter\bin\flutter.bat pub get
& C:\tools\flutter\bin\flutter.bat run
& C:\tools\flutter\bin\flutter.bat test --no-test-assets test/domain test/content test/application test/ui test/phase3
& C:\tools\flutter\bin\flutter.bat analyze
```

Phase 1は `test/domain` と `test/content`、Phase 2は `test/application` と `test/ui`、Phase 3は `test/phase3` です。OneDrive配下で既存の `build/unit_test_assets` がロックされることがあるため、ファイルを直接読むテストには `--no-test-assets` を使用します。

## validator・simulation・seed再現

```powershell
& C:\tools\flutter\bin\dart.bat run bin/phase3.dart validate
& C:\tools\flutter\bin\dart.bat run bin/phase3.dart simulate 5000 1
& C:\tools\flutter\bin\dart.bat run bin/phase3.dart replay 17 test/phase3/on_time_seed17.json
```

`validate` は既存の `ContentLoader` で必須フィールド、ID重複、enum、条件、weight、3〜4択、outcome、時間、残務操作などを検査し、正式版に追加で50件と30分以内の所要時間を確認します。JSON Schemaは `assets/content/*.schema.json` にあります。`tools/generate_events.py` は正式JSONの編集元です。編集後は `python tools/generate_events.py` で再生成し、validatorを実行します。

`simulate` は第2引数が件数、第3引数が開始seedです。4つの機械的な選択方針を均等に使い、定時・残業・応援終了、方針別件数、到達イベント数、fallback連続回数を出します。これは人間の定時率の推定値ではありません。定時率を直接操作する抽選・救済補正はありません。

`replay` はseedと、`eventInstanceId:choiceId:outcomeId` の配列を含むJSONを受け取り、確定outcomeまで照合します。保存済みのseed 17は、正規の勤務進行と選択だけで17:15、残務0、最終申し送り完了になるQAケースです。Phase 1の旧 `bin/headless.dart` と479分のfixtureは境界検証専用です。

## Phase 3の設計判断

- 22の提示枠で50件のプールから重み付き抽選します。時間帯、状態条件、既出ID、重大イベント制限を使います。同一イベントは1勤務で再発しません。13件は選択後の結果にも重み付き分岐があります。
- 記録・調整・ケアの3系統の残務を保ちます。完了・引継ぎ・休憩・トイレ・自然消耗はPhase 1のpure engineが処理します。候補が尽きた場合は常設fallbackを使い、simulationは連続回数を報告します。
- 結果は選択command時に一度確定し、eventInstanceIdとともにGameStateへ保存します。「次へ」で再抽選しません。
- 17:15に残務0と最終申し送り完了の時だけ定時です。17:16以降の通常終了は残業です。上限に達した未完了勤務は応援終了です。
- 5000勤務の機械方針混合結果は定時764（15.28%）、残業3421（68.42%）、応援終了815（16.30%）。全50件に到達し、fallback連続は0でした。方針別結果は `simulate` で確認できます。選択方針の混合比は任意であり、人間のプレイ結果とは分けて扱います。
- 320dp・文字倍率1.5で長文本文、長い選択肢、長い結果文をスクロール・操作するwidget testを追加しました。

## debug APK

```powershell
& C:\tools\flutter\bin\flutter.bat build apk --debug
```

通常の出力先は `build/app/outputs/flutter-apk/app-debug.apk` です。OneDriveがGradle中間ファイルをロックする場合、同一Git HEADのソースを一時ディレクトリへコピーしてビルドし、HEADを記録して `artifacts/app-debug-phase3-<短縮HEAD>.apk` へコピーします。既存buildやソースを強制削除しません。

## 未実装・実機QA

完成版結果画面、記録帳UI、永続保存、SNS共有、本番共有カードは後続Phaseです。現在の勤務保存は同一プロセス内のメモリのみです。Android実機では、320dp相当と大きな文字、長文スクロール、選択ボタン、戻る・中断確認、画面回転・アプリ再開、長時間プレイの操作感を確認してください。実機確認と人間プレイのバランス計測は未実施です。βテストで定時率と、丁寧・時間優先を選んだ際の残務増加、重大イベントの重み、休憩の取りやすさを再調整します。
