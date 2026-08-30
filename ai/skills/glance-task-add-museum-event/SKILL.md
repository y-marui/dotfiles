---
name: glance-task-add-museum-event
description: "Add a new exhibition task to Glance Task's 「美術展: 関東」 or 「美術展: 東北」 group through AppleScript, format its period and venue, and create it directly in unfinished-task position order with add task's optional after parameter. Use only for creating a new museum or art exhibition task; use glance-task-format-museum-events for existing-task formatting and order repair."
---

# Add a Glance Task Museum Event

同梱CLIとGlance TaskのAppleScriptコマンドを使い、新しい美術展を必ず1件だけ作成する。表示順には `fetch tasks` の配列順ではなく、必ず `task position` を使う。

## Collect the Event

- 対象グループは必ず `美術展: 関東` または `美術展: 東北` に確定する。地域が不明なら質問する。
- 展示名、開始日、終了日、会場を必須とする。終了日がない場合は、1日開催であることが明確なときだけそう扱う。
- ステータス絵文字を推測して追加しない。
- 完全一致する展示名の重複を確認する。存在する場合は新規追加せず、既存の安定したタスクIDとともに `glance-task-format-museum-events` skill へ引き継ぐ。

## Format

タイトルには展示名を入れる。メモには半角スペース1つと月日2桁表記を使い、厳密に `<period> <venue>` を入れる。

```text
1日開催         YYYY/MM/DD 会場
同月開催        YYYY/MM/DD-DD 会場
同年開催        YYYY/MM/DD-MM/DD 会場
年またぎ開催    YYYY/MM/DD-YYYY/MM/DD 会場
```

終了日が開始日より前なら受け付けない。日付または会場が曖昧なら質問する。

## Add

スクリプトはこの `SKILL.md` からの相対パスで解決する。まずプレビューを実行する。

```bash
python3 <skill-dir>/scripts/museum_events.py add \
  --group "美術展: 関東" \
  --title "展示名" --start 2026/08/15 --end 2026/10/12 \
  --venue "根津美術館"
```

正規化後のメモと希望する順序を確認する。ユーザーが作成を許可しており、プレビュー結果が曖昧でなければ、同一コマンドに `--apply` を付けて適用する。

```bash
python3 <skill-dir>/scripts/museum_events.py add \
  --group "美術展: 関東" \
  --title "展示名" --start 2026/08/15 --end 2026/10/12 \
  --venue "根津美術館" --apply
```

CLIは書き込み前に未完了の最上位タスクをすべて事前確認する。既存メモを解析できない、またはグループの順序がすでに不正な場合は、新規タスクを作成せず、先に整形skillで修復する。

## Position the Event

- 未完了の最上位タスクを、終了日、開始日の昇順で並べる。
- 同日のタスクは `task position` をタイブレーカーとして既存の相対順を維持し、新規タスクは既存の同日タスクの後ろに置く。
- 希望順で新規イベントの直前にある未完了タスクの安定IDを特定する。
- `add task ... after <previous-task-id>` で一度だけ作成する。先頭に置く場合は `after` を省略する。
- 作成後に `reorder task` を呼ばない。再取得して `task position` を辞書順に並べ、未完了タスク全体の順序を検証する。
- 完了済みタスクとサブタスクは編集しない。
- `task position` を取得できない場合は停止し、取得順へフォールバックしない。

作成したタスクID、最終タイトルとメモ、直前タスクIDまたは先頭配置、検証済みの最終位置を報告する。
