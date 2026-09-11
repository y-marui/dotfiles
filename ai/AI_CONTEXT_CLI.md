# AI Instructions for CLI Tools

## Commit Timing

ユーザーから明示的に指示された時だけコミットする。作業完了後に自動でコミットしない。

## Concise Command Output

ビルド・テスト・lint・pre-commit など出力が多いコマンドは `run-quiet` でラップして実行する。
`git commit` も、pre-commit フックが走るリポジトリでは全フックの "Passed" 行が大量に出力される
ため対象に含める（`run-quiet git commit -m "..."`）。
エラーがなければ1行サマリーのみを確認し、warning / deprecated / note 行は必要に応じて確認する。
原因の特定に十分な情報が得られない場合は、`run-quiet` を外してフル出力で再実行する。

## Fetch Before Starting Work

git リポジトリでコード変更を伴うタスクに着手する前は、ブランチの保護有無やリポジトリの
push ポリシーに関わらず、常に `git fetch` でリモートの最新状態を取り込んでからにする
（ワーキングツリーを変更しない読み取り専用操作なので dirty な状態でも常時実行できる）。
ローカルが古いベースのままコミットすると、後から origin と diverge して余計なマージ
作業が発生するため（実際に発生した事例あり）。

取り込んだ結果を実際に `git pull` や `git merge` で取り込むかどうかは、ワーキングツリーを
変更する操作なので、clean かつユーザーの変更を壊さないことを確認してから行う。

## Scope-Based PR Requirement

作業ブランチを作成するのは、変更規模が大きく、PR に出してレビューを受ける必要がある場合に限る。
それ以外は現在のブランチで作業し、clean な `main` にいることだけを理由にブランチを作成しない。

- **現在のブランチで進めてよい**: memory/コンテキストの移管、Brewfile 等の依存関係定義
  ファイルの追従的な更新、typo 修正等の小さな変更、既存ドキュメント・skill の軽微な更新
- **PR 経由にする**: 新規スクリプトの追加、新規 skill の追加や既存 skill の大規模改修、
  プロジェクトの全体構造（AI コンテキスト階層等）に関わる refactoring

ユーザーから commit を指示され、既読のプロジェクト指示に明示的な禁止がない場合は、
現在のブランチで通常どおり commit を試みる。pre-commit 等のフックが commit を拒否したら
回避せずに理由を確認し、その時点で作業ブランチへの移動等を判断する。

変更規模が大きいか判断に迷う場合はユーザーに確認する。プロジェクトの
AI_CONTEXT.md/CLAUDE.md がこの既定と異なる基準を明記している場合はそちらに従う。

## Local CI Checks Before Creating a PR or Pushing

PR を作成する前、またはブランチに push する前に、そのプロジェクトの CI 設定
（`.github/workflows/`）を確認し、GitHub Actions と同等の lint・build・test をローカルで
実行する（`run-quiet` でラップする）。CI が失敗してから直す往復コストを防ぐため。

## UI Verification for Mac/iOS Apps

Swift/SwiftUI など Mac/iOS ネイティブアプリの変更を検証する際は、iOS Simulator の
操作ツールやスクリーンショットを使わない。ユーザー自身が実機・シミュレータで確認する。
`swift build` / `swift test` / `xcodebuild` やコンパイル・自動テストでの検証は問題ない。
UI 上の見た目確認が必要な場合は、その旨を伝えてユーザーに確認してもらう。

Alfred Workflow（`.alfredworkflow`）など、ダブルクリックで開く形式のネイティブ
macOS 成果物も同様に、実際の見た目・動作確認はユーザー自身が Alfred 上で行う。
ただし成果物をビルドした後、`open <file>.alfredworkflow` で OS 標準のインポート
ダイアログを開くところまでは行ってよい（Finder でのダブルクリックと同義の操作で、
検証行為そのものではないため）。オープンな PR 上で反復開発している場合、ユーザー
からの具体的なフィードバックは新しいブランチを作らず同じ PR に追いコミットし、
再ビルド → `open` → 再確認のループを回す。PR 本文も直近の変更点を反映するよう
都度更新する。

## Language for Self-Executed Issues

GitHub Issue の本文言語は、その Issue の残作業を誰が実行するかで決める。
他のコントリビューターや一般ユーザー向けの作業、あるいは一般的なプロジェクト
文書として書く場合は、そのリポジトリが定める言語ポリシー（`y-marui/*` は
原則英語）に従う。一方、実質的にユーザー自身が後で手を動かす TODO リスト
（手動セットアップ手順、実機での検証、本人しか判断できない意思決定など）で
あれば、リポジトリの言語ポリシーに関わらず本文は日本語で書く（タイトルは
どちらでもよい）。自分用のチェックリストは日本語の方が速く読めるため。

## Closed Issues: Don't Write Problem Content There

クローズ済みの GitHub Issue に、新しい問題点・調査結果・進捗を直接コメントとして
書き込まない。話題が元の Issue と近く見える場合も同様（実例: あるリポジトリで、
Issue が PR マージ直後にクローズされた後も、関連する別の不具合が見つかるたびに
そのクローズ済み Issue へ書き込み続けてしまった）。

内容を書く先は新規 Issue とする。クローズ済みの Issue 側には、必要であれば
その新規 Issue へのリンクのみを残す（内容は書かない）。この方針はリポジトリを
問わず適用する。

## Running Commands in the Warp Terminal

Warp ターミナルは `ssh` や `make` に加え `diff` 等の一般的なコマンドも独自ラッパーで包み、
直接呼び出すとエラーになることがある（例: `(eval):1: make: function definition file not found`）。
発生した場合は `command ssh ...` / `command make ...` / `command diff ...` のように
`command` プレフィックスを付けて回避する。

## Word Splitting in zsh Loops

zsh は既定で `sh_word_split` が無効なため、bash と異なりクォートなしの変数展開
（`for d in $repos; do ...`）はスペース区切りで単語分割されず、変数全体が1つの
値としてループに渡る（`repos="a b c"` としても `$d` には `"a b c"` がまるごと入り、
ループは1回しか回らない）。複数の値をループで回す場合は、変数を介さず
`for d in a b c; do ...` のようにリテラルを直接書くか、配列
（`repos=(a b c); for d in "${repos[@]}"; do ...`）を使う。
