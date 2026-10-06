# dev-charter Install Checklist (lite)

> **このファイルは正本（日本語）と参照版（英語）を併記しています。**
> **This file contains the canonical Japanese text followed by the reference English text.**

## Japanese

`git subtree add`（`lite` ブランチ）で dev-charter をインストールした後、以下のプロンプトを AI に貼り付けて実行してください。

> **重要:** `docs/dev-charter/` 配下のファイルを直接編集しないこと。変更が必要な場合は dev-charter リポジトリに Issue を立て、`git subtree pull` でアップデートを取り込む。プロジェクト固有のルールはプロジェクトの `AI_CONTEXT.md` または専用ファイルに記載すること。

### Step 1 — Bulk Setup

```
docs/dev-charter/ 内の全ファイルを読み、このプロジェクトを調査した上で、以下を実施してください。

1. docs/dev-charter/AI_TOOL_SETUP.md の仕様に従い AI コンテキストファイルをセットアップする
2. 憲章の要件とプロジェクトの現状を照合し、未対応箇所をすべて特定・修正する
   （ファイル構成・CI・セキュリティ・コーディング規約など、プロジェクト全体を対象とする）
3. docs/dev-charter/topics/GITHUB_SETTINGS.md を読み、すべてのリポジトリ設定を適用する
   （gh コマンドが使える場合はコマンドで、使えない場合は GitHub UI から設定する）
4. docs/dev-charter/topics/CI_POLICY.md を読み、.github/workflows/ を確認・整備する
   （lite は main への直接pushを許可する運用のため、Branch Protection の内容は
   このファイルのものに従うこと。full 版の内容と混同しないこと）

- README.md・README-jp.md の構成に定型のガイドラインは無い（lite にはfull版の
  PROJECT_README_GUIDELINES.md が含まれない）。既存の慣習に従うか、無ければ
  プロジェクト概要・セットアップ手順を含む一般的な構成で作成する
- 不明点・確認事項は作業前に 1 回まとめて質問する
- 憲章と既存規約が矛盾する場合は矛盾点を列挙し、優先順位をユーザーに確認してから進める
- 大きなスコープになる場合は修正前にユーザーに確認する
- 完了後はコミットしない（ユーザーが確認してから行う）
```

### Step 2 — File-by-File Review

```
docs/dev-charter/ 内の各ファイルを1つずつ読み直し、プロジェクトへの反映を確認・補完してください。

各ファイルについて順に:
1. ファイルを読む
2. 対応するプロジェクトファイル・設定を確認する
3. 未反映・不十分な箇所があれば修正する

- Step 1 で対応済みの箇所も再確認する
- 完了後はコミットしない（ユーザーが確認してから行う）
```

## English

After running `git subtree add` (the `lite` branch) to install dev-charter in your project, paste the following prompts into your AI tool in order.

> **Important:** Do **not** directly edit files under `docs/dev-charter/`. If a change is needed, open an issue in the dev-charter repository and pull the update via `git subtree pull`. Project-specific rules belong in the project's own `AI_CONTEXT.md` or dedicated files.

### Step 1 — Bulk Setup

```
Read all files in docs/dev-charter/, explore this project, then do the following:

1. Set up AI context files following the spec in docs/dev-charter/AI_TOOL_SETUP.md
2. Compare the project against charter requirements and fix all gaps
   (cover the entire project: file structure, CI, security, coding conventions, etc.)
3. Read docs/dev-charter/topics/GITHUB_SETTINGS.md and apply all repository settings
   (use gh commands if available; otherwise apply via the GitHub UI)
4. Read docs/dev-charter/topics/CI_POLICY.md and review/set up .github/workflows/
   (lite allows direct pushes to main, so follow this file's Branch Protection
   content — don't confuse it with the full variant's)

- There's no prescriptive README structure guide (lite doesn't include full's
  PROJECT_README_GUIDELINES.md). Follow existing conventions, or write a general
  structure covering the project overview and setup steps if there are none
- If you have questions or ambiguities, ask all of them at once before starting
- If the charter conflicts with existing conventions, list the conflicts and confirm priority with the user before proceeding
- For large-scope changes, confirm with the user before proceeding
- Do not commit after completing (let the user review first)
```

### Step 2 — File-by-File Review

```
Re-read each file in docs/dev-charter/ one at a time and verify that the project fully reflects it.

For each file in order:
1. Read the file
2. Check the corresponding project files and settings
3. Fix anything that is missing or incomplete

- Re-check items already addressed in Step 1
- Do not commit after completing (let the user review first)
```
