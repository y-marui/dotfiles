---
name: docx-proofreading
description: "Modes: Light / Standard / Deep / Deep-Auto / Layout-Check. Proofread multilingual text or Microsoft Word (.docx) documents with minimal meaning-preserving edits, tracked-change safeguards, and optional Word-based layout verification. Use for proofreading, copyediting, or Word layout review; do not use for translation or substantive changes to facts, scientific claims, or conclusions."
---

# Word Proofreading

単一言語または多言語の文章を、著者の意味と技術的意図を保ちながら校正する。正確さまたは読みやすさを明確に改善する、最小限の編集を優先する。

## Local proofreading instructions

レビューや編集の前に [../_proofreading-common/local-instructions.md](../_proofreading-common/local-instructions.md) を全文読み、`<fmt>` を `docx` として適用する。加えて次を守る。

- 明示されたローカルの対象範囲、組版、用語方針に従う。ローカルルールが未検証の科学的または実質的な判断を要求する場合は、本文を保持して代わりにアンカー付きコメントを付ける。
- 特別な範囲指定がない限り、変更履歴の有無にかかわらず、ローカルルールと依頼で対象となる文書全体を確認する。既存の変更履歴がある箇所だけをレビュー対象に限定しない。

## Word document safeguards

`.docx` の校正では、次を守る。

- Wordでのページ数・組版の確認、macOSのWord自動化、フォント埋め込みが関わる場合は、先に [references/word-layout-verification.md](references/word-layout-verification.md) を全文読んで従う。
- 編集経路は、既存の変更履歴・コメントを保持できる公式のWord接続、ローカルDOCXのOOXML変更履歴、レビューのみの順に選ぶ。意図した変更すべてを安全に表現できない場合、原本を上書きしたり未記録の本文編集を納品したりせず、修正案またはレビュー報告に留める。クリーンな書き直し版はユーザーが明示的に求めた場合だけ作成する。
- 原本・最終校正コピー・作業中ファイル（cache）の配置と、編集前に確認する文書要素は、編集前に読む [references/docx-redline-tooling.md](references/docx-redline-tooling.md) の「File layout and pre-edit inspection」に従う。
- レビューまたは校正を始める前に、既存の変更履歴を確認して変更前後をレビュー上の参考として把握する。その後、ユーザーが別途指示しない限り、原本を保持したまま校正コピー内の既存の変更履歴をすべて承諾して、承諾後の本文を基準にレビューを進める。既存コメントは保持する。承諾済みの作業コピーを安全に作れない場合は、本文を編集せずユーザーへ制約を伝える。
- 本文の各修正は、最小かつ安全な実際のWord変更履歴として記録する。周辺の書式、リンク、フィールド、ブックマーク、文書構造を保持し、分離した修正を段落全体の置換にまとめない。互換しないrun、保護されたアンカー、複雑なフィールド、数式、文献オブジェクト、コンテンツコントロールを安全に編集できない場合は変更しない。
- 科学的・事実的・方法論的な判断、主張の変更、根拠の不足、大きな再構成、解釈の曖昧さには未記録の本文編集をせず、必要に応じてアンカー付きコメントを使う。
- 文字数・ページ数を減らすことだけを目的に、段落、主張、例、図表説明などの取捨選択を伴う大幅な短縮を適用しない。`Deep-Auto` を含む全モードで、短縮の必要性、対象箇所、著者による重要度判断が必要な理由をアンカーコメントに残し、人間が優先順位を確認してから本文更新を依頼できるようにする。
- `.docx` への変更履歴・コメントの追加と補助スクリプトの扱いは、編集前に [references/docx-redline-tooling.md](references/docx-redline-tooling.md) を全文読んで従う（`docx-redline` のサブコマンドを使い、その場でPythonスクリプトを書かない。コメント・変更履歴の著者名は実行中のコードエージェント名にする）。
- 納品前に、出力が開けてレンダリングできること、今回の編集がWordの変更履歴として表示・受諾・却下可能なこと、既存のレビュー状態が依頼どおり保持または処理されたこと、保護対象が原本と一致すること、原本が未変更であることを確認する。確認できない項目は成功として扱わず、制約を明記する。

