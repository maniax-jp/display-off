# DisplayOff

Mac メニューバーアプリ。ディスプレイを **スリープさせず** に消灯するため、スクリーンロックが
かからず、Claude アプリ等の画面操作が継続できます。Thunderbolt 接続ディスプレイ(既定で外部ディスプレイのみ)対象。

## 仕組み
- `DisplayServices` でバックライト輝度を 0 に(Apple Studio Display / LG UltraFine 等)
- ガンマテーブルを全黒に(どのディスプレイでも有効。スクリーンキャプチャには影響しない)
- 消灯中は IOPMAssertion でシステム/ディスプレイのアイドルスリープを防止
- 終了・復帰時に輝度とガンマを元に戻す

## 使い方
```
./build.sh
open DisplayOff.app            # メニューバーの ◻︎ → "Display Off (no lock)"
DisplayOff.app/Contents/MacOS/DisplayOff --off   # 起動と同時に消灯
```
復帰: 実際のマウス/キーボード操作(自動操作の合成イベントでは復帰しない)、またはメニューバーから。
キーボードでの復帰検知には「入力監視」権限が必要な場合があります(マウス操作のみで復帰する場合は不要)。

## 注意
- 非公開API(DisplayServices)を使用。OS更新で動かなくなる可能性あり。
- DDC/CI による真の電源OFFではなく「黒表示+輝度0」です(画面ロックを避けるための設計)。
- ディスプレイによっては輝度0でも微発光します。

## リリース
`v*` タグを push すると GitHub Actions (macOS 26 ランナー) がユニバーサルバイナリをビルドし、
`DisplayOff.zip` を Release に添付します(`git tag v0.1.0 && git push origin v0.1.0`)。
対象: macOS Tahoe 26 以降。ad-hoc 署名のため、ダウンロード後は初回のみ
`xattr -cr DisplayOff.app` を実行するか、右クリック→開く で起動してください。
