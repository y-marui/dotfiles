---
name: obsidian-save-project
description: Create a Project Home in projects from a referenced Codex or ChatGPT chat when the user has decided to execute it. Use only when the outcome and next action are clear; use obsidian-save-knowledge for an uncommitted proposal.
---

# Save Obsidian Project

参照チャットから、実行を決めた活動のProject Homeを作る。検討だけの企画や単なる調査には使わない。

ユーザーがダウンロード済みZIPまたは展開済み会話資料を指定した場合は、先に[共通の原資料読取手順](../obsidian-save-record/references/exported-chat.md)を全文読み、原本・上流Markdown・補足・添付を照合する。以下の会話リーダーは不足資料の取得に使う。出力は本skillの現行形式を維持する。

会話Recordを作成・整備する場合は、対象vaultの`docs/conversation-record-format.md`を全文読み、全発話と保存時の補足・取得状態を区別する。Daily・Reviewには会話形式を強制しない。

1. 参照種別に対応する公式の会話読み取り手段で対象チャットを最後まで読む。Codex taskでは`read_thread`を使い、ChatGPT conversationでは利用可能なChatGPT会話リーダーを使う。ページがあればcursorをたどる。対応する読み取り手段がない場合は、原資料Recordを部分取得と明示して保存し、追加資料を依頼する。Projectの目的・判断の確認に必要な資料が欠けている場合は、Projectを推測で作らない。
2. vaultの入口文書と構造・運用文書を読み、既存Projectと関連Knowledgeを検索する。
3. ユーザーが実行を決め、Outcomeと代表的なNext actionが確認できる場合だけ作成する。不足する場合は`obsidian-save-knowledge`を使う。
4. 根拠となる会話Recordがなければ、`obsidian-save-record`の基準で作成する。
5. 小規模なProjectは`projects/<project-id>.md`、補助文書が必要な場合だけ`projects/<project-id>/<project-id>.md`とする。
6. `system/templates/project.md`を使い、Outcome、Current state、Next actions、Decisions、Open questions、Key context、External systems、Changelogを合意範囲だけ記す。
7. コード実装の仕様と作業タスクは対応するコードリポジトリとGitHubを正本にし、Project Homeには背景、現在地、安定参照を残す。Issueやリポジトリは明示依頼なしに作成しない。

完成後にリンク、`git diff --check`、`git status --short`を確認する。commitやpushは明示依頼がある場合だけ行う。
