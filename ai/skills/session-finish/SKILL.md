---
name: session-finish
description: "Finish a work session end to end when the user explicitly invokes it: run session-handoff, then commit and push this session's changes (including the Obsidian Project Home that session-handoff updated, in its vault repository) and run git-sweep --all, stopping and reporting when a safety condition fails. Use only when the user explicitly asks to finish or end the session (for example /session-finish); never trigger on its own, and not for a handoff-only request (use session-handoff)."
---

# Session Finish

作業セッションを、記録の整理からGitの後始末まで一度に終える。ユーザーがこのskillを明示的に呼び出したことを、当該セッションで変更した範囲のcommitとpushの指示として扱う。この範囲には、`session-handoff`が更新したObsidian Project Home（vaultリポジトリ内のファイル）も含む。自動では呼び出さない。記録の整理だけを求められた場合は`session-handoff`を使う。

## Authorization

承認に含める操作は、次の2つだけとする。

- 当該セッションで変更した範囲のcommitと、現在のブランチのpush
- `session-handoff`が`obsidian-project-home`で一意に解決して更新したProject Home（vaultリポジトリ内のファイル）のcommitと、そのリポジトリの現在のブランチのpush。これは「他リポジトリの変更」の例外として扱う

次は含めず、必要になった時点で止めてユーザーに確認する。

- PRの作成・merge、local merge
- force push、上記のProject Home以外の他リポジトリの変更（dotfilesを含む）
- ユーザーの変更でない既存の未コミット差分のcommit
- フックの回避（`--no-verify`等）

## Step 1: Check the state

1. Git repositoryでなければ、`session-handoff`だけを実行して終える。
2. `git fetch`でリモートの最新状態を取り込み、`git status`・現在のブランチ・リモートとの差を確認する。
3. 作業ツリーに今回のセッションと無関係な変更が混ざっている、またはリモートとdivergしている場合は、commitせずに止めて報告する。

## Step 2: Run session-handoff

`session-handoff`を実行し、未完了事項と恒久情報の記録先を整える。docsやcontextの更新はここで済ませ、同じcommitに含める。commit後にhandoffでファイルが増えて追加commitが必要にならないようにする。

`session-handoff`がProject Homeを更新した場合は、その時点でvaultリポジトリの状態も確認する。`git fetch`の後、`git status`・現在のブランチ・リモートとの差を見て、今回のセッション以外の未コミット変更が混ざっている、またはリモートとdivergしている場合は、vaultだけをcommitせずに止めて報告する（コードリポジトリ側の処理は続ける）。

## Step 3: Commit

1. プロジェクトの指示で、現在のブランチで進めてよい規模か、PR経由にすべき規模かを判断する。PR経由が必要で`main`などの保護対象にいる場合は、作業ブランチを作ってからcommitする。
2. push前に、プロジェクトのCI設定（`.github/workflows/`）から、変更に関連するlint・build・testをローカルで実行する。実行できない検証は、理由と未確認範囲を報告する。
3. 今回変更したファイルだけを明示してstageし、Conventional Commits形式でcommitする。グローバル・プロジェクトのattribution指示があれば従う。
4. pre-commitなどのフックが失敗したら回避せず、原因を修正してからやり直す。
5. Project Homeを更新した場合は、vaultリポジトリでも同様にcommitする。更新したProject Homeのファイルだけを明示してstageし、メッセージはvaultの`git log`の直近の形式に合わせる（Conventional Commits形式。例: `docs: <project> の<変更点>を反映`）。attribution指示があれば従う。vaultが現在のブランチへの直接commitを運用しているか（直近の履歴とvaultの`AI_CONTEXT.md`）を確認し、PR経由が必要な場合はcommitせずに止めて報告する。

## Step 4: Push

- PRを使わない作業: 現在のブランチをpushする。
- PRを使う作業: 作業ブランチをpushし、PRの状況（番号・draft・CI）を報告して止まる。PR作成・mergeは別途の指示を待つ。
- Project Homeのcommit: vaultリポジトリの現在のブランチをpushする。ルールで拒否された場合は、force pushや回避をせずに止めて報告する（ブランチ保護のバイパス権限で通る通常のpushは、そのまま行ってよい）。

## Step 5: Clean up

`git-sweep --all`は、対象worktreeがcleanで、現在のtipが統合済み（`main`にmerge済み）と確認できる場合だけ実行する。PRが未mergeなど、条件を満たさない場合は実行せず、その理由を報告する。

## Completion report

実施した項目（記録先の整理、commit、push、sweep）と、止めた項目・未実施の項目を分けて示す。Project Homeを更新した場合は、vaultリポジトリのcommit・pushの結果（コミットID、またはvaultだけ止めた理由）を、コードリポジトリとは別に書く。止めた理由（フック失敗、divergence、混在した変更、未mergeのPRなど）と、再開時に見る場所（ブランチ・PR番号）を併記する。
