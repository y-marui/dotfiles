# CLI Environment Procedures

`AI_CONTEXT_CLI.md` から、該当する作業時だけ参照する詳細手順。
共通規約の安全制約と commit・push の承認条件は引き続き適用する。

## Native App Verification

Swift/SwiftUI など Mac/iOS ネイティブアプリの変更を検証する際は、iOS Simulator の
操作ツールやスクリーンショットを使わない。ユーザー自身が実機・シミュレータで確認する。
`swift build` / `swift test` / `xcodebuild` やコンパイル・自動テストでの検証は問題ない。
UI 上の見た目確認が必要な場合は、その旨を伝えてユーザーに確認してもらう。

Alfred Workflow（`.alfredworkflow`）など、ダブルクリックで開く形式のネイティブ
macOS 成果物も同様に、実際の見た目・動作確認はユーザー自身が Alfred 上で行う。
成果物をビルドした後、`open <file>.alfredworkflow` で OS 標準のインポート
ダイアログを開くところまでは行ってよい（Finder でのダブルクリックと同義）。
オープンな PR 上で反復開発している場合は同じブランチで修正し、承認済みの範囲で
追いコミット・push と PR 本文更新を行う。再ビルド → `open` → ユーザーの再確認を繰り返す。

## Warp Command Wrappers

Warp ターミナルで `ssh`・`make`・`diff` 等のラッパー由来のエラー
（例: `(eval):1: make: function definition file not found`）が発生した場合は、
`command ssh ...` / `command make ...` / `command diff ...` で回避する。
対象が安全ガードを持つ関数の場合は、その制約を維持できることを確認する。

## Zsh Word Splitting

zsh は既定で `sh_word_split` が無効なため、bash と異なりクォートなしの変数展開
（`for d in $repos; do ...`）はスペース区切りで単語分割されない。
`repos="a b c"` としても、変数全体が1つの値として渡り、ループは1回しか回らない。
複数の値は `for d in a b c; do ...` のようなリテラルか、
配列（`repos=(a b c); for d in "${repos[@]}"; do ...`）を使う。
