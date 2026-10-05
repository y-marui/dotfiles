---
name: obsidian-maintain-record-review
description: Proofread the Obsidian Records changed since the last reviewed point, tracked by the origin/ai/review branch, then commit, push, and advance the marker. Use for the scheduled proofreading run; use obsidian-maintain-record for files the user names.
---

# Maintain Obsidian Records (Review Range)

## Purpose

`origin/ai/review`が指す「校正済みの範囲」の終端から`origin/main`までの差分を、`obsidian-maintain-record`で校正する薄いラッパー。定期実行のスケジュールタスクから呼ぶ。ユーザーが指定した個別ファイルの校正には使わない（`obsidian-maintain-record`を使う）。

校正の中身（意味を保つ、敬体の維持、`#no-update`の保護など）は`obsidian-maintain-record`に従う。このskillは、対象範囲の決定、commitとpush、目印の更新だけを持つ。

`ai/review`の意味と運用は、対象Vaultの`docs/vault-operations.md`「校正用スケジュールタスクと`ai/review`」を正本とする。

## Preconditions

呼び出し側（スケジュールタスク）が、`git fetch`、未コミット変更の確認、pull、conflict時の中断までを済ませている前提とする。このskillは次を確認し、満たさなければ何も変更せず、理由を報告して止まる。

- 作業ツリーが`git status --porcelain`で空である。
- ローカルの`main`が`origin/main`と一致している（未pushのコミットがない）。
- `origin/ai/review`が存在し、`origin/main`の祖先である。

commitとpushは、呼び出し側が明示的に依頼した場合だけ行う。明示がなければドライランとし、対象ファイルの一覧を報告するだけでファイルを変更しない。

## Target Selection

1. `git diff --name-only --diff-filter=AMR origin/ai/review origin/main`の結果を取る。
2. 次の`.md`だけに絞る。
   - `records/daily/`
   - `records/reviews/`
   - `records/conversations/`
3. 次を除く。
   - `private/**`、移行前の`conversation_log/`と`idea_notes/`。
   - 実行日（JST）の日付をファイル名に持つDaily（`records/daily/<年>/YYYY-MM-DD.md`の日付が当日のもの）。
   - `#no-update`を含むファイル。
4. 前日（JST）の日付のDailyが存在すれば、差分の有無に関わらず対象に加える。当日分を除外したまま目印を進めるため、翌日に拾えるようにする。
5. 並びは、Daily、Review、Conversationの順にする。

対象が空なら、校正は行わず、`Marker`の手順へ進む。

## Proofread

`obsidian-maintain-record`を実行し、`Target Selection`で得たファイルを対象Recordとして明示する。次を伝える。

- commitとpushはこのskillが行うため、`obsidian-maintain-record`はcommitもpushもしない。
- 意味を変える疑い、対象不明、Private判断不能などで触らなかったファイルは、理由を付けて一覧で返す。ユーザーへの確認を求めず、そのファイルは未処理のまま残す。

## Commit and Push

1. 校正で変更があったファイルだけを明示してstageし、1つのコミットにまとめる。メッセージは`docs: proofread records pulled via scheduled sync`とする。
2. pre-commitなどのフックが失敗したら、回避せず原因を報告して止まる。pushも、目印の更新もしない。
3. `git push origin main`でpushする。拒否された場合は、forceせず、原因を報告して止まる。目印は更新しない。
4. 変更がなかった場合は、commitもpushも行わない。

## Marker

`origin/ai/review`は、`main`へのpushが成功した後だけ更新する。

- 触らなかったファイルが1つでもある回は、更新しない。次回、同じファイルを再度対象にして報告する。
- 位置は、コミットを作った場合はそのコミット、作らなかった場合はpull後の`origin/main`の先頭とする。
- 更新は`git push origin <commit>:refs/heads/ai/review`で行う。更新前に、`origin/ai/review`が`<commit>`の祖先であることを確認し、force pushは使わない。
- 呼び出し側がpushを明示していない場合（ドライラン）は更新しない。

## Prohibited

- `--force`、`--force-with-lease`、rebase、`reset --hard`、`git clean`、ブランチの削除。
- `ai/review`への直接のコミットや、`main`以外のブランチでの校正。
- 対象でないファイルのstage、commit。
- フックの回避（`--no-verify`等）。

## Report

最後に、日本語で簡潔に報告する。

- 範囲: 更新前の`ai/review`の位置と、`origin/main`の位置。
- 対象にしたファイルと、校正で変更したファイル。
- 触らなかったファイルと理由。
- commitとpushの結果（コミットID）。
- `ai/review`の更新の有無と、更新後の位置。
- 止まった場合は、その理由と、再開時に見る場所。
