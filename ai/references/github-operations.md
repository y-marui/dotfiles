# GitHub Operation Procedures

`AI_CONTEXT_CLI.md` から、該当する作業時だけ参照する詳細手順。
共通規約の安全制約と commit・push の承認条件は引き続き適用する。

## Merge and Branch Cleanup

- PR ブランチのコンフリクト解消は rebase ではなく merge（base ブランチを PR ブランチにマージ）を使う。
  rebase は履歴を書き換え force push が必要になるため、他者が同じ PR ブランチに push している場合に問題になる。
  rebase は明示的に指示された場合のみ実施する
- マージ依頼には、マージ済みで未コミット変更や他の作業での使用がないブランチの整理を含める。
  マージ後は対象リポジトリと各 worktree の状態を確認し、現在のローカル tip が統合済みで、未 push の未統合コミットがない場合だけ整理する。
  upstream の消失だけで削除を判断しない。
  `git-sweep` はこれらの条件を守れる場合に使い、満たせない場合は対象を残す
- `git branch -d` は、リモートの同名ブランチを追跡している場合、その追跡先を基準に「統合済み」と判定する。
  そのため PR が未マージでも削除できてしまう。
  削除の前に、PR が MERGED であること（または `git merge-base --is-ancestor <branch> origin/<base>`）を確認する
- ツールが使えない場合や整理を保留した場合は、マージの完了と分けて報告する

## Assignees

- `y-marui/*` および `fukami-lab-sot/*` リポジトリで Issue を作成する場合は、見逃し防止のため assignee に `y-marui` を設定する。
  AI が直接操作する場合も、自動化コマンド経由の場合も同様
- 自分（`y-marui`）が作成する PR は、作成者として GitHub 上で追えるため assignee を付けない
- Dependabot 等の bot や他者が作る PR は、各リポジトリの `auto-assign-self.yml`（`pull_request_target`）が assign する。
  assignee 本人が作った PR は対象外。
  組織所有リポジトリでは Actions 変数 `AUTO_ASSIGN_USER=y-marui` が必要（未設定だと `repository_owner` が組織名になる）

## Automated Review

- PR での自動レビュー依頼は、PR コメントでのメンションで行う: Codex は `@codex review`、GitHub Copilot は `@copilot review`
- 自動レビュー（Copilot 等）の指摘は無条件に正しいものとして受け入れない。
  各指摘を自分で検証し、妥当と判断したものだけ修正する
- PR レビューコメント（自動レビュー、人間のレビュアー問わず）に対応したら、修正やコメントでの回答が完了した時点で、
  そのレビュースレッド（conversation）を resolve する。
  却下した指摘（対応しない判断をしたもの）も、理由をコメントで返信したうえで resolve する
- 自動レビューの指摘に対応して resolve したら、同じ PR で再度のレビュー依頼（`@codex review` 等の再メンション）はせずそのままマージしてよい。
  レビュー→修正→再レビューを繰り返して待たない

## Issue Language for Self-Executed Work

GitHub Issue の本文言語は、その Issue の残作業を誰が実行するかで決める。
他のコントリビューターや一般ユーザー向けの作業、あるいは一般的なプロジェクト文書として書く場合は、
そのリポジトリが定める言語ポリシー（`y-marui/*` は原則英語）に従う。
一方、実質的にユーザー自身が後で手を動かす TODO リスト（手動セットアップ手順、実機での検証、本人しか判断できない意思決定など）であれば、
リポジトリの言語ポリシーに関わらず本文は日本語で書く（タイトルはどちらでもよい）。
自分用のチェックリストは日本語の方が速く読めるため。

## Closed Issues

クローズ済みの GitHub Issue に、新しい問題点・調査結果・進捗を直接コメントとして書き込まない。
話題が元の Issue と近く見える場合も同様。
内容を書く先は新規 Issue とする。
クローズ済みの Issue 側には、必要であればその新規 Issue へのリンクのみを残す（内容は書かない）。
この方針はリポジトリを問わず適用する。

## Account Information

GitHub / BMC アカウントの対応表: `~/.identity/accounts.yaml`（dotfiles-private で管理）。
プロジェクトの GitHub オーナーを確認し、対応する `github` / `bmc` の値を使用する。
`make private` を実行済みであればファイルが存在する。
