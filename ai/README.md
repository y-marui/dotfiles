# AI Configuration Management

`ai/` は、Claude Code、Codex、GitHub Copilotで使う共通指示・skill・
MCP / plugin宣言と、各ツール固有設定の正本である。
ホームディレクトリ側のリンク先や、各ツールが生成する実行時状態を直接編集せず、
再現可能な設定はこのディレクトリで管理する。

## Context Layers

グローバルコンテキストは、常時読む内容を最小限にし、作業内容に応じて補完規約を読む。

| ファイル | 読む条件 | 主な内容 |
| --- | --- | --- |
| [`AI_CONTEXT.md`](AI_CONTEXT.md) | 常時 | 対話・安全・文章・ツール選択の共通原則と Context Routing |
| [`AI_CONTEXT_COMPUTER_USE.md`](AI_CONTEXT_COMPUTER_USE.md) | Computer Use でブラウザまたはネイティブアプリを操作するとき | サイト・アプリの許可範囲、操作、検証 |
| [`AI_CONTEXT_CLI.md`](AI_CONTEXT_CLI.md) | CLI・Coding・リポジトリ・Git/GitHubを扱うとき | 開発、Git、GitHub、docs / Issue、検証、環境固有手順への導線 |

`AI_CONTEXT.md` には、通常の会話を含むすべてのタスクで必要な原則だけを書く。
特定の操作・開発時にしか使わない内容は対応する補完規約へ置き、
同じ規則を複数ファイルへ重複させない。

各エージェントの入口は薄いshimとして保つ。

- [`codex/AGENTS.md`](codex/AGENTS.md): 共通コンテキストと Context Routing の読み込みを指示
- [`claude/CLAUDE.md`](claude/CLAUDE.md): 共通コンテキストをimportし、Claude Code固有設定だけを追記
- [`copilot/instructions.md`](copilot/instructions.md): 共通コンテキストと Context Routing を参照

補完規約の詳細手順は [`references/`](references/) に分離し、必要な節だけ読む。

## Directory Responsibilities

| パス | 責務 |
| --- | --- |
| `skills/` | Claude CodeとCodexで共有する個人skill |
| `claude/` | Claude Code固有の設定、skill、MCP / plugin宣言 |
| `codex/` | Codex固有の入口、skill、MCP / plugin宣言 |
| `copilot/` | GitHub Copilot固有の指示とMCP宣言 |
| `references/` | グローバルコンテキストから条件付きで読む詳細手順 |

skillは、ツール固有の機能や記法へ依存しない限り `skills/` に置く。
配置、命名、private data、cloud skillの詳細は
[`skills/README.md`](skills/README.md) に従う。

## Ownership Boundaries

### Repository-managed

- グローバルコンテキストと各エージェントの入口
- 共有・ツール固有skill
- 公開可能なMCP / plugin宣言
- リンク定義と、設定を再現・検証するスクリプト

### Private repository

アカウント名、リソースID、個人対応表などの固定private dataは
`dotfiles-private` に置き、同リポジトリの `links.conf` から
`~/.identity/` 等へリンクする。公開側には値を書かず、参照パスとスキーマだけを置く。

### Runtime-owned

認証トークン、ログ、履歴、DB、キャッシュ、セッション状態、ツールが随時更新する
設定ファイル全体は管理しない。必要な公開設定だけを宣言ファイルに記録し、
`dots {claude|codex|copilot} apply` で各ツールのuser scopeへ反映する。

## Applying and Inspecting State

- `make links`: コンテキストや入口を含むシンボリックリンクを再適用
- `make check`: public / privateリンクの整合性を確認
- `dots {claude|codex|copilot} diff`: 宣言と実際のuser scope設定を比較
- `dots {claude|codex|copilot} apply`: 宣言済みの不足・設定不一致を追加または更新
- `dots {claude|codex|copilot} prune`: dotfilesの管理境界内にある未宣言項目だけを削除・退避
- `dots ai {diff|apply|prune}`: Claude CodeとCodexをまとめて処理

`apply` と `prune` の所有範囲はツールごとに異なる。
実装・例外・認証情報の扱いはルート[`README.md`](../README.md#ai-configuration)を参照する。

## Change Checklist

1. 作業前に `git fetch` と `make check` を実行する。
2. リンク先ではなく `ai/` の正本を編集する。
3. 新しいリンク対象を追加する場合は、`scripts/_links.sh` と
   `scripts/_links.ps1` の両方、および関連ドキュメントを更新する。
4. コンテキストの内容は常時必要か、Computer Use固有か、CLI / Coding固有かを分類する。
5. skillは共有配置を既定とし、ツール固有配置にする根拠を確認する。
6. private dataや実行時状態が公開差分へ含まれていないことを確認する。
7. `make links`、`make check`、変更に応じて `make check-skills` を実行する。
8. `pre-commit run --all-files` を実行する。新規未追跡ファイルは
   `pre-commit run --files <path>` でも確認する。

構成や管理境界を変更した場合は、このREADMEとルートREADMEを同じ作業内で更新する。
