---
name: pptx-proofreading
description: "Modes: Light / Standard / Deep / Layout-Check. Proofread Microsoft PowerPoint (.pptx) slide text and speaker-note scripts while preserving deck content, comments, and memo boundaries. Add concrete correction proposals as PPTX comments and render every slide for visual verification. Use for PPTX proofreading or slide layout review; do not use for substantive claim changes."
---

# PPTX Proofreading

Microsoft PowerPoint (`.pptx`) のスライド本文と speaker note 内の発表原稿を、著者の意味と技術的意図を保ちながら校閲する。PPTXには安全で互換性のある変更履歴の経路がないため、明らかな言語上の修正を含め、既定では本文を直接編集せず具体的な修正案をコメントとして残す。

## Read the review context

レビューや編集の前に [../_proofreading-common/local-instructions.md](../_proofreading-common/local-instructions.md) を全文読み、`<fmt>` を `pptx` として適用する。加えて次を守る。

- ローカルルールが未検証の科学的または実質的な判断を要求する場合は、スライドとノートを保持して代わりにコメントへ具体案を入れる。

## PPTX safeguards and workflow

- 原本は保持し、ソースディレクトリ直下には原本と `<stem>-proofread-<mode>-<YYYYMMDDHHMM>.pptx` 形式の最終校正コピーだけを置く。作業途中のPPTX、コメント定義JSON、展開XML、PDF、レンダリングページ、検証出力は `<source-directory>/proofreading/cache/<source-deck-stem>/` に、再現に必要な補助スクリプトは `<source-directory>/proofreading/scripts/<source-deck-stem>/` に保存する。
- 編集前に、スライド、ノート、既存のコメント・スレッドコメント、リンク、埋め込みオブジェクト、図表、数式、カスタムXML、コメント関係を確認する。既存コメントを保持できると確認できない場合、コメントを追加する校正コピーを作らず、指摘一覧を返す。
- `.pptx` の調査とコメント追加は、その場でPythonやOOXML操作スクリプトを書かず `pptx-redline` で行う。コメントのアンカー指定・著者名（`--author` に実行中のコードエージェント名）・読み戻し・`validate` の手順は、編集前に [references/pptx-redline-workflow.md](references/pptx-redline-workflow.md) を全文読んで従う。
- 事実、科学、方法論、論理、数値、図表の解釈、主張の強さに関わる変更は、本文・ノートへ直接適用しない。コメントに「例」として修正案を示し、著者の専門的判断が必要であることを明記する。
- ユーザーが本文またはノート原稿への直接編集を明示的に依頼した場合だけ、原本を保持した校正コピーへ最小限の変更を行う。既存コメント・ノート境界・レイアウトを保持し、変更箇所と検証結果を報告する。
- PDF変換とスライドレンダリングにはMicrosoft PowerPointを使い、LibreOfficeは使わない。PowerPointを利用できない場合は、LibreOfficeへ切り替えずユーザーに相談する。
- PPTX操作・レンダリングでComputer Useを使わない。必要になった場合は、実行前に必要性を説明してユーザーの了承を得る。

## Speaker notes

speaker note を扱う（レビュー・コメント追加・保持確認）前に、[references/speaker-notes.md](references/speaker-notes.md) を全文読んで従う。既定は、発表原稿を先に置き、校閲対象外のメモを `--- メモ（校閲対象外） ---` 以降に置く形で、区切り以降のメモは一切レビュー・編集・引用しない。

## Cross-format review rules

レビュー前に、共通参照 [../_proofreading-common/review-principles.md](../_proofreading-common/review-principles.md) を全文読む。言語・文体の判定、意味・数値・引用の保護、各言語の校閲観点、著者判断を要する問題へのコメントは同参照を適用する。

## Select the mode

ユーザーが指定したモードを使う。モードが指定されていない場合は、校閲・編集を開始せず、次の1〜3から選択を確認する。`Layout-Check` は文章校閲の深さとは独立しており、1〜3に `+ Layout-Check` として明示的に組み合わせられる。レイアウト確認を暗黙に追加しない。

1. `Light`: 誤字脱字、文法、句読点、明らかに不自然な表現だけをコメントで指摘する。
2. `Standard`: Lightに加え、明瞭さ、簡潔さ、自然な表現、用語の一貫性をコメントで改善する。
3. `Deep`: Standardに加え、論理のつながり、曖昧さ、スライド間の構成、学術文体、読者が誤解しやすい点を確認する。事実関係・主張・論拠・方法・結論は、文書内の整合性、根拠の十分性、因果関係、目的との対応、引用・図表との対応をレビューする。意味、論拠、根拠、構成の変更を要する問題はコメントとして扱う。
  - `Deep` でスライド間の比較構成や新規手法の提示を確認する場合は、先に [references/deep-slide-comparison.md](references/deep-slide-comparison.md) を全文読んで適用する。
4. `Layout-Check`: スライド本文を編集せず、PPTXをPDFへ変換してPNGへレンダリングし、全スライドを視覚確認する。文字化け、フォント置換、文字・図表の欠け、重なり、はみ出し、コメント表示、余白、スライド番号を確認し、問題は位置と内容を報告する。LibreOfficeは使用しない。PowerPoint等のネイティブなアプリケーション自動化で変換・レンダリングできない場合は、その場で回避策を実装せず、対応手段が無い旨をユーザーに報告する。

`Deep` で科学的文書をレビューする場合は、対応する `references/<domain>.md` があれば追加で適用する。文書種別の判定に確信が持てない場合は、推測でファイルを選ばずユーザーに確認する。

## Verify and deliver

1. `pptx-redline list-comments` で追加コメントの件数・著者・アンカー種別を読み戻し、テキスト範囲のコメントが `shape_id` と正の `length` を、画像・図形へのコメントが意図した `object_id` を持つことを確認する。意図せず `shape_id`、`length`、`object_id` がすべて空のコメントはスライド全体へのコメントなので、コメント定義と一致しなければ作り直す。
2. `pptx-redline validate <output> --original <source>` でPPTX構造と原本内容の保持を検証する。
3. PDFへ変換し、PNGとして全スライドをレンダリングして1枚ずつ視覚確認する。コメントだけの追加なら、原本と出力コピーのスライド描画が同一であることも確認する。画像・図形コメントは、`inspect` のオブジェクト名とレンダリング上の対象を照合する。
4. 生成物が開け、スライド・コメント・ノートが読み取れることを確認する。原本が未変更であること、既存コメントが保持されたこと、speaker note の区切りとメモが保持されたことを確認する。可能な場合はPowerPointでも代表的なテキスト範囲コメントとオブジェクトコメントのマーカー位置を確認し、構造検証だけで表示位置を確認済みとしない。
5. 納品時に、使用モード、対象範囲、適用したローカル方針、出力コピー、コメント数、テキスト範囲・オブジェクト・スライド全体ごとの件数、既存コメントの扱い、ノート原稿の扱い、PDF/PNG確認範囲、PowerPointでの表示確認の有無、未解決事項を簡潔に報告する。

## Retain durable proofreading knowledge

校正作業の最後に永続的な知識を記録する場合は、先に [references/knowledge-retention.md](references/knowledge-retention.md) を全文読んで従う。
