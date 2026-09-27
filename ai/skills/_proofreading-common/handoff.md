# Proofreading handoff procedure (DOCX / PPTX)

DOCX と PPTX の校閲引き継ぎで共通する手順。`<fmt>` は `docx` または `pptx`、`<target>` は対象文書（DOCX）または対象デッキ（PPTX）を指す。形式固有の項目は各skillの「Format-specific rules」に従う。

## Read the existing context

1. `<target>`、同階層の `PROOFREADING.md`、`PROOFREADING.<fmt>.md`、および `PROOFREADING.md` 先頭の有効な `@<relative-path>` 参照を読む。`@` 参照は `<fmt>-proofreading` と同じ規則で `$OBSIDIAN_ROOT/writing/<relative-path>` に解決する。`PROOFREADING.<fmt>.md` 内の `@` 行は外部参照にしない。
2. 同階層の `proofreading/HANDOFF.md` があれば、既存の正本へ直接反映するか保留している観測・不具合兆候・暫定回避策だけを再開時の補助情報として読む。現在の`<target>`状態と矛盾する内容は使わない。
3. ユーザーが会話メモリーの移管を明示的に依頼した場合だけ、`MEMORY.md` の対象項目を読む。Memoryは移管候補を見つける補助であり、正本ではない。無関係な項目や一時的な内容を横断して移さない。
4. ユーザーが明示した判断、実際に確認した`<target>`の状態、未解決事項を区別する。不明確な内容や既存ルールと競合する内容は、推測して記録先を決めず確認する。

## Choose the destination

| 情報の性質 | 記録先 |
| --- | --- |
| DOCX・PPTXの両方に関わる特定文書・フォルダの用語、対象範囲、書式、レイアウト、著者が確定した判断 | 同階層の `PROOFREADING.md` |
| `<fmt>` だけに関わる特定文書・フォルダの用語、組版、著者が確定した判断（追加の対象項目は Format-specific rules） | 同階層の `PROOFREADING.<fmt>.md` |
| 科研費・論文・学会要旨など、複数案件で再利用し著者も更新する執筆・校閲知見 | 参照済みの `$OBSIDIAN_ROOT/writing/...` ガイド |
| 既存の正本への反映を保留する、skill・ツール・処理経路の不具合兆候、観測結果、暫定回避策 | 同階層の `proofreading/HANDOFF.md` |
| DOCX・PPTX共通の安全な編集不変条件、言語・内容レビュー原則 | `_proofreading-common/review-principles.md` の更新案 |
| `<fmt>` 固有の安全な編集不変条件と手順（内容は Format-specific rules） | `<fmt>-proofreading/SKILL.md` の更新案 |
| 特定の文書種別だけに関わる、案件・著者に依存しない内容レビューの観点 | `<fmt>-proofreading/references/<domain>.md` の更新案 |
| 移管後に残す必要のない会話メモリーの校閲ルール | `/Users/yuki/.codex/memories/extensions/ad_hoc/notes/` に更新ノートを追加し、`MEMORY.md` の削除または更新を依頼する |

`PROOFREADING.md` に `@` 参照がない場合、文書種別を推測してObsidianのガイドを新設・参照追加しない。再利用先が明確なら候補パスを提案し、ユーザーの判断を得る。

## Handoff procedure

1. まず`<target>`、`PROOFREADING.md`、`PROOFREADING.<fmt>.md`、参照済みのObsidianガイド、skillを確認し、反映先が明確な情報は重複・競合を避けて最小限追記する。既存の指示を上書き・要約して失わせない。
2. Memory移管を依頼された場合は、対象項目ごとに恒久的な規則だけを抽出し、先に適切な正本へ反映する。反映後に不要になったMemory項目は、ユーザーが明示的に更新・削除も依頼した場合だけ、小さな更新ノートで削除または更新を依頼する。`MEMORY.md` 自体を直接編集しない。
3. `PROOFREADING.md`、`PROOFREADING.<fmt>.md` とObsidianガイドには、今後も判断を変える規則だけを書く。今回の作業量、途中経過、個別の本文、未確定の解釈は入れない。
4. `proofreading/HANDOFF.md` には、正本へ直接反映するか迷う観測だけを短く記録する。Format-specific rules に挙げた項目など、`<target>`、skill、`PROOFREADING.md`、`PROOFREADING.<fmt>.md`、参照済みObsidianガイドから分かる内容は複製しない。skill・ツール・処理経路の不具合または非互換の兆候では、観測された差異、試した暫定回避策、未確定の点だけを残す。
5. 認証情報、個人情報、本文の不要な転載、推測、会話内だけの指示を記録しない。科学的事実・結論・根拠を新たに確定したように書かない。
6. すべての案件で有用になり得る規則を見つけた場合は、DOCX・PPTX共通なら `_proofreading-common/review-principles.md`、`<fmt>` 固有なら `<fmt>-proofreading/SKILL.md`、特定の文書種別だけに関わる観点なら `<fmt>-proofreading/references/<domain>.md` の更新候補を、根拠・追加先・短い文案とともに報告する。ユーザーが変更まで明示的に依頼した場合だけ、対象ファイルを更新して検証する。それ以外は提案に留める。

## Completion report

更新したファイル、何をどの範囲で引き継げるようにしたか、Memoryの更新ノートを作成したか、残る確認事項、および各skillが定める追加の報告項目を報告する。スキル更新候補がある場合は、提案であることを明確にし、採否をユーザーに委ねる。
