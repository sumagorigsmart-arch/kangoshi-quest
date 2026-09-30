# 看護師クエスト Phase 4

「今日も無事に定時で帰れ。」架空の日勤病棟で、患者・チーム・時間・自分の状態をやりくりする風刺系お仕事RPGです。勤務は8:30開始、定時は17:15です。正式コンテンツは `assets/content/events_phase3.json` の **50イベント**で、1勤務には状態・時間帯・重みに応じた一部だけが現れます。検証専用の `fixture_events.json` は正式件数に含めず、アプリからも読み込みません。

## 起動・テスト

この開発機のFlutter SDKは `C:\tools\flutter` です。プロジェクト直下で実行します。

```powershell
& C:\tools\flutter\bin\flutter.bat pub get
& C:\tools\flutter\bin\flutter.bat run
& C:\tools\flutter\bin\flutter.bat test --no-test-assets test/domain test/content test/application test/ui test/phase3 test/phase4
& C:\tools\flutter\bin\flutter.bat analyze
```

Phase 1は `test/domain` と `test/content`、Phase 2は `test/application` と `test/ui`、Phase 3は `test/phase3` です。OneDrive配下で既存の `build/unit_test_assets` がロックされることがあるため、ファイルを直接読むテストには `--no-test-assets` を使用します。

## Phase 8 日勤フローとTask Queue

新規勤務は08:30の朝申し送りから始まり、午前ケア、設定可能な昼食開始時刻（初期値11:30）、休憩可能時間、午後ケア、15:30〜15:50の申し送り、残務処理を経て17:00に定時到達します。時刻と完了状況から勤務フェーズをdomain層で導出します。17:00では勤務を自動終了せず、未処理と記録を確認できます。

`lib/domain/day_shift.dart` に個別Task、Routine / Dynamic / Documentation分類、優先度、期限、ソート、完了時の記録Task生成、点滴交換・検査の代表fixtureを置いています。Routine Taskは勤務開始時に生成し、画面では今処理できる仕事を中心に表示します。「あとでやる」は5分進め、TaskはQueueに残します。旧イベントの選択・結果・4軸評価は維持し、4状態ゲージは補助表示へ移しました。旧イベント残務の集計と個別Task QueueはPhase 8では別管理です。

進行中勤務の保存エンベロープはschemaVersion 2です。GameState内の既存schemaVersion 1と既存キーを保ち、`workQueue`と導出した`shiftPhase`を追加しました。旧schemaVersion 1の勤務はそのまま読み込め、次の保存時にエンベロープを2へ更新します。旧勤務は従来のイベント進行として続行し、新規勤務にRoutine Taskを生成します。勤務履歴の保存形式は変更していません。

日勤フローをheadlessで確認するには `dart run bin/day_shift.dart` を実行します。08:30開始、15:30の申し送り、17:00到達を検証し、残った未処理・記録件数をJSONで出力します。

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

実機確認と人間プレイのバランス計測は未実施です。βテストで定時率と、丁寧・時間優先を選んだ際の残務増加、重大イベントの重み、休憩の取りやすさを再調整します。
## Phase 4 追補

勤務終了で定時・残業・応援終了を大きく表示します。勤務時刻、残業、既存domainの4軸評価（患者対応・チーム・自分の健康・安全）の数値と段階、本日の称号、イベント・行動・休憩・残務を表示します。称号は既存の13件を既存domainの条件と優先順位で判定します。結果からホームへ戻るか、新しいseedで再勤務できます。ホームの「記録帳」は新しい順で、保存済み記録から詳細を開きます。記録0件表示もあります。

### ローカル保存とschema

shared_preferencesの非同期APIを使い、ShiftHistory repositoryを境界としてJSONの記録一覧を端末内に保存します。少量の完成勤務を扱うMVPでは導入が軽く、テスト用storeへ差し替えられるため採用しました。外側と各記録にschemaVersion: 1を持たせています。記録IDはrun IDで、保存処理を直列化し、同一IDの重複を防ぎます。記録には開始・終了日時、seed、content/balance version、終了種別、時刻と残業、4軸、称号、イベント数、選択履歴、休憩と残務を含む結果スナップショットが入ります。将来の変更時はversionごとに明示的なmigrationを追加します。

空・欠損・decode不能・未知version・重複IDは異常として記録帳に表示します。元データは上書きせず、ゲームは開始できます。この状態では新しい記録の保存を止め、破損データの誤消去を避けます。保存失敗も結果画面へ表示します。履歴自体のバックアップや修復UIは後続Phaseです。端末設定からアプリデータを消すと履歴も消えます。

Phase 4時点では進行中勤務は同一プロセス内のメモリ保持のみでした。Phase 5で永続化を追加しています。

### Phase 3バランスbaselineとPhase 4回帰

simulate 5000 1、4方針を各1250勤務。Phase 3 baselineは定時764件（15.28%）、残業3421件（68.42%）、応援終了815件（16.30%）。分担中心の定時746/1250、丁寧中心0/1250、時間優先中心0/1250。Phase 4でも全数値が完全一致しました。これは機械方針の結果で、人間の定時率ではありません。定時再現seedは17です。Phase 4ではイベントとバランスを変更していません。

