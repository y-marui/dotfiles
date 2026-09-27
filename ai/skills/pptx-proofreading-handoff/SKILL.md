---
name: pptx-proofreading-handoff
description: "Hand off confirmed PowerPoint proofreading rules and deck-review state to durable project instructions, and preserve a folder-local handoff note so PPTX proofreading can resume accurately in another chat. Use when the user asks to record, hand off, or resume PPTX proofreading context; do not use for ordinary proofreading alone."
---

# PPTX Proofreading Handoff

PPTX校閲から得た情報と、必要に応じて会話メモリーに残っている校閲ルールを、次のチャットでも読める正本へ移す。対象デッキの本文やspeaker note全文を会話メモリーへ保存する代わりに、再利用範囲ごとに記録先を分ける。

このskillは、校閲の完了時だけでなく、別チャットでの再開前や中断前にも使う。通常のPPTX校閲だけを依頼された場合は呼び出さない。

## Procedure

[../_proofreading-common/handoff.md](../_proofreading-common/handoff.md) を全文読み、`<fmt>` を `pptx`、`<target>` を対象デッキとして適用する。

## Format-specific rules

- `PROOFREADING.pptx.md` の追加対象: コメント方針、speaker note境界。
- `pptx-proofreading/SKILL.md` の更新案に含める内容: PPTX固有の安全な編集不変条件、コメント・レンダリング・検証手順。
- `proofreading/HANDOFF.md` に複製しない情報: 対象ファイル名・版・作業モード・コメント数・既存コメントの扱い・speaker note境界の扱い・PDF/PNG確認範囲・進捗・次の作業。
- 記録しない本文: 個別スライド本文、speaker note全文。不要な転載もしない。
- 追加の報告項目: デッキ原本・校正コピー・コメント数・speaker note境界・PDF/PNG確認の状態をどこに記録したか。
