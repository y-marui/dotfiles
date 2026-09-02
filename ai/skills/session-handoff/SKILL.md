---
name: session-handoff
description: "Close out a git-repo work session: resolve or surface leftover tasks, then route durable decisions to the right project docs, GitHub Issues, or supported agent memory so work resumes accurately in another chat. Use when the user asks to wrap up, hand off, or close out work before ending or switching a chat; not for routine task completion alone."
---

# Session Handoff

git repository内の作業セッションを、別チャット・別作業へ安全に引き継げる状態にする。今回の会話だけに残る一時的な記憶を正本にせず、性質ごとに適切な記録先（プロジェクトdocs、GitHub Issue、対応するagentの長期memory、git自体）へ振り分ける。

対象はgit repository内のエンジニアリング作業全般(コード・設定・プロジェクトdocs等)。単発の質問や、区切りのない作業途中では呼び出さない。

## Step 1: Resolve or surface loose ends

1. 会話を振り返り、実施すると述べたが未完了の変更、ユーザーの未回答の質問、確認待ちの判断を洗い出す。
2. `git status` / `git diff` / `git log` で作業ツリーの実態を確認する。会話の記憶ではなく、今の実際の状態を正とする。
3. 安全に完了できるものはこの時点で完了する。commit・push・破壊的操作の確認要否は通常の安全ルールのまま変わらない。特にcommitは、今回のタスクでユーザーが明示的に指示していない限り、このskillを使うこと自体を理由に新規作成しない。
4. 判断が必要で完了できないものは、無理に片付けず一覧にする。「一旦保留」を暗黙のまま終わらせない。

## Step 2: Classify what emerged this session

情報の性質ごとに記録先を分ける。1箇所に混在させない。**agentの長期memory（`~/.claude/projects/.../memory/` 等）は最後の手段であり、既定の置き場所ではない** — 下記の順で先に他の置き場所を検討し、どれにも当てはまらないと確認できた場合のみ長期memoryを使う。

| 情報の性質 | 記録先 |
| --- | --- |
| このプロジェクトに固有の仕様・設計判断・手順・制約、または「なぜこうなっているか」という背景（他プロジェクトとの関係・共有元リポジトリの存在なども含む） | プロジェクトの `AI_CONTEXT.md`（または `CLAUDE.md`/`AGENTS.md` が import する先）や `docs/`。「メタ情報っぽいから」「個人的な文脈だから」を理由に long-term memory へ逃がさない — 将来そのプロジェクトを読む人・AI の理解を助けるなら docs の役割。構成はプロジェクトの `DOCS_STRUCTURE.md` 相当の指示に従う |
| 特定プロジェクトに限らない、ユーザーの作業スタイル・恒久的な指示・CLI/GitHub運用フィードバック | まず `~/.ai/AI_CONTEXT.md`（対話スタイル・原則）や `~/.ai/AI_CONTEXT_CLI.md`（CLIツール向けの作業ルール）に書けないか検討する。これらは dotfiles 管理下でユーザー自身が全プロジェクト共通で読む恒久contextなので、Claude の long-term memory より優先する。編集は通常のファイル編集として行うが、dotfiles リポジトリへの commit は他プロジェクト同様ユーザーの明示的な指示があるときのみ行う |
| 上記どちらにも当てはまらない、Claude自身の運用にのみ関わる情報（ユーザー自身のcontextファイルに書くには細かすぎる／Claude固有の挙動に関する事項） | 実行中のagentが対応し、ユーザーが明示的に保存を求めた場合だけ長期memoryに保存する。保存不可または基準が不明な場合は保存せず、ユーザーへ報告する |
| 未完了のTODO・バックログ・調査中の仮説・実装チェックリスト | GitHubのIssue/Sub-issue/Project。リポジトリに `TODO.md` 等の一時ファイルとして残さない |
| 次にどこから再開するか（対象ブランチ・ファイル・直前の判断） | git自体（コミットメッセージ、ブランチ名、必要なら記述的なstashメッセージ）。恒久ドキュメントにもmemoryにも書かない |

- プロジェクトがdev-charter相当の指針を導入している場合は、その「一時情報はIssue、恒久情報はdocs」区分に従う。導入していない場合も同じ区分を既定とし、プロジェクト固有のルールがあればそちらを優先する。
- プロジェクトdocsを更新する前に、プロジェクトのAI_CONTEXT系ファイルが指定する参照順序・命名規則を確認する。
- 既存のagent長期memoryを見つけた場合、その内容が実際には上記いずれか（プロジェクトdocsまたはグローバルcontext）に属するなら、この機会に移管して重複を解消する（該当プロジェクトのセッションでは、次回セッションで気づいた際にも同様に扱う）。
- 該当する記録先が存在しない、またはどちらに書くべきか不明な場合は、推測で新規ファイルを作らずユーザーに確認する。

## Step 3: Apply updates with the right permission level

- プロジェクトdocsの編集は通常の編集操作として行う。
- `~/.ai/AI_CONTEXT.md` / `AI_CONTEXT_CLI.md`（dotfiles管理）の編集も通常の編集操作として行うが、dotfilesリポジトリへのcommit・pushはユーザーの明示的な指示があるときのみ行う。
- GitHub Issueの新規作成・更新、対象プロジェクト側のcommit・pushはそれぞれ影響を確認し、ユーザーの承認を得てから行う。
- long-term memoryへの保存は、実行中のagentが対応し、ユーザーが明示的に求めた場合だけ既存のmemory種別の基準に従って行う。今回の作業の一時的な状態や進行中のタスク詳細はmemoryに書かない。

## Completion report

完了・保留した項目、どこに何を記録したか（docs／`~/.ai/AI_CONTEXT*.md`／Issue／memoryの別）、再開時に見るべき場所（ブランチ・ファイル・Issue番号）を簡潔に報告する。未解決のまま残った項目は隠さず明示する。
