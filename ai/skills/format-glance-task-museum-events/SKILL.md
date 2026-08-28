---
name: format-glance-task-museum-events
description: "Audit, format, normalize, or reorder existing exhibition tasks in Glance Task's 「美術展: 関東」 and 「美術展: 東北」 groups through AppleScript, always checking unfinished tasks in both groups first. Use for canonicalizing exhibition titles, periods, or venues; finding format deviations; or restoring unfinished tasks to position order. When invoked without a target, repair every unambiguous finding in both groups without asking for confirmation. Do not use for creating a new exhibition task."
---

# Format Glance Task Museum Events

同梱CLIとGlance TaskのAppleScriptコマンドで、既存の美術展を監査・整形する。タスクは安定IDで識別し、表示順には `fetch tasks` の配列順ではなく `task position` を使う。

## Proceed Without Confirmation

- 整形、正規化、修復、並べ替えの依頼は、要求された変更を適用する許可として扱う。事前確認やプレビュー後に確認待ちで止めない。
- タスクやより狭い対象が指定されない場合は、両グループで見つかった曖昧でない書式・順序の問題をすべて修復する。
- 必ず適用しないプレビューを内部で実行し、結果が曖昧でなければ同一の `--apply` コマンドを直接続けて実行する。
- ユーザーが監査、確認、チェック、プレビューのみを明示した場合は変更しない。
- 完全な日付と会場を特定できない不正なメモ、完全一致タイトルの重複、安定IDの欠落など、必須データが不足または曖昧な場合だけ質問する。推測しない。
- タスク指定の依頼が許可するのは、そのタスクと同一グループの順序修復だけである。依頼が全件対象でない限り、無関係な書式問題は修復しない。

## Start With Both-Group Preflight

タスクを選択または整形する前に、必ず両方の美術展グループを取得・監査する。

```bash
python3 <skill-dir>/scripts/museum_events.py preflight
```

- `美術展: 関東`、次に `美術展: 東北` の未完了最上位タスクをすべて確認する。
- メモが正規の期間・会場書式に従うか確認する。
- `task position` を辞書順に並べ、終了日・開始日の順序と比較して並びを確認する。
- 許可済みの作業を続けながら、書式変更、書式エラー、並べ替えの必要性を報告する。確認を求めるためだけに停止しない。
- タスク指定の依頼では、別グループの問題は参考情報として扱い、変更しない。対象未指定なら、両グループの曖昧でない問題をすべて修復する。
- いずれかのグループを取得できない、または `task position` がない場合は停止する。失敗したグループをスキップしない。

`format` コマンドは同じ両グループ事前確認を内部で行い、プレビューと適用結果に含める。AppleScriptを直接呼び出して回避しない。

## Resolve the Existing Task

事前確認後、安定IDを特定する必要があれば、対象グループを実際の位置順で一覧する。

```bash
python3 <skill-dir>/scripts/museum_events.py list --group "美術展: 東北"
```

- 変更対象は `美術展: 関東` と `美術展: 東北` に限定する。
- 完全一致のタイトルから安定タスクIDを特定する。部分一致は使わない。完全一致タイトルが重複する場合は質問する。
- ユーザーが変更を求めない限り、省略された項目と末尾の既存ステータス絵文字を保持する。
- サブタスクを美術展として整形しない。

## Format

タイトルには展示名を入れる。メモには半角スペース1つと月日2桁表記を使い、厳密に `<period> <venue>` を入れる。

```text
1日開催         YYYY/MM/DD 会場
同月開催        YYYY/MM/DD-DD 会場
同年開催        YYYY/MM/DD-MM/DD 会場
年またぎ開催    YYYY/MM/DD-YYYY/MM/DD 会場
```

終了日が開始日より前なら受け付けない。既存メモが不正なら、不足項目を推測せず、完全な開始日、終了日、会場を要求する。

## Format a Selected Task

まず `--apply` を付けずに対象コマンドを実行する。

```bash
python3 <skill-dir>/scripts/museum_events.py format \
  --group "美術展: 東北" --task-id "<task-id>" \
  --start 2027/01/30 --end 2027/01/31 \
  --venue "せんだいメディアテーク"
```

変更前後の正確な値と希望順を内部で確認する。ユーザーが監査またはプレビューのみを依頼していない限り、結果が曖昧でなければ同一コマンドに `--apply` を付けて直ちに再実行し、確認を求めない。変更しない項目は省略する。項目を一切指定しない場合は、選択タスクの既存メモを正規化して順序を修復する。

## Format Every Finding

対象が指定されない場合:

1. 必須の事前確認を実行し、両グループの `format_changes` にある全項目を収集する。
2. 各安定タスクIDについて、`--apply` なしで `format` を実行し、変更前後の正確な値を確認してから、同一コマンドに `--apply` を付けて停止せずに実行する。変更は順番に処理する。
3. グループが引き続き `needs_reorder` を返す場合は、`sort --group <group> --apply` を実行する。
4. 再度 `preflight` を実行する。両グループで `format_changes` と `format_errors` がなく、`needs_reorder` が false になった時点で完了する。そうでなければ、正確な曖昧なブロッカーを報告する。

Glance Taskは、並べ替え直後に更新済みの `task position` を返すことがある。直後の検証で不一致が出た場合は、失敗と判断する前にグループを再取得する。再取得した監査でも並べ替えが必要なら、`sort` は1回だけ再試行する。

## Audit or Repair One Group

特定の問題を調査する場合に限り、必須の両グループ事前確認後に1グループのみを監査する。

```bash
python3 <skill-dir>/scripts/museum_events.py audit --group "美術展: 関東"
```

順序のみを修復する場合:

```bash
python3 <skill-dir>/scripts/museum_events.py sort \
  --group "美術展: 関東" --apply
```

- 未完了の最上位タスクを、終了日、開始日の昇順で並べる。
- 同日のタスクは `task position` をタイブレーカーとして既存の相対順を保持する。
- 完了済みタスクとサブタスクは編集しない。
- `reorder task ... after ...` で並べ替え、再取得して `task position` を辞書順に並べて検証する。
- 未完了タスクを解析できない、または `task position` を取得できない場合は停止し、取得順へフォールバックしない。

タスクID、タイトルとメモの正確な変更前後、および並べ替えの有無を報告する。このskillで新規タスクを作成しない。作成依頼は `add-glance-task-museum-event` skill へ引き継ぐ。
