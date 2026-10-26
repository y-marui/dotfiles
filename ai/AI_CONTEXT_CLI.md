# AI Instructions for CLI and Coding Work

## Scope

`AI_CONTEXT.md` を先に読み、次のいずれかを行う場合にこのファイルを全文読む。
ターミナル・シェルの使用、コードや管理対象ファイルの作成・変更、Git リポジトリや GitHub の Issue・PR・Actions の操作、build・test・lint・依存関係・ツール設定、その他の開発作業。

コマンド出力・シェルの規約は、プロジェクトレスの調査や個人ファイル操作を含むすべてのターミナル操作に適用する。
Git・GitHub・コーディングの規約は該当する作業にだけ適用する。
通常の会話、説明、文章作成、開発に関係しない調査には適用しない。
矛盾時は `AI_CONTEXT.md` を優先する。

## Safety for Coding and Repositories

シークレット・認証情報をコードや管理対象ファイルに書かない。
`git commit`/`push` 等で `--no-verify`（`commit` の `-n` 含む）は使わない。
pre-commit フックのエラーは無視・回避せず原因を修正する。
shell の git wrapper 関数（`dotfiles/shell/zshrc`）でも禁止済みだが、回避され得るため明記する。

## Chat and Work Directory

大規模な開発を含む作業は、1 chat につき 1 作業ディレクトリ（リポジトリ）を原則とする（並列作業や軽微な派生タスクは除く）。
別のリポジトリで大規模な作業が必要になったら、情報を Issue に移して別 chat で進める。

## Commit and Push Authorization

ユーザーから明示的に指示された時だけコミットし、作業完了後に自動でコミットしない。
commit と push は別の操作として扱い、commit の依頼だけでは push しない。
「push して」「PR を作成して」など、リモートへの反映を含む依頼がある場合に push する。

## Session Closeout

`/compact`の前の区切りには`session-handoff`、セッションを終えるには`session-finish`を使う。
どちらも、記録の整理に加えて、区切りのついた作業のcommit・push・PR・mergeまでを呼び出しの承認として行う
（CI緑・レビュー解決済み・自分のPR、のときだけ。満たさなければ止めて報告する）。
`session-finish`は、さらにサブセッションとこのセッションのarchive、`git-sweep --all`、
実機・環境への反映（プロジェクトの Post-merge 宣言）を行う。
どちらもユーザーが明示的に呼び出したときだけ使い、手順と承認範囲はその skill に従う。
プロジェクトで実機反映が要る場合は、`AI_CONTEXT.md`等に Post-merge（コマンド・反映先・条件）を宣言する。

## Core Development Rules

詳細は下表の `dev-workflow.md` を、該当する作業の前に読む。

- 出力が多いコマンドは、利用可能なら `run-quiet` でラップし、終了コードと警告・エラーを確認する。
  副作用のある操作は出力確認だけを目的に再実行しない。
  commit 時の doc-lint 警告は見えないため、Markdown を変更したら commit 前に `doc-lint` を実行して直す
- 開発作業の開始時は、`obsidian-project-home --repo <repository-root>` が使えれば解決し、終了コード `0` の場合だけ読む。
  それ以外は推測・新規作成をせず進める。
  正本はリポジトリの docs と Issue
- コード変更を伴うタスクの前に `git fetch` する。
  `git pull`/`merge` は clean で変更を壊さないと確認してから行う
- 作業ブランチは、PR レビューが必要な規模・影響の場合だけ作る。
  それ以外は現在のブランチで作業し、commit を指示されたらまず試み、フックが拒否したら理由を確認する
- PR 作成前・push 前に `.github/workflows/` を確認し、関連する lint・build・test をローカルで実行する。
  できない検証は理由と未確認範囲を報告する。
  private リポジトリでは、使用OSのrunner変数・登録と、各jobの`runs-on`（再利用workflowの入力を含む）も確認する（手順は `github-rare.md` の `#actions-billing-errors`）
- AI の PR は最初から draft で開き、ローカル検証後に ready にする。
  レビュー対応はまとめて push し、自動レビュー依頼のためだけに ready にしない
- 恒久的な設計・仕様・運用手順は `docs/`・README・AI_CONTEXT に、TODO・進捗・ブロッカーは Issue・Project に記録する。
  公開リポジトリに不要な運用情報（ホスト名、IP、鍵情報、サービス構成）を載せない
- シェルは ShellCheck 準拠で `set -euo pipefail`、Swift は SwiftLint、Python は ruff / black（新規は 3.11 以上）。
  パスは `$HOME`。依存バージョンの更新は、依頼された保守作業か具体的根拠がある場合に限る

## GitHub

PR・Issue の作成前に `.github/` のテンプレートを確認し、あれば従う。
詳細は下表の `github-operations.md` を、該当する作業の前に読む。

- PR・Issue の操作は GitHub MCP を優先し、不可なら `gh` CLI を使う。
  Web UI から直接作成・更新・マージしない。
  `gh` 未認証なら `gh auth login -h github.com` を案内する
- GitHub MCP の `create_pull_request` 等、書き込み系ツールが対話フォームを表示するだけで
  実行されない環境（Claude Code デスクトップアプリの Code タブ等）がある。
  フォームが表示されたが実行結果が返らない・ユーザーから見えないと言われた場合は、
  そのツール呼び出しを繰り返さず `gh` CLI に切り替える
