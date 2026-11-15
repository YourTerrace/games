# 引き継ぎ書: SecurityCam

## 目的
古い Android スマホを防犯カメラにするネイティブアプリ。機能は意図的にシンプル。

## 仕様(ユーザー要望)
1. 画質(SD/HD/FHD/UHD)とカメラ(イン/アウト)を選べる
2. 起動後、n 分ごとに**動画クリップ**を保存。最大使用容量を超えたら古いデータから削除
3. 本体から音を出さない

## 判断・解釈した点
- 「別のタイミングで撮ったものは上書きしない」= 古いクリップを**ファイル単位で丸ごと削除**し、途中から切り詰めない(`ClipStore.trim`)。ユーザーに最終確認は未取得。
- 音声は録音しない(`withAudioEnabled` を呼ばない)。通知は IMPORTANCE_LOW の無音チャンネル。
- n 分は「録画開始から次の録画開始まで」の間隔。録画の合間はカメラを解放する(省電力)。
- 保存先はアプリ専用領域 `Android/data/com.example.securitycam/files/clips/`。ギャラリーには出ない。
- Android のみ(Kotlin / CameraX 1.3.4 / minSdk 24 / targetSdk 34)。iOS は対象外。

## 構成
- `Config.kt`: 設定(SharedPreferences)。サービスは録画ごとに読み直す
- `ClipStore.kt`: 保存先、容量管理
- `RecorderService.kt`: 前面サービス(camera type)。録画ループ
- `MainActivity.kt` / `res/layout/activity_main.xml`: 設定画面と開始/停止

## 現在の状態(重要)
- **未ビルド・未実機確認**。作成環境(クラウド)で Google Maven に届かず、コンパイルすらしていない。コンパイルエラーがありうる。
- Gradle wrapper は未生成。Android Studio で開くか、`gradle wrapper --gradle-version 8.9` で生成する。
- `.github/workflows/build-securitycam.yml` で CI ビルドも可(未実行)。

## 実機で確認してほしいこと
- 画面を消しても録画が続くか
- 録画の合間にカメラが解放されるか
- シャッター音・録画開始/停止音が鳴らないか(機種依存の可能性)
- 容量上限で古いクリップが削除されるか
- 長時間運用でバッテリー最適化により止められないか

## 未実装・候補
- 再起動後の自動起動(BootReceiver)
- 動体検知時のみ録画
- ギャラリー表示 / アプリ内再生 / Wi-Fi 送信
- 録画中の容量チェック(現状は録画前後に trim。1本分の超過はありうる)
