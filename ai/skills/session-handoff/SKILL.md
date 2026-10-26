---
name: session-handoff
description: "Close out a work session before compacting or switching chats: resolve leftover tasks, route durable decisions to project docs, Obsidian Project Home, GitHub Issues, or memory, and ship completed work to main (commit, push, PR, merge). Supports main/sub roles. Use when the user asks to wrap up or hand off; to end the session, use session-finish."
---

# Session Handoff

Git repository内外の作業セッションを、別チャット・別作業へ安全に引き継げる状態にする。今回の会話だけに残る一時的な記憶を正本にせず、性質ごとに適切な記録先（プロジェクトdocs、対応するObsidian Project Home、GitHub Issue、対応するagentの長期memory、git自体）へ振り分ける。

このskillは、`/compact`の前の区切りとして使う。compactで失われる情報を記録先へ移し、区切りのついた作業をremoteとmainに反映して、セッションを続けられる状態にする。セッション自体を終える場合は`session-finish`を使う。

対象は、明示的に区切るGit作業（コード・設定・プロジェクトdocs等）と非Git作業全般。単発の質問や、区切りのない作業途中では呼び出さない。

## Role

引数（`sub`・`main`・`solo`）を優先し、なければ`list_sessions {linked:true}`で子がいれば`main`、なければ`solo`とみなす。`sub`は、依頼文や会話からサブセッションとして起動されたと分かる場合。`sub`はProject Homeを編集せず、mergeもせず、報告で返す。判定と役割ごとの違い、`sub`の報告の形は [references/roles.md](references/roles.md) を全文読んで従う。

## Step 1: Resolve or surface loose ends

1. 会話を振り返り、実施すると述べたが未完了の変更、ユーザーの未回答の質問、確認待ちの判断を洗い出す。
2. Git repositoryであれば、`git status` / `git diff` / `git log`で作業ツリーの実態を確認する。非Git作業では、対象の成果物・未完了事項・外部システムの状態を確認する。会話の記憶ではなく、今の実際の状態を正とする。
3. 安全に完了できるものはこの時点で完了する。破壊的操作の確認要否は通常の安全ルールのまま変わらない。commit・push・PR・mergeはStep 4（`references/ship.md`）の範囲だけ、このskillの呼び出しを承認として行う。
4. 判断が必要で完了できないものは、無理に片付けず一覧にする。「一旦保留」を暗黙のまま終わらせない。

`main`は、各子セッションのPRがmerge済みか確認する。未mergeのものは止めて報告する（mainがmergeを代行するのは、そのPRのCI・レビューが`references/ship.md`の条件を満たすときだけ）。

Git repositoryで`obsidian-project-home`が使える場合（`sub`を除く）は、`obsidian-project-home --repo <repository-root>`でProject Homeを解決する。終了コード`0`（一意）だけを対応付けとして使う。`4`（重複）、`5`（設定またはfrontmatter不正）の場合は、Project Homeを本文検索して推測・新規作成・更新せず、その状態を報告して以後の処理を続ける。

`obsidian-project-home` が終了コード`3`（なし）を返した場合は、Step 1〜3の後に [references/project-home-ensure.md](references/project-home-ensure.md) を全文読んで従う（`ensure`は作業開始時には実行しない）。

## Step 2: Classify what emerged this session

情報の性質ごとに記録先を分ける。1箇所に混在させない。**agentの長期memory（`~/.claude/projects/.../memory/` 等）は最後の手段であり、既定の置き場所ではない** — 下記の順で先に他の置き場所を検討し、どれにも当てはまらないと確認できた場合のみ長期memoryを使う。

| 情報の性質 | 記録先 |
| --- | --- |
| このプロジェクトに固有の仕様・設計判断・手順・制約、または「なぜこうなっているか」という背景（他プロジェクトとの関係・共有元リポジトリの存在なども含む） | プロジェクトの `AI_CONTEXT.md`（または `CLAUDE.md`/`AGENTS.md` が import する先）や `docs/`。「メタ情報っぽいから」「個人的な文脈だから」を理由に long-term memory へ逃がさない — 将来そのプロジェクトを読む人・AI の理解を助けるなら docs の役割。構成はプロジェクトの `DOCS_STRUCTURE.md` 相当の指示に従う |
| 特定プロジェクトに限らない、ユーザーの作業スタイル・恒久的な指示・Computer Use・CLI/Coding/GitHub運用フィードバック | まず `~/.ai/AI_CONTEXT.md`（常時読む対話・安全・ツール選択の原則）、`~/.ai/AI_CONTEXT_COMPUTER_USE.md`（ブラウザ・GUI操作）、`~/.ai/AI_CONTEXT_CLI.md`（CLI・Coding・リポジトリ・Git/GitHubの作業ルール）に書けないか検討する。頻度の低い手順は本文を増やさず、dotfilesの`ai/references/`へ置き、`AI_CONTEXT_CLI.md`末尾のDetail Referencesの表に読むトリガーを足す。これらは dotfiles 管理下でユーザー自身が全プロジェクト共通で使う恒久contextなので、Claude の long-term memory より優先する |
| 上記どちらにも当てはまらない、Claude自身の運用にのみ関わる情報（ユーザー自身のcontextファイルに書くには細かすぎる／Claude固有の挙動に関する事項） | 実行中のagentが対応し、ユーザーが明示的に保存を求めた場合だけ長期memoryに保存する。保存不可または基準が不明な場合は保存せず、ユーザーへ報告する |
| 未完了のTODO・バックログ・調査中の仮説・実装チェックリスト | GitHubのIssue/Sub-issue/Project。リポジトリに `TODO.md` 等の一時ファイルとして残さない |
| 一意に対応付けられたコードProjectの現在地、重要な横断判断、解決していない問い、代表的な次の一手、安定した外部参照 | Obsidian Project Home。技術的な設計・実装・設定・テスト・復旧手順の正本はコードリポジトリのdocsに残し、同じ詳細を複製しない |
| まだ結論のない個人的な考え・比較・検討 | 対応するProject Homeの`Open questions`。Projectに属さない未分類の考えはObsidian Inbox。複数Projectにまたがる提案は`status: proposed`のDecision |
| その日に意味のある節目・判断・振り返り | Obsidian Daily。細かな実装ログは残さず、必要な日だけ1〜3項目を目安に追記する |
| 次にどこから再開するか（対象ブランチ・ファイル・直前の判断） | git自体（コミットメッセージ、ブランチ名、必要なら記述的なstashメッセージ）。恒久ドキュメントにもmemoryにも書かない |

