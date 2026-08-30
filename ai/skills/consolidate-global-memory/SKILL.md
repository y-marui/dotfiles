---
name: consolidate-global-memory
description: "Consolidate durable knowledge from Claude and Codex local memories into hand-maintained instructions, and identify the user-managed boundary for ChatGPT Work memory. Use when the user asks to deduplicate, consolidate, sync, or globalize memory across agents; not for moving memory between stores."
---

# Consolidate Agent Memory

`memory` は想起の補助であり、恒久的なルールの正本は手動管理の指示ファイルである。別のmemoryストアへ移動しない。保存場所ごとの操作境界を守り、必要な内容を正本へ昇格する。

- 正本: `~/.ai/AI_CONTEXT.md`（全体）、`~/.ai/AI_CONTEXT_CLI.md`（CLI固有）、`~/.claude/CLAUDE.md`（Claude Code固有）、各プロジェクトの `AI_CONTEXT.md`。
- このユーザーのプロジェクトでは `<project-root>/CLAUDE.md` は `@AI_CONTEXT.md` のimport shimである。shimではなく `AI_CONTEXT.md` を編集する。

## Memory Stores

- **Claude Code**: `~/.claude/memory/` と `~/.claude/projects/*/memory/`。内容を正本へ反映または既存記載と確認した後、該当memoryを削除して `MEMORY.md` を更新する。
- **Codex local**: `${CODEX_HOME:-~/.codex}/memories/`。`MEMORY.md`、`memory_summary.md`、`raw_memories.md`、`rollout_summaries/` を読んで昇格候補を見つける。これらは生成済み状態なので、手編集・削除しない。現在または将来のchatへの利用は `/memories`、有効化は Settings > Personalization または `config.toml` のmemory設定でユーザーが管理する。
- **ChatGPT Work**: アカウントまたはワークスペースのmemory設定を使い、ローカルCodex memoryやローカル制御を使わない。ローカルファイルを探索・変更・削除しない。ユーザーが提供したmemory内容だけを正本へ昇格し、設定変更・削除は Settings > Personalization でユーザーが管理する。

必須ルールは常に `AGENTS.md` または管理対象ドキュメントへ置き、memoryを唯一の正本にしない。

## Phase 1 — Inventory memory

Claude CodeとCodex localの候補は、同梱スクリプトで一度に一覧する。

```bash
bash <skill-dir>/scripts/list-memories.sh
```

出力は `scope<TAB>type<TAB>name<TAB>description<TAB>path`。Claude Codeのscopeは `global` または `project:<project-dir-name>`、Codex localは `codex:local` または `codex:rollout`。`MEMORY.md` のようにfrontmatterがないファイルは型・名前・説明が空でも一覧に残し、内容を読む。候補は話題ごとにまとめる。複数プロジェクトに同じ内容があることは、グローバル層へ置く強い根拠になる。

## Phase 2 — Classify scope

各候補の内容全体を読み、最も広く適用できる層を選ぶ。

1. **Universal + CLI-specific** — CLIコーディングagentに特化するが（例: ツール呼び出しのバッチ化、コミットのタイミング）、どのプロジェクトにも適用できる内容。対象は `~/.ai/AI_CONTEXT_CLI.md`。
2. **Universal** — 任意のプロジェクト、ツール、画面に適用できる内容（コーディングスタイル、git規約、ユーザーの一般的な作業方法）。対象は `~/.ai/AI_CONTEXT.md`。
3. **Claude-Code-only** — 一般のCLI agentではなく、CodexやGemini CLIにも当てはまらない、Claude Code製品だけに真に固有の内容。対象は `~/.claude/CLAUDE.md`（`@` importの後に追記）。
4. **One project only** — そのプロジェクトの `AI_CONTEXT.md`。エスケープされたパスは `-` を `/` に置換して候補を試し、存在と可能なら `.git` を確認する。

`feedback` に限らず、`user`、`reference`、`project` を含むすべてのmemory種別に適用する。真の矛盾は解決せず、両方を残して最終報告で示す。

## Phase 3 — Promote safely

選択した指示ファイルを先に読む。

- 既に記載済みなら、Claude Codeの該当memoryだけを削除する。
- 未記載なら、そのファイルの言語・見出し・簡潔な指示文体に合わせ、既存の適切な見出しへ追加する。Claude Codeの該当memoryは、その後に削除する。無関係な既存内容は再構成しない。
- 真に永続的で正しく一般化できる内容だけを昇格する。独立した重複は強い根拠だが、一回限りの内容は慎重に扱う。
- Codex localの生成済みmemoryは、昇格後も変更しない。対応する `/memories` 設定またはユーザーが管理するmemoryを報告する。
- ChatGPT Workのmemoryは、ユーザー提供内容だけを昇格対象にする。内容の列挙、エクスポート、削除を試みず、ユーザーがSettingsで管理する境界を報告する。
- 対応する指示ファイルがない場合は新規作成せず、唯一のコピーを削除せずに残して報告する。

## Phase 4 — Tidy Claude indexes

Claude Codeのファイルを削除した各memoryストアについて、`MEMORY.md` を実態に合わせて更新する。削除済みファイルへのポインタを外し、システムプロンプトで定めた `- [Title](file.md) — hook` 形式と、200行未満・約25KB未満の上限を保つ。Codex localのindexは変更しない。

## Phase 5 — Report

追加先、Claude Codeで退役させたmemory、既存記載として削除した冗長コピー数、Codex local／ChatGPT Workでユーザー管理として残したmemory、指示ファイルがなく残したmemory、未解決の矛盾を短く報告する。

## Phase 6 — Sweep `~/.dotfiles-backup`

memoryの棚卸しと合わせて `review-dotfiles-backup` skillを使い、`~/.dotfiles-backup` も内容確認・分類する。冗長と確認できても自分で `rm -rf ~/.dotfiles-backup` を実行せず、ユーザーへコマンドとして渡す。結果は報告に含める。
