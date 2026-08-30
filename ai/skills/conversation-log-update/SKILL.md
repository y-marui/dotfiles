---
name: conversation-log-update
description: Proofread and rewrite conversation logs in the conversation_log directory of the obsidian-vault repository, pushing changes to main and ai/review branches.
---

# Conversation Log Update

## Target Files

- 個別指定時は、そのファイルだけを対象にしてブランチ間差分を確認しない。
- 指定がなければ、`origin/ai/review` があれば `git diff --name-only origin/main origin/ai/review` の差分、なければ `conversation_log/` 配下の全 `.md` を対象にする。

## Flow

- 個別指定時は、読み込み・校正・保存・コミットを最小限に行い、`origin/ai/review` へpushしない。
- 自動抽出時は確認を挟まず連続処理し、完了後に一度だけコミット・pushする。
- 校正後の全文は出力せず、`Updated: filename` のように簡潔に報告する。

## Editing Rules

### Protected Tags

`#no-update` を含むファイルは校正・要約・再構成をせず、Git操作では現状のまま扱う。

### Daily Notes (`YYYY-MM-DD.md`)

冒頭3節を必ず「タスク」「予定」「課題」にし、次の形式で書く。

- **タスク**: 今日やるべきこと、または現在進行中のタスク。
- **予定**: **明日以降**に控えている未来の予定。
- **課題**: 現在直面している問題点や、改善すべき事項。

`## タスク` (または `## 予定`, `## 課題`)
`* **短い見出し**: 自然な文章による中身の説明（過度な要約を避け、元のニュアンスを維持・拡張する）`

4節目以降は当日の活動・出来事・対話を、抽象カテゴリでなく具体的な話題ごとに書く。

`## 具体的なトピック名`
`自然な文章による中身の説明（過度な要約を避け、論理的な一文または段落として構成する）`

- 明日以降の行動予定は、タスクまたは本文から「予定」へ移す。
- タスクと本文が重複する場合は、詳細をタスクへ統合して本文側を削除する。

### Other Files (`-MJ.md`, `-(topic).md`)

誤字脱字を直し、構造的な改善が見込める場合だけ論理的で読みやすい構成へ再構成する。

### Common Rules

- 文体は簡潔な「だ・である」調または体言止め。メッセージ、メール、対話文は元の敬体を維持する。
- 原文の敬称を保ち、ない敬称を追加しない。要約だけにせず、意味を保って文脈を補完する。
- 「追記」「Append」「後日談」は本文の適切な位置へ統合する。コード、参考文献、`## Appendix`、`## 付録` は末尾の独立節として残す。
- 指示されない「まとめ」「考察」「追記」などの定型節を作らない。

## Git

- コミットメッセージ: `YYYY-MM-DD HH:MM:SS - Proofread and rewrite conversation logs`
- 個別指定時は `upstream` (main) のみ、自動抽出時は `upstream` と `origin/ai/review` の両方へpushする。
