# Obsidian skill workflow

## Format ownership

会話Recordの外枠・全発話・補足・取得状態は対象vaultの`docs/conversation-record-format.md`、テンプレートは`system/templates/conversation.md`を正本とする。公開dotfilesには個人の会話内容・Privateの具体的ファイル名を記載しない。

## Skill responsibilities

- `obsidian-save-record`: 参照会話やダウンロードZIPから会話全文を保存する。
- `obsidian-save-knowledge`: 原資料のRecordを保持し、外部事実を検証して再利用可能な理解を整理する。
- `obsidian-save-project`: 原資料Recordから合意済み目的・現在地・次の行動を整理する。
- `obsidian-save-record-tarot`: Private会話と画像を保存し、学習ノートを保存時の補足として区別する。
- `obsidian-maintain-record`: 指定された既存Recordを原資料と意味を保って整える。原資料のない要約を全文に見せない。
- `obsidian-maintain-knowledge`: 既存Knowledgeを整理する。参照元Recordの全文を要約で上書きしない。
- `obsidian-maintain-record-review`: 通常領域の既定対象だけを校正し、Private・旧ログを除外する。

ZIP・JSONはDownloads等の一時的な原資料として扱い、vaultへ恒久複製しない。会話の取得状態と外部主張の正確さは別に検証する。形式変更は通常・Private・要約記録を小さく試用し、本文・添付・リンク・表示を確認してから広げる。