- マージは merge commit を標準とし、squash・rebase は明示された場合のみ
- 関連 issue は PR 本文に `Fixes #123`/`Closes #123`（自動クローズ）か `Refs #123`（関連付けのみ）でリンクする
- コンフリクト解消は rebase でなく merge を使う。
  rebase は明示指示がある場合のみ
- マージ依頼には統合済みブランチの整理を含める。
  PR が MERGED で未 push の未統合コミットがないことを確認してから整理し、満たせなければ残して別に報告する
- `y-marui/*`・`fukami-lab-sot/*` の Issue は assignee に `y-marui` を設定する。
  自分の PR には付けない
- 自動レビューは PR コメントで依頼する（`@codex review`、`@copilot review`）。
  指摘は検証して妥当なものだけ修正し、対応後は却下分も理由を返信して resolve する。
  再レビューは依頼せずマージしてよい
- Issue 本文の言語は残作業の実行者で決める（ユーザー自身の TODO は日本語）
- 前提条件が整うまで延期・凍結する Issue には、`on hold` ラベルを付ける（`y-marui/*` 管理下のリポジトリ共通）。
  ラベルがなければ作成する（色 `C5DEF5`、説明 `Postponed until a precondition is met`）。
  延期の理由と再開の条件は Issue にコメントで残す
- クローズ済み Issue に内容を書き込まない。
  新規 Issue に書き、旧 Issue にはリンクのみ残す
- アカウント対応表は `~/.identity/accounts.yaml`

## Commit Messages

Conventional Commits 形式（`feat:` 新機能、`fix:` バグ修正、`chore:` ビルド・設定、`docs:` ドキュメント、`refactor:` リファクタリング）。

## MCP Configuration Scope

個人の恒常的なツール連携は、各エージェントの user / global scope に登録する。
特定リポジトリだけで使う連携のみ project / local scope に登録する。
登録方法や設定ファイルの所有境界は、各エージェント固有の設定文書に従う。

## zsh Caveats

この環境の zsh は `noclobber` が有効で、`cat > file` は既存ファイルの上書きに失敗する。
既存ファイルの更新は Write/Edit ツールで行い、シェルでは `>|` を使う。
他の挙動は下表の `cli-environments.md` を読む。

## Detail References

使う場面が限られる手順は `references/` に置く。
次の作業の前に、該当する節だけ全文読む。

- Windows の Git Bash 等で、標準入力が空のまま `python -` を実行しない（スクリプトはファイルか `python -c` で渡す）
- 新規リポジトリは public（公開予定がなければ private）で、既存のテンプレートリポジトリから命名規則に従って作る
- 多数のリポジトリへ同じ PR を一括で出す場合、ready 化を一斉に行わず、数個ずつ時間をずらす
- Mac/iOS ネイティブアプリや Alfred Workflow の UI 検証はユーザーが行う
- zsh で複数値を反復する場合は、文字列の暗黙分割に頼らず配列かリテラルを使う

| 作業 | 読む場所 |
| --- | --- |
| Project Home、fetch、PR 要否、draft PR、ドキュメント管理、コーディングスタイル、`run-quiet` | `dev-workflow.md` |
| ブランチ整理、assignee、自動レビュー対応、Issue の言語、クローズ済み Issue、アカウント | `github-operations.md` |
| zsh の `noclobber` | `cli-environments.md` の `#zsh-overwrite-and-noclobber` |
| zsh の `cd`・`rm`・`cp`・`log` の挙動 | `cli-environments.md` の `#zsh-interactive-prompts-and-auto-ls` |
| zsh で複数値を反復する | `cli-environments.md` の `#zsh-word-splitting` |
| ネイティブアプリ・Alfred Workflow の UI 検証 | `cli-environments.md` の `#native-app-verification` |
| iOS Simulator の操作・確認 | `cli-environments.md` の `#ios-simulator-moved-to-device-hub` |
| Warp のラッパー由来のコマンド実行エラー | `cli-environments.md` の `#warp-command-wrappers` |
| Windows（Git Bash）・WSL・Windows ホストへの ssh | `windows-wsl.md` |
| App Store Connect の登録・提出準備 | `app-store-connect.md` |
| SSH Host エイリアスのリモートで `gh` が default remote エラー | `github-rare.md` の `#gh-default-repository-with-ssh-host-alias` |
| Copilot の PR レビュー依頼 | `github-rare.md` の `#copilot-review-latency` |
| GitHub Actions の課金エラー | `github-rare.md` の `#actions-billing-errors` |
| repo-status の再生成・更新 | `github-rare.md` の `#repo-status` |
| 新規リポジトリの作成 | `github-rare.md` の `#new-repository-creation` |
| 多数のリポジトリへ同じ PR を一括で出す | `github-rare.md` の `#bulk-pr-ready-conflicts` |
| 規約レビュー、dev-charter の引用元の変更把握 | `github-rare.md` の `#documentation-section-and-dev-charter` |

このファイルがシンボリックリンク経由の場合は、リンクの実体である `AI_CONTEXT_CLI.md` のディレクトリを基準に `references/` を解決する。
参照先を読めない場合は、その制約を報告し、未確認の手順を推測して実行しない。
