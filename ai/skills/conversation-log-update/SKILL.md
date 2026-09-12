---
name: conversation-log-update
description: Proofread and rewrite conversation logs in the conversation_log directory of the obsidian-vault repository, and, when explicitly requested, migrate daily-note tasks to Google Tasks through Glance Task.
---

# Conversation Log Update

## Target Files

- 個別指定時は、そのファイルだけを対象にしてブランチ間差分を確認しない。
- 指定がなければ、`origin/ai/review` があれば `git diff --name-only origin/main origin/ai/review` の差分、なければ `conversation_log/` 配下の全 `.md` を対象にする。

## Flow

- 個別指定時は、読み込み・校正・保存・コミットを最小限に行い、`origin/ai/review` へpushしない。
- 自動抽出時は確認を挟まず連続処理し、完了後に一度だけコミット・pushする。
- 校正後の全文は出力せず、`Updated: filename` のように簡潔に報告する。

## Google Tasks Migration

日次ログの行動可能な「タスク」は、原則としてGlance Taskを経由してGoogle Tasksへ移管する。移管が明示されていない場合は、候補と移管先を提示し、作成前に一度だけ確認する。移管の依頼または確認が得られた場合は、ログ更新と同じ作業で作成・検証・記録まで行う。

- `#no-update` を含むファイルは移管対象にしない。
- 時刻が決まった予定はGoogle Calendar、コード・実装を伴うタスクはGitHub、先送りするメモやアイデアはObsidianで扱う。Google Tasksには、これら以外の行動タスクだけを移す。
- 移管前にGlance Taskからタスクグループと移管先の既存タスクを取得し、安定IDで操作する。同一タイトルの未完了タスクがあれば新規作成せず、そのタスクを使う。似ているだけで目的が異なるタスクは別タスクとして扱う。
- 移管先の指定を優先する。指定がなければ、研究に直接関係するタスクは「仕事」、それ以外は「趣味」に入れる。
- タイトルにはログの短い見出し、メモには本文の説明を使う。期限・親タスク・順序は、ユーザーの指定がない限り追加しない。
- 作成後は、タイトル・未完了状態・タスクIDを再取得して確認する。未認証、移管先不明、または分類を決められない場合は作成せず、必要な対応をユーザーへ尋ねる。
- Google TasksのWeb URLは安定して参照できないため、ログにはGlance Taskで確認した安定タスクIDを記録する。各タスク本文の直後に次の形式で追記する。

  `<br><span style="color: var(--text-faint);">Google Tasks: <code style="color: inherit;">{タスクID}</code></span>`

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
