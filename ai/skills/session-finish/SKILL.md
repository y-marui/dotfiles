---
name: session-finish
description: "Finish a work session end to end when the user explicitly invokes it: run session-handoff (records, then commit, push, PR, and merge of completed work to main), then deploy to devices when the project requires it, archive sub-sessions and this session, and run git-sweep --all so local is clean. Supports main/sub roles. Use only when the user explicitly asks to finish or end the session (for example /session-finish); never trigger on its own, and not for a handoff-only or compact-and-continue request (use session-handoff). Never run in a sub-session."
---

# Session Finish

作業セッションを、記録の整理からmainへの反映、実機への反映、archive、localの後始末まで一度に終える。ユーザーがこのskillを明示的に呼び出したことを、`session-handoff`の`references/ship.md`のAuthorizationに挙げた操作と、下記の後始末の承認として扱う。自動では呼び出さない。続けて作業する区切りには`session-handoff`を使う。

## Role

`session-handoff`のRoleの判定に従う。`sub`の場合は、このskillを実行せず`session-handoff sub`だけを実行する（`session-finish`はメインセッションだけで実行する）。以下は`solo`・`main`向け。

## Authorization

`session-handoff`で承認される操作（commit・push・自分のPRの作成とmerge、Project Homeのcommit・push、未完了事項のIssue）に加えて、次を承認に含める。

- 子セッションのarchiveと、このセッション自体のarchive
- worktreeとブランチの整理（`git-sweep --all`）
- `references/post-merge.md`で決まる実機・環境への反映コマンドの実行

次は含めず、必要になった時点で止めてユーザーに確認する。

- force push、squash・rebase merge、フックの回避（`--no-verify`等）
- 他リポジトリの変更（Project Homeのvaultを除く）、ユーザーの変更でない既存の未コミット差分のcommit
- 署名・公開（ストア提出など）

## Step 1: Check the state

1. Git repositoryでなければ、`session-handoff`だけを実行して終える（archiveは行う）。
2. `git fetch`でリモートの最新状態を取り込み、`git status`・現在のブランチ・リモートとの差を確認する。
3. `main`は`list_sessions {linked:true}`で子セッションの一覧と状態を確認する。実行中の子がいれば止めて報告する。

## Step 2: Run session-handoff

`session-handoff`をRoleに従って実行する。記録の整理（docs、Issue、Project Homeの1回の更新）、commit、push、PR、mergeまで含まれる。ここで未mergeのPRや止めた単位が残った場合は、その単位のブランチとworktreeを後始末の対象にしない。

## Step 3: Archive sub-sessions

`main`は、PRがmerge済みで`session-handoff sub`の報告が済んだ子セッションだけを`archive_session`でarchiveする。未mergeの子、報告がない子はarchiveせず、理由を報告する。

## Step 4: Clean up

対象は、このセッションと子セッションが作った作業ブランチ、サブブランチ、worktreeすべて。統合済み（PRがmerge済みで、`main`にmerge済み）と確認できるものだけを整理し、未統合・未pushのコミット、dirtyなworktreeがあるものは残して理由を報告する。

1. 子セッションのworktreeは、archive後に`git worktree remove`で取り除く（dirtyなら取り除かない）。このセッション自体がアプリの作ったworktreeで動いている場合は、自分の作業ディレクトリを消せないので、Step 6のarchive後にアプリの`clean_up_worktrees`で整理する。それでも整理できない場合は、ユーザーが主checkoutで実行するコマンド（`git worktree remove <path>`と`git branch -d <branch>`。pathとbranchは実際の値）を完了報告に示す。
2. 主checkout（元のリポジトリ）で`git-sweep --all`を実行し、merge済みのローカル・リモート追跡ブランチを削除する。出力が多いので`run-quiet`でラップしてよい。
3. 次を確認する。満たさなければ`git checkout main`・`git pull --ff-only`で整え、できなければ理由を報告する。
   - 主checkoutのブランチが`main`（プロジェクトのデフォルトブランチ）である
   - 作業ツリーがcleanで、`origin/main`と一致している（ahead・behindが0）
   - 統合済みのローカルブランチとworktreeが残っていない（残るものは未統合の理由を報告に書く）

## Step 5: Post-merge

[references/post-merge.md](references/post-merge.md)を全文読んで従う。最新のmainで、実機・環境への反映が必要なら実行する。何もmergeしなかった、または最後のmerge後に実行済みでmainが変わっていないときは省略する。

## Step 6: Archive this session

Step 4の確認結果を含む完了報告を出してから、最後に`archive_session`でこのセッションをarchiveする。止めた項目（未mergeのPR、`main`に戻せない、フック失敗、divergence、実行中の子、post-mergeの失敗など）が残る場合は、archiveせずにセッションを残し、理由と再開点を報告する。

## Completion report

実施した項目（記録先の整理、commit、push、PR・merge、子セッションのarchive、worktree・ブランチの整理、`main`への復帰確認、sweep、post-merge、このセッションのarchive）と、止めた項目・未実施の項目を分けて示す。Project Homeを更新した場合は、vaultリポジトリのcommit・pushの結果を、コードリポジトリとは別に書く。止めた理由と、再開時に見る場所（ブランチ・PR番号・Issue番号）を併記する。