## Retain durable proofreading knowledge

校正作業の最後に、永続的な知識を記録する場合は、先に [references/knowledge-retention.md](references/knowledge-retention.md) を全文読んで従う。

## Select the mode

ユーザーが指定したモードを使う。モードが指定されていない場合は、校閲・編集を開始せず、次の1〜4から選択を確認する。`Layout-Check` は文章校正の深さとは独立しており、1〜4に `+ Layout-Check` として明示的に組み合わせられる。レイアウト確認を暗黙に追加しない。

1. `Light`: 誤字脱字、文法、句読点、明らかに不自然な表現だけを修正する。任意の文体変更はしない。
2. `Standard`: Lightの修正に加え、明瞭さ、簡潔さ、自然な表現、用語の一貫性を改善する。
3. `Deep`: Standardの修正に加え、論理のつながり、曖昧さ、段落構成、学術文体、読者が誤解しやすい点を確認する。さらに、本文中の事実関係・主張・論拠・方法・結論について、文書内の整合性、根拠の十分性、因果関係、文書の目的との対応、引用・図表との対応をレビューする。意味、論拠、根拠、構成の変更を要する問題は、編集ではなくコメントとして扱う。
4. `Deep-Auto`: `Deep` と同じ文章・内容レビューを行うが、著者の判断を必要とせず意味を変えずに一意に直せるもの（曖昧な指示語の解消、接続の補強、段落の入れ替えなど）は、コメントに留めず実際のWord変更履歴として直接適用する。事実・主張・論拠の当否・根拠の十分性・大きな再構成の要否など、著者の判断が必要な問題は `Deep` と同様に本文を変更せずコメントのまま残す。共通の意味保護は、モードによらず常に適用する。
5. `Layout-Check`: `.docx` を編集せず、全ページを視覚確認して報告する。手順と確認項目は [references/word-layout-verification.md](references/word-layout-verification.md) の「Layout-Check mode」に従う。

`Deep` と `Deep-Auto` で本文中の主張・論拠・方法・結論を確認する際、対応する `references/<domain>.md` があれば追加で適用する。現時点では、研究論文・学位論文・研究計画書・研究報告書などの科学的文書向けに [references/science.md](references/science.md)、装置・ソフトウェアマニュアルなどの操作・手順文書向けに [references/manual.md](references/manual.md) がある。専用の参照ファイルがない文書種別では、この節までの一般的な観点だけを適用し、独自の観点をその場で作らない。文書種別の判定に確信が持てない場合は、推測でファイルを選ばずユーザーに確認する。

`Deep-Auto` の構造レビューの完了基準は、`Deep-Auto` を実行する前に [references/deep-auto-structure.md](references/deep-auto-structure.md) を全文読んで従う。

## Cross-format review rules

レビュー前に、共通参照 [../_proofreading-common/review-principles.md](../_proofreading-common/review-principles.md) を全文読む。言語・文体の判定、意味・数値・引用の保護、各言語の校閲観点、著者判断を要する問題へのコメントは同参照を適用する。Wordの変更履歴とコメントの実装手順は、このskillのWord固有保護策を優先する。

## Produce the result

貼り付けテキストまたはプレーンテキストファイルでは、次を行う。

1. 段落とリスト構造を保った校正後テキストを先に返す。
2. 著者の判断または内容上の懸念が残るときだけ、簡潔な `Comments / 指摘` セクションを追加する。
3. 詳細な変更一覧または左右比較は、ユーザーが求めた場合だけ示す。

`.docx` またはWord文書では、上記のWord文書保護策に従い、利用可能な安全な変更履歴・コメント手順とインストール済みの文書アーティファクト手順で、レンダリングと検証を行う。`Layout-Check` では、確認したページ数、視覚確認の範囲、フォント検出結果、未解決のレイアウト上の懸念を報告する。

納品時に、使用したモードと未解決の制約を明記する。Word文書では、変更が実際のWord変更履歴か、使用した編集経路、既存の変更履歴を確認後に校正コピーで承諾したこと、および既存コメントを保持したかを明記する。`Deep-Auto` では、どの指摘を編集として自動適用し、どれを著者判断のためコメントに残したかも簡潔に明記する。
