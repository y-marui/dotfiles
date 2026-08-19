# AI Instructions for CLI Tools

## コミットのタイミング

ユーザーから明示的に指示された時だけコミットする。作業完了後に自動でコミットしない。

## 作業前のブランチ確認

git リポジトリでコード変更を伴うタスクに着手する前、現在のブランチが `main`/`master` 等の
直接 push が禁止されたブランチで、かつ clean な状態の場合は、次の順で進める。

1. `git fetch`（または `git pull`）でリモートの最新状態を取り込む
2. `git branch -a` 等で main 以外の既存ローカルブランチの有無を確認し、あればユーザーに
   「そのブランチで作業を続けるか」を尋ねる（勝手に新規ブランチを作らない）
3. 既存ブランチがない、またはユーザーが main 起点を選んだ場合のみ、新規に作業用ブランチ
   （`work/<short-description>` 等）を作成してから編集を始める

既に作業ブランチにチェックアウト済み、または main 以外にいる場合はこの手順の対象外。
リポジトリや場所を問わず適用する標準的な安全策。

## PR 作成・push 前のローカル CI チェック

PR を作成する前、またはブランチに push する前に、そのプロジェクトの CI 設定
（`.github/workflows/`）を確認し、GitHub Actions と同等の lint・build・test をローカルで
実行する（`run-quiet` でラップする）。CI が失敗してから直す往復コストを防ぐため。

## Mac/iOS アプリの UI 検証

Swift/SwiftUI など Mac/iOS ネイティブアプリの変更を検証する際は、iOS Simulator の
操作ツールやスクリーンショットを使わない。ユーザー自身が実機・シミュレータで確認する。
`swift build` / `swift test` / `xcodebuild` やコンパイル・自動テストでの検証は問題ない。
UI 上の見た目確認が必要な場合は、その旨を伝えてユーザーに確認してもらう。

## Warp ターミナルでのコマンド実行

Warp ターミナルは `ssh` や `make` などを独自ラッパーで包み、直接呼び出すとエラーになる
ことがある（例: `(eval):1: make: function definition file not found`）。発生した場合は
`command ssh ...` / `command make ...` のように `command` プレフィックスを付けて回避する。
