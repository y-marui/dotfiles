---
name: session-handoff
description: "Close out a Git or non-Git work session: resolve or surface leftover tasks, then route durable decisions to project docs, an Obsidian Project Home when uniquely mapped, GitHub Issues, or supported agent memory so work resumes accurately in another chat. Use when the user asks to wrap up, hand off, or close out work before ending or switching a chat; not for routine task completion alone."
---

# Session Handoff

Git repository内外の作業セッションを、別チャット・別作業へ安全に引き継げる状態にする。今回の会話だけに残る一時的な記憶を正本にせず、性質ごとに適切な記録先（プロジェクトdocs、対応するObsidian Project Home、GitHub Issue、対応するagentの長期memory、git自体）へ振り分ける。

対象は、明示的に区切るGit作業（コード・設定・プロジェクトdocs等）と非Git作業全般。単発の質問や、区切りのない作業途中では呼び出さない。

## Step 1: Resolve or surface loose ends

1. 会話を振り返り、実施すると述べたが未完了の変更、ユーザーの未回答の質問、確認待ちの判断を洗い出す。
2. Git repositoryであれば、`git status` / `git diff` / `git log`で作業ツリーの実態を確認する。非Git作業では、対象の成果物・未完了事項・外部システムの状態を確認する。会話の記憶ではなく、今の実際の状態を正とする。
3. 安全に完了できるものはこの時点で完了する。commit・push・破壊的操作の確認要否は通常の安全ルールのまま変わらない。特にcommitは、今回のタスクでユーザーが明示的に指示していない限り、このskillを使うこと自体を理由に新規作成しない。
4. 判断が必要で完了できないものは、無理に片付けず一覧にする。「一旦保留」を暗黙のまま終わらせない。

Git repositoryで`obsidian-project-home`が使える場合は、`obsidian-project-home --repo <repository-root>`でProject Homeを解決する。終了コード`0`（一意）だけを対応付けとして使う。`3`（なし）、`4`（重複）、`5`（設定またはfrontmatter不正）の場合は、Project Homeを本文検索して推測・新規作成・更新せず、その状態を報告して以後の処理を続ける。

## Step 2: Classify what emerged this session

情報の性質ごとに記録先を分ける。1箇所に混在させない。**agentの長期memory（`~/.claude/projects/.../memory/` 等）は最後の手段であり、既定の置き場所ではない** — 下記の順で先に他の置き場所を検討し、どれにも当てはまらないと確認できた場合のみ長期memoryを使う。

| 情報の性質 | 記録先 |
| --- | --- |
| このプロジェクトに固有の仕様・設計判断・手順・制約、または「なぜこうなっているか」という背景（他プロジェクトとの関係・共有元リポジトリの存在なども含む） | プロジェクトの `AI_CONTEXT.md`（または `CLAUDE.md`/`AGENTS.md` が import する先）や `docs/`。「メタ情報っぽいから」「個人的な文脈だから」を理由に long-term memory へ逃がさない — 将来そのプロジェクトを読む人・AI の理解を助けるなら docs の役割。構成はプロジェクトの `DOCS_STRUCTURE.md` 相当の指示に従う |
| 特定プロジェクトに限らない、ユーザーの作業スタイル・恒久的な指示・Computer Use・CLI/Coding/GitHub運用フィードバック | まず `~/.ai/AI_CONTEXT.md`（常時読む対話・安全・ツール選択の原則）、`~/.ai/AI_CONTEXT_COMPUTER_USE.md`（ブラウザ・GUI操作）、`~/.ai/AI_CONTEXT_CLI.md`（CLI・Coding・リポジトリ・Git/GitHubの作業ルール）に書けないか検討する。これらは dotfiles 管理下でユーザー自身が全プロジェクト共通で使う恒久contextなので、Claude の long-term memory より優先する |
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

Project Homeは、解決済みの対応付けがあり、Current state・Open questions・重要判断・代表的なNext action・安定リンクのいずれかが実際に変わる場合だけ更新する。コードのPRやIssueが閉じただけでは`status: completed`にしない。Project Outcomeが満たされ、ユーザーが完了を明示した場合だけ変更する。

## Step 3: Apply updates with the right permission level

- プロジェクトdocsの編集は通常の編集操作として行う。
- `~/.ai/AI_CONTEXT.md` / `AI_CONTEXT_COMPUTER_USE.md` / `AI_CONTEXT_CLI.md`（dotfiles管理）の編集も通常の編集操作として行うが、dotfilesリポジトリへのcommit・pushはユーザーの明示的な指示があるときのみ行う。
- GitHub Issueの新規作成・更新、対象プロジェクト側のcommit・pushはそれぞれ影響を確認し、ユーザーの承認を得てから行う。
- 今回の作業の一時的な状態や進行中のタスク詳細はmemoryに書かない。

## Step 4: Git lifecycle

このskillはcommit・push・merge・ブランチ整理を実行しない。これらを含めて一度に終える場合は、ユーザーが明示的に呼び出す`session-finish`を使う。

## Completion report

完了・保留した項目、どこに何を記録したか（リポジトリdocs／Obsidian Project HomeまたはInbox/Daily／`~/.ai/AI_CONTEXT*.md`／Issue／memoryの別）、Project Homeの解決結果、再開時に見るべき場所（ブランチ・ファイル・Issue番号）を簡潔に報告する。未コミットの変更が残る場合は、その旨と`session-finish`で終えられることを示す。未解決のまま残った項目は隠さず明示する。
