# SecurityCam

古い Android スマホを防犯カメラにするアプリ。n 分ごとに短い動画クリップを保存します。

## 機能
1. インカメラ/アウトカメラ、画質(SD/HD/FHD/UHD)の選択
2. 起動後、n 分ごとに動画クリップを保存。保存容量が上限を超えたら、古いクリップをファイル単位で削除(別タイミングで撮ったファイルを途中から上書きはしない)
3. 音を出さない: 音声は録音せず、通知も無音チャンネル(シャッター音なし)

## ビルド
- Android Studio で `securitycam/` を開いて Run、または
- GitHub Actions (`Build SecurityCam APK`) の成果物 `app-debug.apk` をスマホに入れる

## 使い方・注意
- 保存先: `Android/data/com.example.securitycam/files/clips/`(アプリ画面にも表示)
- 長時間運用では、設定 → アプリ → SecurityCam で「バッテリー最適化の対象外(制限なし)」にし、充電しっぱなしにしてください
- 録画の合間はカメラを解放します。画面を消しても前面サービスとして動作します
