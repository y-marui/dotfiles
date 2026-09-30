---
name: obsidian-update-conversation-log
description: Proofread and update existing Daily or Conversation records in an Obsidian vault while preserving meaning and current vault policy. Use for requested record cleanup and, only when explicitly requested, migration of action tasks to Google Tasks; do not use for new chat capture or Knowledge extraction.
---

# Obsidian Update Conversation Log

既存のDailyまたはConversation Recordを、意味と判断経緯を失わず校正・更新する。
新規チャットの保存、Knowledgeへの昇格、Vault全体の一括再構成には使わない。

## Scope and authorization

- 対象vaultの`README.md`、`AI_CONTEXT.md`、Home、Records・Private・移行に関する正本文書を、
  定められた順序で読む。vault側の保存先、形式、安全規則を本skillの既定値より優先する。
- ユーザーが指定したファイルだけを対象にする。フォルダまたは期間が指定された場合は、変更前に
  対象一覧、件数、処理内容、検証方法を提示する。対象が不明な場合は、Privateを除外した候補一覧だけを
  作り、選択を得るまで本文を読んだり変更したりしない。
- `private/**`とvaultが指定する移行前Private対象を通常探索から読み取り前に除外する。
  ユーザーがPrivateの対象パスと目的を明示した場合だけ、その範囲を読む。
- `#no-update`を含むファイルは、ユーザーがそのファイルを明示し、タグを解除または今回だけ更新する
  意図を確認した場合を除いて変更しない。
- 校正依頼は対象ファイルの保存を許可するが、移動、削除、Knowledge抽出、外部タスク作成、commit、
  pushを許可したとは扱わない。それぞれ明示された場合だけ行う。
- dirty worktreeの既存変更を保全し、開始時点の変更と自分の変更を区別する。

`origin/ai/review`との差分やフォルダ全体を既定の対象にしない。自動commit・自動pushは行わない。

## Preserve the record

- 誤字脱字、音声認識の明白な誤り、重複した相槌、読点・段落を整えてよい。
- 発言者、時系列、断定の強さ、感情、条件、候補、棄却理由、合意、未決事項を変えない。
- 会話にない診断、評価、結論、アクション、研究アイデアを追加しない。
- 「追記」「Append」「後日談」は、時点の違いが失われない形で適切な位置へ統合する。
- コード、参考文献、`Appendix`、`付録`は独立節として残す。
- 外部情報を最新化する依頼でない限り、その時点の記録を現在情報へ書き換えない。
- RecordsをAI要約で置換しない。大幅な圧縮や構成変更が必要なら、先に変更案を提示する。

## Respect current and legacy formats

### Current Daily

`records/daily/`のDailyは、既存構造を尊重しつつ、必要な見出しだけを次から使う。

1. Focus
2. Timeline / Log
3. Decisions
4. Carryovers
5. Reflection

空の見出しを埋める義務はない。継続タスクの正本をDailyへ移さず、その日の実行履歴だけを残す。

### Current Conversation

`records/conversations/`のConversationは、必要に応じて次を使う。

1. Summary
2. Participants / Source
3. Related context
4. Faithful transcript or detailed record
5. Extracted Knowledge / Decisionsへのリンク

読みやすく直しても、意味、選択肢、棄却理由、合意、未決事項を失わせない。

### Legacy records

`conversation_log/`等の既存Legacyファイルは、その場所と基本形式を維持する。今回の依頼が
移行でない限り、`records/`へ移動・複製したり、現行テンプレートへ全面変換したりしない。
Legacy Dailyの「タスク」「予定」「課題」等は、既存内容の意味を保って校正できるが、全ファイルへ
一律に追加・並べ替えしない。

## Google Tasks migration

日次ログからGoogle Tasksへの移管は、ユーザーが今回明示した場合だけ行う。

- 時刻が決まった予定はGoogle Calendar、コード・実装を伴うタスクはGitHub、先送りするメモや
  アイデアはObsidianで扱い、それ以外の継続タスクだけをGoogle Tasks候補にする。
- 作成前にGlance Taskから移管先と既存タスクを取得し、同一の未完了タスクがないか確認する。
- 移管先が明示されていない場合は、候補と移管先を提示し、外部作成前に確認する。無人実行であっても
  承認を推測せず、作成を保留する。
- 作成後はタイトル、未完了状態、安定タスクIDを再取得して確認する。
- Google TasksのWeb URLに依存せず、関連RecordにはGlance Taskで確認した安定IDを記録する。
- `#no-update`を含むファイルから外部タスクを作成しない。

## Verify and report

1. 更新したファイルを全文読み返し、原文と照合する。
2. 対象外ファイル、Private、`#no-update`、添付、内部リンクが意図せず変わっていないことを確認する。
3. `git diff --check`と`git status --short`を実行し、先行変更と自分の変更を区別する。
4. 外部タスクを作成した場合は、作成先、タイトル、安定ID、検証結果を報告する。
5. 更新ファイル、主な校正内容、保持したLegacy形式、未確認事項、Git状態を簡潔に報告する。

commitとpushは、ユーザーが明示的に依頼した場合だけ行う。
