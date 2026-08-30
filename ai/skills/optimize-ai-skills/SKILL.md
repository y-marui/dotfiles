---
name: optimize-ai-skills
description: "Audit and rewrite existing agent skills for lower context cost and clearer, behavior-preserving instructions. Use when the user asks to optimize, streamline, review, or consolidate the contents of SKILL.md files; do not use to create a new skill or change its intended behavior."
---

# Optimize AI Skills

既存の Agent Skill を、動作・権限・安全境界を保ったまま簡潔で判断しやすい内容にする。新規 skill の設計・作成は `skill-creator` を使う。

## Scope

- 対象はユーザーが指定した skill とその `SKILL.md`、`agents/openai.yaml`、そこから明示的に参照されるリソースだけ。対象がない場合は、候補を列挙して選択を求める。全件指定なら、skill ごとに独立して扱う。
- リポジトリ固有の skill 配置・記述言語・検証手順は、対象ディレクトリの近傍にある指示と README に従う。
- 新しい手順、外部操作、権限、ツール、出力形式、対象範囲を追加しない。作成済みのスクリプトや参照資料は、本文の最適化だけで不要と断定しない。

## Preserve the Contract

編集前に、対象から次を抽出する: 起動条件と除外条件、目的、入力、実行順序、変更可能な対象、確認が必要な操作、失敗時の停止条件、検証、報告内容。

- 冗長な説明の削除、重複の統合、見出しの整理、既存ルールの明文化は、契約を変えない範囲で直ちに編集できる。
- 起動条件、意味、実行順、権限、破壊性、出力契約、検証を変える提案は仕様変更として扱う。差分と影響を示し、編集前に承認を得る。
- 不明な記述は推測で補わない。必要な決定だけを質問する。

## Optimize

1. frontmatter の `description` は、何をする skill か、いつ使うか、誤って使われやすい隣接タスクとの境界だけを短く記す。
2. `SKILL.md` 本文には、実行判断を変える前提・制約・手順・検証だけを残す。一般的な助言、同義反復、過度な前置き、装飾、区切り線は削る。
3. 常に必要な情報は本文に置く。条件付きで長い手順・仕様・例は、実際に参照される場合だけ `references/` 等へ分け、本文から読む条件を明示する。
4. 箇条書きと短い命令文を優先する。用語、コマンド、パス、実UI文言は正確に維持する。

対象が扱う成果物に応じ、次の要素を既存の目的を変えない範囲で反映する。

- コード: 重複実装を避ける判断、必要な型定義、実装説明を最小限にする。
- 分析: 根拠と推論を区別し、客観的な比較・結論を構造化する。
- 書類: 対象の標準規約に従い、日本語の公用文では公用文の表記を優先し、Markdown指定時はMarkdownで出力する。

ユーザーが「書き換え案だけ」を求めた場合は、前置きなしで完成案を単一の Markdown コードブロックに入れる。ファイルを編集した場合は、通常の簡潔な変更・検証報告をする。

## Verify

- frontmatter と参照先を確認し、リンク切れや未使用の新規リソースを残さない。
- 対象の検証コマンドを実行する。dotfiles で管理する skill は `scripts/check-skills.sh` を使う。
- 変更内容、契約を維持したこと、実行した検証、承認待ちの仕様変更があればそれだけを報告する。
