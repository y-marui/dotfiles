# AI Instructions for CLI Tools

## Scope

`AI_CONTEXT.md` を先に読み、このファイルはその補完として適用する。矛盾時は共通規約を優先する。
コマンド出力・シェルの規約は、プロジェクトレスの調査や個人ファイル操作を含む
すべてのターミナル操作に適用する。fetch・PR・CI の規約は Git リポジトリ内の
変更作業に適用し、Issue の規約は該当する課題管理操作に適用する。

## Commit and Push Authorization

ユーザーから明示的に指示された時だけコミットする。作業完了後に自動でコミットしない。
commit と push は別の操作として扱い、commit の依頼だけでは push しない。
「push して」「PR を作成して」など、リモートへの反映を含む依頼がある場合に push する。

## Concise Command Output

ビルド・テスト・lint・pre-commit など出力が多いコマンドは、利用可能なら `run-quiet` で
ラップする。未導入の場合、親シェルの関数に依存する場合、詳細ログや進捗表示が必要な場合は
直接実行してよい。終了コードと、表示された警告・エラーを確認する。
`run-quiet` は成功時の通常出力を保存せず、警告の抜粋もすべての書式を拾うとは限らない。
詳細確認が必要な処理は初回からログを残す。再実行が安全な検証コマンドに限り、
診断情報が不足したら直接実行で再確認する。
commit・push など副作用のある操作は出力確認だけを目的に再実行しない。
特にシェル関数の Git ガードに依存する場合、外部スクリプトの `run-quiet` を通さず実行する。
どの実行経路でもフック回避禁止は維持する。

## Fetch Before Starting Work

git リポジトリでコード変更を伴うタスクに着手する前は、ブランチの保護有無やリポジトリの
push ポリシーに関わらず、常に `git fetch` でリモートの最新状態を取り込んでからにする
（ワーキングツリーを変更しない読み取り専用操作なので dirty な状態でも常時実行できる）。
ローカルが古いベースのままコミットすると、後から origin と diverge して余計なマージ
作業が発生するため（実際に発生した事例あり）。

取り込んだ結果を実際に `git pull` や `git merge` で取り込むかどうかは、ワーキングツリーを
変更する操作なので、clean かつユーザーの変更を壊さないことを確認してから行う。

## Scope-Based PR Requirement

作業ブランチを作成するのは、変更規模・影響・復旧の難しさから PR レビューが必要な場合とする。
それ以外は現在のブランチで作業し、clean な `main` にいることだけを理由にブランチを作成しない。

- **現在のブランチで進めてよい**: memory/コンテキストの移管、Brewfile 等の依存関係定義
  ファイルの追従的な更新、typo 修正等の小さな変更、既存ドキュメント・skill の軽微な更新
- **PR 経由にする**: 新規スクリプトの追加、新規 skill の追加や既存 skill の大規模改修、
  プロジェクトの全体構造（AI コンテキスト階層等）に関わる refactoring。
  認証・データ削除・公開 API 等、変更量が小さくても影響が大きい、または復旧が難しい変更

ユーザーから commit を指示され、既読のプロジェクト指示に明示的な禁止がない場合は、
現在のブランチで通常どおり commit を試みる。pre-commit 等のフックが commit を拒否したら
回避せずに理由を確認し、その時点で作業ブランチへの移動等を判断する。

規模・影響・復旧の難しさを確認しても判断できない場合はユーザーに確認する。プロジェクトの
AI_CONTEXT.md/CLAUDE.md がこの既定と異なる基準を明記している場合はそちらに従う。

## Local CI Checks Before Creating a PR or Pushing

PR を作成する前、またはブランチに push する前に、そのプロジェクトの CI 設定
（`.github/workflows/`）を確認し、変更に関連する lint・build・test をローカルで実行する。
文書だけの変更は文書 lint・リンク検査等、コード変更は影響する build・test を対象とする。
リポジトリ固有の必須チェックは優先する。実行できない検証は理由と未確認範囲を報告する。

## UI Verification for Mac/iOS Apps

Mac/iOS ネイティブアプリや Alfred Workflow の UI 検証はユーザーが行う。
該当する開発時に、[環境別手順](references/cli-environments.md#native-app-verification) を読む。

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

Warp でラッパー由来のコマンド実行エラーが起きた場合は、
[環境別手順](references/cli-environments.md#warp-command-wrappers) を読む。

## Word Splitting in zsh Loops

zsh で複数値を反復する場合は文字列の暗黙分割に頼らず、配列かリテラルを使う。
具体例が必要な場合は、[環境別手順](references/cli-environments.md#zsh-word-splitting) を読む。

## Overwriting Files in zsh

この環境の zsh は `noclobber` が有効で、`cat > file` や `echo > file` は既存ファイルの
上書きに失敗する。既存ファイルの更新は Write/Edit ツールで行い、シェルでは
`>|` を使う。失敗した heredoc 書き込みは、その後の処理が古い内容のまま
進みやすいため、書き込み後に内容を確認する。

## Interactive Prompts and Auto-ls in zsh

この環境の zsh には、Bash ツールの出力に影響する挙動が 2 つある。

- `cd` は、移動後に自動で `ls` を実行する（`dotfiles/shell/zshrc` の関数）。`cd` を含むコマンドの
  出力にディレクトリの一覧が混ざり、`grep` などの結果を読み違えやすい。ディレクトリを変えずに
  済む場合は `git -C <dir>` や絶対パスを使う
- `rm` は確認を求めることがあり（`remove <file>?`）、確認待ちのまま停止して、後続のコマンドを
  含む処理全体が止まる。非対話で削除する場合は、対象を確認したうえで `rm -f` を使う

## Reference Resolution

環境別手順は必要な節だけ読む。このファイルがシンボリックリンク経由の場合は、
リンクの実体である `AI_CONTEXT_CLI.md` のディレクトリを基準に `references/` を解決する。
参照先を読めない場合は、その制約を報告し、未確認の手順を推測して実行しない。
