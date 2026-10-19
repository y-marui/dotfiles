# Retain durable proofreading knowledge

校正作業の最後に、作業中に得た永続的で判断に関わる知識だけを記録する。

- 新たな安全な編集不変条件や再利用可能なレビュー原則など、DOCXとPPTXに共通する規則は `../_proofreading-common/review-principles.md`（skillルート基準。このファイルからは `../../_proofreading-common/review-principles.md`） に追加する。DOCXだけの作業規則は親の `SKILL.md`（`../SKILL.md`）に追加する。
- 特定の文書種別(科学的文書など)だけに関わる内容レビューの観点は skillルートの `references/<domain>.md`（このディレクトリ内の `<domain>.md`）に追加する。該当ファイルがなければ、観点の内容を確認したうえで新設する。適用の判定は対象文書の内容に基づき、`PROOFREADING.md`の有無や`@`参照の設定には依存しない。
- 文書またはフォルダ固有の用語、対象範囲、レイアウト、組版規則は、共通なら同階層の `PROOFREADING.md`、DOCXだけなら `PROOFREADING.docx.md` に追加する。
- 特定の申請制度・文書種別・研究分野にまたがる、著者も参照・更新する知見は Obsidian の `system/templates/outputs/` 配下の執筆・校閲ガイドに記録し、該当フォルダの `PROOFREADING.md` の先頭から `@<relative-path>` で必要な場合だけ明示参照する。skillや案件フォルダへ複製しない。
- コンテキストの記録・引き継ぎをユーザーが依頼した場合は、`docx-proofreading-handoff` に従う。
- 一回限りの文書内容、一時的な作業状態、推測的な結論、今回だけに限定されたユーザー指示を永続化しない。
- 明示的なユーザー判断と推論を区別する。ユーザーが推論の保持を求めない限り、前者だけを記録する。