- プロジェクトがdev-charter相当の指針を導入している場合は、その「一時情報はIssue、恒久情報はdocs」区分に従う。導入していない場合も同じ区分を既定とし、プロジェクト固有のルールがあればそちらを優先する。
- プロジェクトdocsを更新する前に、プロジェクトのAI_CONTEXT系ファイルが指定する参照順序・命名規則を確認する。
- 既存のagent長期memoryを見つけた場合、その内容が実際には上記いずれか（プロジェクトdocsまたはグローバルcontext）に属するなら、この機会に移管して重複を解消する（該当プロジェクトのセッションでは、次回セッションで気づいた際にも同様に扱う）。
- 該当する記録先が存在しない、またはどちらに書くべきか不明な場合は、推測で新規ファイルを作らずユーザーに確認する。

Project Homeは、解決済みの対応付けがあり、Current state・Open questions・重要判断・代表的なNext action・安定リンクのいずれかが実際に変わる場合だけ更新する。日付・PR番号つきの経過（merge、デプロイ、確認の結果）はProject HomeのNext actionsに溜めず、同じディレクトリの`<project>-changelog.md`へ追記する（`-changelog`・`CHANGELOG*.md`は`doc-lint`のサイズ検査の対象外）。コードのPRやIssueが閉じただけでは`status: completed`にしない。Project Outcomeが満たされ、ユーザーが完了を明示した場合だけ変更する。

## Step 3: Apply updates with the right permission level

- プロジェクトdocsの編集は通常の編集操作として行う。
- `~/.ai/AI_CONTEXT.md` / `AI_CONTEXT_COMPUTER_USE.md` / `AI_CONTEXT_CLI.md`（dotfiles管理）の編集も通常の編集操作として行うが、dotfilesリポジトリへのcommit・pushはユーザーの明示的な指示があるときのみ行う。
- このセッションの未完了事項のGitHub Issue新規作成・更新は、このskillの呼び出しを承認として行う（重複を`search_issues`で確認し、`y-marui/*`・`fukami-lab-sot/*`はassigneeに`y-marui`を設定する）。このセッションと無関係なIssueの更新や、対象プロジェクト側のcommit・push・PR・mergeはStep 4の範囲だけ行う。
- Project Home（Obsidian vault内のファイル）の編集は通常の編集操作として行う（`sub`は編集しない）。そのvaultリポジトリのcommit・pushも、このskillの呼び出しを承認として行う。更新・新規作成したProject Homeのファイルだけを明示してstageし、メッセージはvaultの`git log`の直近の形式に合わせる。今回のセッション以外の未コミット変更が混ざる、またはリモートとdivergしている場合は、vaultだけ止めて報告する。
- 今回の作業の一時的な状態や進行中のタスク詳細はmemoryに書かない。

## Step 4: Ship

[references/ship.md](references/ship.md)を全文読んで従う。このskillの呼び出しは、ship.mdのAuthorizationに挙げた操作（このセッションの変更のcommit・push、自分のPRの作成・ready化・merge）の承認として扱う。区切りのついた作業単位はmainまで反映し、未完了の単位はブランチへのpushまでにとどめる。

このskillはセッションを閉じない。archive、`git-sweep --all`、実機への反映（post-merge）は行わない。これらを含めて終える場合は、ユーザーが明示的に呼び出す`session-finish`を使う。

## Completion report

完了・保留した項目、記録先（docs／Project HomeまたはInbox/Daily／`~/.ai/AI_CONTEXT*.md`／Issue／memoryの別）、Project Homeの解決結果、再開点（ブランチ・ファイル・Issue番号）を簡潔に報告する。shipの結果（commit・push・PR・merge、止めた単位とその理由）を示す。残った未完了の単位は、ブランチ・PR番号とともに再開点として書く。その後に`/compact`して作業を続けてよいこと、終えるなら`session-finish`を使うことを示す。`sub`は上記の報告の形で返す。未解決のまま残った項目は隠さず明示する。