### Phase 4テストとAPK

Phase 4はtest/phase4です。上記テストコマンドに追加済みです。通常のdebug APK出力先はbuild/app/outputs/flutter-apk/app-debug.apkです。OneDriveがGradle中間ファイルをロックする場合、同一Git HEADのソースを安全な一時ディレクトリへコピーし、ビルドしたHEADとSHA-256を記録します。

### 後続Phaseと実機QA

クラウド同期、アカウント、オンラインランキング、課金、広告、外部analytics SDK、破損履歴の修復・書き出しは未実装です。

Android実機は未確認です。結果画面と長文スクロール、320dp相当、Android文字サイズ変更、記録帳、アプリ終了→再起動→履歴保持、複数勤務の新着順、戻る、中断、連打、画面回転、長時間プレイを確認してください。

## Phase 4.5 Web版

スマートフォンChromeの縦画面（320〜430dp相当）を主対象に、既存のゲームをWebで起動できます。通常のFlutter Web buildを使用します。結果確定済みの勤務記録は従来の `ShiftHistory` / `shared_preferences` により、WebではブラウザのlocalStorageへ保存されます。同じURL・同じブラウザで再読み込みしても記録帳に残ります。シークレットモードやブラウザデータ削除では失われる場合があります。進行中勤務もPhase 5から復元します。

```powershell
& C:\tools\flutter\bin\flutter.bat run -d chrome
& C:\tools\flutter\bin\flutter.bat build web --release
```

OneDrive配下で `build/flutter_assets` が同期や別のFlutterプロセスにロックされると、`flutter run -d chrome` が中間ディレクトリを更新できない場合があります。起動中のFlutterを終了して再試行してください。解消しない場合は、ソースをOneDrive外の作業ディレクトリへコピーして `flutter pub get` から実行できます。

公開URLがない場合、PCとスマートフォンを同じWi-Fiへ接続し、プロジェクト直下で以下を起動します。

```powershell
& C:\tools\flutter\bin\flutter.bat run -d web-server --web-hostname 0.0.0.0 --web-port 8080
```

PCのLAN IPv4アドレスを `ipconfig` で確認し、スマートフォンChromeで `http://PCのIPアドレス:8080` を開きます。Windows Firewallが8080番への接続を遮断する場合は、プライベートネットワーク上の受信を許可してください。

Web公開用の成果物は `build/web` です。320/390/430dpと文字倍率1.5の画面回帰は `test/phase45` にあります。

GitHub Pages向けの設定は `.github/workflows/deploy-web.yml` にあります。`main` push後に同workflowが `build/web` を公開します。プロジェクトPagesのサブパスはリポジトリ名から設定します。公開URLは https://sumagorigsmart-arch.github.io/kangoshi-quest/ です。

## Phase 5: 続き・ふりかえり・共有

進行中勤務を `shared_preferences` の `active_shift_v1` に GameState 全体と表示中の行動結果差分、開始時刻を JSON 保存します。選択前と行動結果表示中のどちらからでも「勤務のつづき」で復帰できます。GameState には seed、rngState、eventInstanceId、確定 outcome、choiceHistory、UI phase が含まれるため、再読み込み時に抽選をやり直しません。保存データの schema/content/balance version と必須状態を検証します。

更新前の正常なスナップショットを `active_shift_v1_backup` に1世代残します。主データが破損した場合はバックアップを表示し、明示的な「バックアップから復元」で復旧できます。破損した主データは自動で上書きせず、明示復元時も別キーへ退避します。復元できない場合はプレイを止め、記録削除を利用できます。保存失敗時も追加の保存を止め、元データを誤って上書きしません。

勤務完了時は確定状態の保存完了を待ち、既存 schema 1 の勤務履歴へ勤務IDで一度だけ登録し、進行中データを消します。途中停止で完了状態が残った場合、次回起動時に同じ手順を再試行します。累計は重複IDのない履歴から計算するため、別の累計カウンタへ二重加算しません。記録帳の詳細から結果のテキスト共有と画像カード共有ができます。Web Share API が利用可能なら共有し、テキストはコピー、PNGはダウンロードへフォールバックします。共有のキャンセルは記録に影響しません。

ホームの「勤務のふりかえり」に総勤務・定時回数と率・総/平均残業・応援終了・4軸平均・獲得称号と回数を端末内だけで表示します。ホームの「すべての記録を削除」は確認後に進行中勤務と履歴を消し、派生する累計・分析も初期状態へ戻します。外部サーバー、ログイン、ランキング、Analytics SDK は使いません。

## Phase 7 β版

ホームに短い遊び方と所要時間の目安を置き、勤務中は選択操作と定時後の残務を明示します。行動結果には選んだ行動を添え、結果画面では評価と称号の直後に再勤務ボタンを置きます。共有画像プレビューは狭い画面に合わせ、長い称号を省略しません。

「感想・不具合を送る」は現時点で一般ユーザー向けの安全な送信先を確定できないため、画面には追加していません。今後、管理できる専用フォームまたは連絡先を用意し、個人情報の扱いを明示してから導線を追加します。GitHub Issues を一般ユーザー向けの送信先にはしません。
