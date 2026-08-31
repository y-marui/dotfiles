# AI Instructions for CLI Tools

## Commit Timing

ユーザーから明示的に指示された時だけコミットする。作業完了後に自動でコミットしない。

## Concise Command Output

ビルド・テスト・lint・pre-commit など出力が多いコマンドは `run-quiet` でラップして実行する。
エラーがなければ1行サマリーのみを確認し、warning / deprecated / note 行は必要に応じて確認する。
原因の特定に十分な情報が得られない場合は、`run-quiet` を外してフル出力で再実行する。

## Fetch Before Starting Work

git リポジトリでコード変更を伴うタスクに着手する前は、ブランチの保護有無やリポジトリの
push ポリシーに関わらず、常に `git fetch` でリモートの最新状態を取り込んでからにする
（ワーキングツリーを変更しない読み取り専用操作なので dirty な状態でも常時実行できる）。
ローカルが古いベースのままコミットすると、後から origin と diverge して余計なマージ
作業が発生するため（実際に発生した事例あり）。

取り込んだ結果を実際に `git pull` や `git merge` で取り込むかどうかは、ワーキングツリーを
変更する操作なので下記「作業前のブランチ確認」と同様 clean な場合に限る。

## Branch Check Before Starting Work

現在のブランチが `main`/`master` 等のデフォルトブランチで、かつ clean な状態の場合は、
push ポリシー（直接 push の可否）に関わらず、fetch に続けて次の順で進める。作業を
main から隔離すること自体は、直接 push の可否とは別軸のため省略しない（直接 push
可否が変えるのは完了後の統合方法だけで、完了後に PR を挟まずローカルで main へ
merge & push してよいか、PR を経由するかの違いに過ぎない）。

1. `git branch -a` 等で main 以外の既存ローカルブランチの有無を確認し、あればユーザーに
   「そのブランチで作業を続けるか」を尋ねる（勝手に新規ブランチを作らない）
2. 既存ブランチがない、またはユーザーが main 起点を選んだ場合のみ、新規に作業用ブランチ
   （`work/<short-description>` 等）を作成してから編集を始める

既に作業ブランチにチェックアウト済み、または main 以外にいる場合はこの手順（ブランチ
作成の要否確認）の対象外。各プロジェクトの AI_CONTEXT.md/CLAUDE.md が「ブランチ作成
不要」と明記している場合に限りそれに従う（例: dotfiles）。単に直接 push が許可されて
いるだけでは、このスキップの理由にならない。

## Local CI Checks Before Creating a PR or Pushing

PR を作成する前、またはブランチに push する前に、そのプロジェクトの CI 設定
（`.github/workflows/`）を確認し、GitHub Actions と同等の lint・build・test をローカルで
実行する（`run-quiet` でラップする）。CI が失敗してから直す往復コストを防ぐため。

## UI Verification for Mac/iOS Apps

Swift/SwiftUI など Mac/iOS ネイティブアプリの変更を検証する際は、iOS Simulator の
操作ツールやスクリーンショットを使わない。ユーザー自身が実機・シミュレータで確認する。
`swift build` / `swift test` / `xcodebuild` やコンパイル・自動テストでの検証は問題ない。
UI 上の見た目確認が必要な場合は、その旨を伝えてユーザーに確認してもらう。

## Running Commands in the Warp Terminal

Warp ターミナルは `ssh` や `make` などを独自ラッパーで包み、直接呼び出すとエラーになる
ことがある（例: `(eval):1: make: function definition file not found`）。発生した場合は
`command ssh ...` / `command make ...` のように `command` プレフィックスを付けて回避する。
