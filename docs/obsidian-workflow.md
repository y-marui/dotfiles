# Obsidian skill workflow

## Format ownership

会話Recordの外枠・全発話・補足・取得状態は対象vaultの`docs/conversation-record-format.md`、テンプレートは`system/templates/conversation.md`を正本とする。公開dotfilesには個人の会話内容・Privateの具体的ファイル名を記載しない。

## Skill responsibilities

- `project-update-documentation`: リポジトリの恒久文書を実装・合意済み方針と照合して更新する。技術docs、Project Homeの現在地・未決事項、GitHubの実装タスク、Tasks・Calendar等の責務を分ける。セッション終了処理は含めない。
- `obsidian-save-record`: 参照会話やダウンロードZIPから会話全文を保存する。
- `note-create-article-from-records`: 指定Recordから、背景・認識の変化・判断軸を伝える一般向けnote原稿を作る。重要な前提不足は執筆前に確認し、元Recordの変更やnoteへの投稿は含めない。
- `note-create-english-conversation-article`: 指定された英会話Recordから、noteの「今日の英会話」シリーズの復習教材下書きを作る。元発話を保つRecordと教材用の再構成を分け、noteへの投稿は含めない。対話用プロンプトはvaultの`system/prompts/english-conversation-trainer.md`に置く。
- `obsidian-save-knowledge`: 原資料のRecordを保持し、外部事実を検証して再利用可能な理解を整理する。
- `obsidian-save-project`: 原資料Recordから合意済み目的・現在地・次の行動を整理する。
- `obsidian-save-zotero`: ChatGPTの論文議論を、会話Record、論文deck（既定は`knowledge/research/papers/<citekey>.md`、Privateは`private/knowledge/research/papers/<citekey>.md`）、Zotero itemからのobsidian://リンクとして1回で保存する。Zotero操作は外部CLI（python-zotero-paper-tools）に委ね、会話Recordは`obsidian-save-record`の手順に従う。
- `obsidian-save-record-tarot`: Private会話と画像を保存し、学習ノートを保存時の補足として区別する。
- `obsidian-maintain-record`: 指定された既存Recordを原資料と意味を保って整える。原資料のない要約を全文に見せない。
- `obsidian-maintain-knowledge`: 既存Knowledgeを整理する。参照元Recordの全文を要約で上書きしない。
- `obsidian-maintain-record-review`: 通常領域の既定対象だけを校正し、Private・旧ログを除外する。

ZIP・JSONはDownloads等の一時的な原資料として扱い、vaultへ恒久複製しない。会話の取得状態と外部主張の正確さは別に検証する。形式変更は通常・Private・要約記録を小さく試用し、本文・添付・リンク・表示を確認してから広げる。

## Source ChatGPT archive

保存系スキルで会話Recordを残した場合は、依頼された成果物すべての保存・検証完了後に元ChatGPT会話を標準でアーカイブする。削除はしない。部分取得・欠落・照合未完了・保存失敗では実行しない。ユーザーのアーカイブ不要指定を優先する。対象同定・公式ツール・失敗時の報告は[共通のアーカイブ手順](../ai/skills/obsidian-save-record/SKILL.md#archive-the-source-chatgpt-conversation)に従い、過去の保存済み会話には遡及しない。

## ChatGPT source acquisition

保存系スキル（Record・Knowledge・Project・Tarot・Zotero）の原資料取得・照合は、[共通手順](../ai/skills/obsidian-save-record/references/exported-chat.md)を正本とする。提供済みZIP・展開済み資料を優先し、未取得なら`chatgpt-export capture ... --auto-start`で通常ブラウザの既存拡張を外部トリガーする。Computer Use・画面キャプチャ・マウス操作・手動エクスポートへ切り替えず、人への操作依頼はChatGPTログインだけとする。取得不能なら理由を報告して停止する。公式会話リーダーは不足の補完に使い、Codex task等は対応する公式リーダーを使う。取得レポートの内部メッセージ数・思考要約の要確認数と、保存すべき可視発話の件数・欠落を区別する。

Knowledge・Project・Tarot・Zoteroで会話Recordを作るときは、[obsidian-save-record](../ai/skills/obsidian-save-record/SKILL.md)を全文読み、共通の保存基準に従う。各skillは固有の保存先・補足・成果物だけを上書きし、取得手順やRecord形式を複製しない。形式の正本はvaultの`docs/conversation-record-format.md`である。

論文の議論の保存先は、公開済み論文（技術調査）なら通常領域（Record: `records/conversations/`、deck: `knowledge/research/papers/`）を既定とし、未公開の着想・原稿や所属機関の制限を含む場合、またはユーザーの指定がある場合はPrivate（`private/records/conversations/`、`private/knowledge/research/papers/`）にする。判断できなければ確認し、deckとRecordは同じ側に置く。

論文deckはMarpスライド（frontmatterに`marp: true`）として書き、表示にはコミュニティプラグイン Marp Inline Preview を使う。Marpは通常の文章・表を自動縮小しないため、1枚に入る分量にし、長い表・長文は複数スライドに分ける。論文deckでは、会話由来の原文紹介・著者の解釈と、AIの批判・研究案・ユーザー本人の着想を分ける。原論文に未照合の内容は未確認とし、人の確認までは`review_status: pending`を維持する。PDFへのページリンクは`paper-find --json`の`pdf_key`で作り、`null`なら未確認とする。図はZIP内のファイルに加えてMarkdownのdata URIも確認し、deckへ使う候補をユーザーが選ぶ。
