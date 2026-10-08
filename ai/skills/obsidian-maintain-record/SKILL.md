---
name: obsidian-maintain-record
description: Proofread, restructure, or update existing Obsidian Records in records without changing their meaning. Use for existing Records; use obsidian-save-record for a new chat.
---

# Maintain Obsidian Record

会話Recordを作成・整備する場合は、対象vaultの`docs/conversation-record-format.md`を全文読み、全発話と保存時の補足・取得状態を区別する。Daily・Reviewには会話形式を強制しない。

## Target Files

- ユーザーが指定した既存Recordだけを対象にする。指定がなければ推測せず確認する。
- 対象は`records/`と、対象パスと目的が明示された`private/records/`に限定する。
- 旧`conversation_log/`の移行や整備には使わない。旧ノートは移行バッチまで既存の場所で保全する。

## Flow

- 対象RecordとVault規約を読み、意味、選択肢、棄却理由、合意、未決事項を保ったまま誤字や構造を整える。
- Recordは根拠層であるため、後知恵で結論を書き換えない。訂正や新しい解釈は追記するか、別のKnowledge・Decisionへリンクする。
- 外部タスク、予定、Issueの作成は、ユーザーが明示的に依頼した場合だけ行う。
- commitとpushは、ユーザーが明示的に依頼した場合だけ行う。

## Editing Rules

### Protected Tags

`#no-update` を含むファイルは校正・要約・再構成をせず、Git操作では現状のまま扱う。

### Conversation and Review Records

誤字脱字を直し、構造的な改善が見込める場合だけ読みやすく再構成する。会話Recordは独立行の`**USER:**`／`**AI:**`を使い、明白な誤字・書式だけを直す。発話や反復を省略・統合しない。原資料なしに要約を全文へ復元しない。

### Common Rules

- 文体は簡潔な「だ・である」調または体言止め。メッセージ、メール、対話文は元の敬体を維持する。
- 原文の敬称を保ち、ない敬称を追加しない。要約だけにせず、意味を保って文脈を補完する。
- 会話Recordでは保存時の追記・分析を元の発話へ統合せず、補足と明示する。他のRecordの「追記」「Append」「後日談」は本文の適切な位置へ統合する。コード、参考文献、`## Appendix`、`## 付録` は末尾の独立節として残す。
- 指示されない「まとめ」「考察」「追記」などの定型節を作らない。
- 対象Recordが参照する添付を、vaultの`docs/vault-architecture.md`の「添付ファイル」に合わせる。埋め込み画像は`<ノート名>-img/`、埋め込まない小さな参照ファイルは`<ノート名>-assets/`に置く。添付の移動は、依頼が添付の整理を明示的に許可している場合（定期実行の指示を含む）だけ、対象Recordが参照するものに限って`git mv`で行い、リンクのパスを同時に更新する（書式は変えない）。許可がない場合は、添付を動かさず規約外の配置を報告する。複数ノートが参照する添付、`posts/`、`private/`の外へ出る移動は、許可があっても動かさず報告する。

## Verify and report

変更後に対象を全文で読み返し、`git diff --check`と`git status --short`を確認する。変更したRecord、保持した意味、追記またはリンクした訂正、Git状態を簡潔に報告する。
