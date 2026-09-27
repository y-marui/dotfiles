---
name: docx-proofreading-handoff
description: "Hand off confirmed proofreading rules from conversation memory and current artifacts to durable project instructions, and preserve a folder-local handoff note so Word proofreading can resume accurately in another chat. Use when the user asks to record, hand off, or resume proofreading context; do not use for ordinary proofreading alone."
---

# Word Proofreading Handoff

校閲から得た情報と、必要に応じて会話メモリーに残っている校閲ルールを、次のチャットでも読める正本へ移す。対象文書そのものの内容や一時的な推測を会話メモリーへ保存する代わりに、再利用範囲ごとに記録先を分ける。

このskillは、校閲の完了時だけでなく、別チャットでの再開前や中断前にも使う。通常の校閲だけを依頼された場合は呼び出さない。

## Procedure

[../_proofreading-common/handoff.md](../_proofreading-common/handoff.md) を全文読み、`<fmt>` を `docx`、`<target>` を対象文書として適用する。

## Format-specific rules

- `PROOFREADING.docx.md` の追加対象: 変更履歴。
- `docx-proofreading/SKILL.md` の更新案に含める内容: DOCX固有の安全な編集不変条件、ツール利用手順。
- `proofreading/HANDOFF.md` に複製しない情報: 対象ファイル名・版・作業モード・変更履歴・コメント・進捗・次の作業。恒久ルールへ反映した後も、その規則だけでは分からない観測根拠または例外として有用ならHandoffに残す。
- 記録しない本文: 個別本文。不要な転載もしない。
- 追加の報告項目: なし。
