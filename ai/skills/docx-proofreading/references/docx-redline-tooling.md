# docx-redline and helper scripts

- `.docx` への実際の変更履歴・コメントの追加は、その場でPythonスクリプトを書かず、`pipx` で導入された `docx-redline` コマンド（実体は [y-marui/python-docx-redline](https://github.com/y-marui/python-docx-redline)）のサブコマンドで行う。`docx-redline inspect` で編集前の段落・既存コメント・変更履歴を確認し、既存変更履歴の承諾には `accept-revisions`、編集には `replace`（一致1件が既定、複数箇所は `--occurrence`/`--all`）、`replace-batch`（複数の置換をJSONでまとめて適用）、`replace-paragraph`、`insert-paragraph`、`add-comment`、`strip-comments`、`strip-format-revisions` を用いて編集し、納品前に `validate` で安全確認する。コメント・変更履歴の著者名は、実行中のコードエージェント名を `--author` で明示して用いる。名前を確認できない場合、汎用の既定名で記録せず、ユーザーに確認する。既存のコメント著者になりすましてはならない。
- `docx-redline inspect` のテキストに、図表キャプション等が同一段落内で2回連続して現れることがある（フロート画像・テキストボックスがアンカー段落に文字位置として重複反映されるため）。これは抽出結果の見かけ上の重複であり、本文の実際の重複とは限らない。編集前にレンダリングPDF（Wordでの`export-pdf`、または既存の同時点PDF）で実際の表示を確認してから、重複と誤認して削除・修正しない。
- `docx-redline` のサブコマンドで安全に表現できない編集（数式・コンテンツコントロール・フィールドをまたぐ置換など）だけ、その場限りの補助スクリプトを書いてよい。実行して検証に成功したコードは保存する。保存先は `<source-directory>/proofreading/scripts/<source-document-stem>/` とし、importの相対構造を維持する。作業開始時にディレクトリの有無を確認せず、保存が必要になった時点で作成する。同じ種類の欠落に繰り返し遭遇する場合は、使い捨てスクリプトを積み上げる代わりに `docx-redline` 側への機能追加（Issue・PR）を検討する。
- 補助スクリプトの一時ファイル・中間出力（レンダリングページ、途中生成物、検証用の一時DOCX等）は `<source-directory>/proofreading/cache/<source-document-stem>/` に保存する。スクリプトには再現に必要な入出力関係だけをコメントで示す。
- OOXMLで変更履歴を作る場合は、非衝突のIDと `w:ins` / `w:del` を使い、削除文字は `w:delText` に入れる。コメントを追加する場合は、既存のコメント著者になりすまさず、実行中のコードエージェント名を用いる。

## File layout and pre-edit inspection

- 原本を保持し、ソースディレクトリ直下には原本と `<stem>-proofread-<mode>-<YYYYMMDDHHMM>.docx` 形式の最終校正コピーだけを置く。作業途中のDOCX、レンダリングページ、Word/PDFの検証出力、変更履歴を承諾したレイアウト確認用コピーは、`<source-directory>/proofreading/cache/<source-document-stem>/` に置く。編集前に、既存のコメント・変更履歴、フィールド、数式、引用、脚注・文末脚注、コンテンツコントロール、リンク、ブックマーク、相互参照、保護領域、埋め込みオブジェクトを確認する。
