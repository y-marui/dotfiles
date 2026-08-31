---
name: word-proofreading-transfer
description: "Preserve confirmed proofreading rules and a folder-local handoff so Word proofreading can resume accurately in another chat. Use when the user asks to record, transfer, or resume proofreading context; do not use for ordinary proofreading alone."
---

# Proofreading Knowledge Transfer

校閲から得た情報を、次のチャットでも読める正本へ移す。対象文書そのものの内容や一時的な推測を会話メモリーへ保存する代わりに、再利用範囲ごとに記録先を分ける。

このskillは、校閲の完了時だけでなく、別チャットでの再開前や中断前にも使う。通常の校閲だけを依頼された場合は呼び出さない。

## Read the existing context

1. 対象文書、同階層の `PROOFREADING.md`、およびその先頭の有効な `@<relative-path>` 参照を読む。`@` 参照は `word-proofreading` と同じ規則で `$OBSIDIAN_ROOT/writing/<relative-path>` に解決する。
2. 同階層の `proofreading/HANDOFF.md` があれば読む。対象文書・版・更新時刻が今回の作業と一致するか確認し、一致しない内容を現在の指示や事実として扱わない。
3. ユーザーが明示した判断、実際に確認した文書状態、未解決事項を区別する。不明確な内容や既存ルールと競合する内容は、推測して記録先を決めず確認する。

## Choose the destination

| 情報の性質 | 記録先 |
| --- | --- |
| 特定文書・フォルダの用語、対象範囲、書式、レイアウト、著者が確定した判断 | 同階層の `PROOFREADING.md` |
| 科研費・論文・学会要旨など、複数案件で再利用し著者も更新する執筆・校閲知見 | 参照済みの `$OBSIDIAN_ROOT/writing/...` ガイド |
| 現在の対象ファイル、作業済み範囲、出力版、未解決コメント、次に確認する点 | 同階層の `proofreading/HANDOFF.md` |
| 文書横断の安全な編集不変条件、ツール利用手順、全案件共通の校閲手順 | `word-proofreading/SKILL.md` の更新案 |

`PROOFREADING.md` に `@` 参照がない場合、文書種別を推測してObsidianのガイドを新設・参照追加しない。再利用先が明確なら候補パスを提案し、ユーザーの判断を得る。

## Transfer procedure

1. 既存の正本を検索して重複・競合を避け、確定した情報だけを最小限追記する。既存の指示を上書き・要約して失わせない。
2. `PROOFREADING.md` とObsidianガイドには、今後も判断を変える規則だけを書く。今回の作業量、途中経過、個別本文、未確定の解釈は入れない。
3. `proofreading/HANDOFF.md` には、対象ファイルの相対名または絶対パス、基準にした版、作業モード、確認済み範囲、生成物、未解決のアンカーコメントまたは確認事項、次の安全な作業を簡潔に記録する。更新時刻を付け、解決済みの進捗は最新状態へ置き換える。手順書や一般規則を複製しない。
4. 認証情報、個人情報、本文の不要な転載、推測、会話内だけの指示を記録しない。科学的事実・結論・根拠を新たに確定したように書かない。
5. すべての案件で有用になり得る規則を見つけた場合は、`word-proofreading/SKILL.md` の更新候補を、根拠・追加先・短い文案とともに報告する。このskillからは `SKILL.md` を自動編集しない。

## Completion report

更新したファイル、何をどの範囲で引き継げるようにしたか、残る確認事項を報告する。スキル更新候補がある場合は、提案であることを明確にし、採否をユーザーに委ねる。
