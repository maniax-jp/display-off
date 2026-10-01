# DisplayOff

Mac メニューバーアプリ。ディスプレイを **スリープさせず** に消灯するため、スクリーンロックが
かからず、Claude アプリ等の画面操作が継続できます。Thunderbolt 接続ディスプレイ(既定で外部ディスプレイのみ)対象。

## 仕組み
既定(Power off via DDC + virtual display):
- 仮想ディスプレイ(CGVirtualDisplay)を作り、macOS と画面キャプチャに画面が残るようにする
- 物理ディスプレイへ DDC/CI の standby(VCP 0xD6=5)を送り、本当に電源を切る(Apple Silicon の IOAVService 経由)
- 復帰はディスプレイ本体の電源ボタン。物理ディスプレイが戻ると自動で仮想ディスプレイを破棄する

代替(メニューでオフにした場合): バックライト輝度 0 + ガンマ全黒の黒表示。
消灯中は IOPMAssertion でアイドルスリープを防止し、ロックを避ける。

## 使い方
```
./build.sh
open DisplayOff.app            # メニューバーの ◻︎ → "Display Off (no lock)"
DisplayOff.app/Contents/MacOS/DisplayOff --off   # 起動と同時に消灯
```
復帰: 電源オフ方式(既定)はモニタ本体の電源ボタンのみ(マウス/キーボードでは復帰しない)。
黒表示方式は実際のマウス/キーボード操作(合成イベントでは復帰しない)かメニューから。
「内蔵ディスプレイを含める」「マウス/キーボードで復帰」は黒表示方式でのみ表示される。
黒表示方式でのキーボード復帰検知には「入力監視」権限が必要な場合があります(マウス操作のみで復帰する場合は不要)。

## 注意
- 非公開API(DisplayServices)を使用。OS更新で動かなくなる可能性あり。
- DDC standby に対応していないモニタでは電源が切れません(その場合は黒表示方式を使用)。
- ディスプレイによっては輝度0でも微発光します。

## リリース
`v*` タグを push すると GitHub Actions (macOS 26 ランナー) がユニバーサルバイナリをビルドし、
`DisplayOff.zip` を Release に添付します(`git tag v0.1.0 && git push origin v0.1.0`)。
対象: macOS Tahoe 26 以降。ad-hoc 署名のため、ダウンロード後は初回のみ
`xattr -cr DisplayOff.app` を実行するか、右クリック→開く で起動してください。
