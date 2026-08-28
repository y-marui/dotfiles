---
name: consolidate-global-memory
description: "Scan the global memory store (~/.claude/memory) together with every per-project memory store (~/.claude/projects/*/memory) and fold each memory's content into the user's hand-maintained instruction files instead — ~/.ai/AI_CONTEXT.md, ~/.ai/AI_CONTEXT_CLI.md, or ~/.claude/CLAUDE.md for anything global/cross-project, or that project's own AI_CONTEXT.md/CLAUDE.md for anything project-specific — then delete the memory file once it's captured there (or delete it outright if already covered). Memory-to-memory moves are out of scope; the goal is to empty memory into instructions wherever a suitable instruction file exists. Use when the user asks to deduplicate, consolidate, sync, or 'globalize' memory across projects, or says memory is scattered/duplicated. Different from the single-directory consolidate-memory pass: this one compares across all project boundaries and the instruction-file hierarchy, not just one memory directory."
---

# Consolidate Global Memory

ここでは、重複し得る2つの仕組みが永続的なコンテキストを記録している。

- **指示ファイル** — 手動管理され、常に読み込まれる正本。`~/.ai/AI_CONTEXT.md`（ツール横断・全プロジェクト）、`~/.ai/AI_CONTEXT_CLI.md`（CLIツール固有・全プロジェクト）、`~/.claude/CLAUDE.md`（Claude Code専用。前述2ファイルをimportしてClaude Code専用ルールを追加）、および各プロジェクトの `AI_CONTEXT.md`。このユーザーのすべてのプロジェクトでは、`<project-root>/CLAUDE.md` は1行の `@AI_CONTEXT.md` import shimであり、実際の内容は `AI_CONTEXT.md` にある。`CLAUDE.md` を直接編集せず、importする `AI_CONTEXT.md` を編集する。
- **自動memory** — プロジェクトディレクトリごとのストア（`~/.claude/projects/<escaped-project-path>/memory/`）と、プロジェクトに属さない独立したグローバルストア（`~/.claude/memory/`）。

このskillの役割は、各memoryの置き場所を指示ファイル階層から見つけ、そこへ記録してからmemoryを削除することである。「別のmemoryストアへ移動する」という結果はない。memoryは一時的な保管場所であり、最終保存先ではない。受け入れる指示ファイルが存在しない場合だけ、memoryを残す（Phase 4を参照）。

システムプロンプトのauto-memory節が、memoryファイルの形式（frontmatter、`MEMORY.md` のインデックス形式、4種類のmemory）を定義している。ここでの保存先は別のmemoryファイルではないが、内容を読むために形式を理解する必要がある。

## Phase 1 — Inventory memory

各プロジェクトの `MEMORY.md` を1件ずつ読む代わりに、同梱スクリプトで全ストアのmemoryファイルを1回で一覧する。

```bash
bash <skill-dir>/scripts/list-memories.sh
```

各行はTSV形式の `scope<TAB>type<TAB>name<TAB>description<TAB>path` であり、`scope` は `global` または `project:<project-dir-name>` である。`MEMORY.md` のインデックス自身は、type/name/descriptionが空で返る。ここではその行を無視し、Phase 5でインデックスを編集する。

残りの行を明らかな話題ごとにまとめる（スコープをまたぐ類似したname/description、または別プロジェクトで独立して記録された同じ内容）。同じことを記すプロジェクトスコープのmemoryが複数あること自体が、プロジェクト固有ではなくグローバル層に置く根拠となる。

## Phase 2 — Classify scope

各候補の内容全体を開き、広い順にどの層へ属するか決める。

1. **Universal + CLI-specific** — CLIコーディングagentに特化するが（例: ツール呼び出しのバッチ化、コミットのタイミング）、どのプロジェクトにも適用できる内容。対象は `~/.ai/AI_CONTEXT_CLI.md`。
2. **Universal** — 任意のプロジェクト、ツール、画面に適用できる内容（コーディングスタイル、git規約、ユーザーの一般的な作業方法）。対象は `~/.ai/AI_CONTEXT.md`。
3. **Claude-Code-only** — 一般のCLI agentではなく、CodexやGemini CLIにも当てはまらない、Claude Code製品だけに真に固有の内容。対象は `~/.claude/CLAUDE.md`（`@` importの後に追記）。
4. **One project only** — そのリポジトリに結び付き、他では有用でない内容。対象はそのプロジェクトの `AI_CONTEXT.md`。エスケープされたプロジェクトディレクトリ名から実パスを復元する（`-` を `/` に置換し、組織名・リポジトリ名自体にハイフンがある場合は候補を試し、存在するパス、可能なら `.git` を含むパスを確認する）。

これは `feedback` だけでなく、すべてのmemory種別に適用する。対象ファイルにその種別の内容を置く場所がすでにあれば、`user` 型のプロフィール情報、`reference` のポインタ、`project` の状態も指示ファイルへ置ける（例: このユーザーの `AI_CONTEXT.md` には参照形式のポインタ用「アカウント情報」節がある。重複するアカウント・プロフィールmemoryは、プロジェクトに散在させずそこへ置く）。

真の矛盾を推測で解決しない。2つのmemory、またはmemoryと指示ファイルが矛盾する内容を述べる場合は、どちらも残し、片方を選ばず最終要約で矛盾を指摘する。

## Phase 3 — Check what's already covered

何かを書き込む前に、選択した層の該当指示ファイルを読む。プロジェクトスコープの候補では、そのプロジェクトの `AI_CONTEXT.md` が存在すれば読む。

- **すでに記載済み**（表現が異なっていても）: 記録しているmemoryファイルを削除する。何も書き込まない。
- **どこにも記載がない**: Phase 4へ進む。

## Phase 4 — Fold in, then delete the memory

内容を選択した層の指示ファイルへ追加する。そのファイルの既存言語（このユーザーのファイルでは日本語）、見出し構造、簡潔な指示文体に合わせる。「Why:」や「How to apply:」のような説明はmemoryの形式であり、ここには加えない。明確に適合する既存見出しがあればその下へ追加し、なければ最小限の新しい見出しを加える。無関係な既存内容を再構成・書き換えしない。その後、内容を昇格したすべてのmemoryファイルを削除する。複数プロジェクトが独立して記録していても同様である。

慎重に扱う。指示ファイルは、グローバル層なら今後の全セッション、プロジェクト層ならそのリポジトリの全セッションで読み込まれる。真に永続的で正しく一般化できると確信できる内容だけを追加する。同じ内容が2か所以上で独立して記録されていることは強い根拠である。一回限りのmemoryは根拠が弱いが、曖昧でなければ昇格できる。

**このスコープに指示ファイルが存在しない場合**（例: プロジェクトに `AI_CONTEXT.md` / `CLAUDE.md` がまったくないプロジェクトスコープのmemory）は、memoryを残す唯一のケースである。存在しないプロジェクト用に新しい `AI_CONTEXT.md` を作らず、memoryを残して最終要約に記す。内容がどこかに残らないまま、唯一のmemoryコピーを削除しない。

## Phase 5 — Tidy every touched index

ファイルを削除した各memoryストアについて、`MEMORY.md` を実態に合わせて更新する。削除済みファイルへのポインタを外し、システムプロンプトで定めた `- [Title](file.md) — hook` 形式と、200行未満・約25KB未満の上限を保つ。

## Phase 6 — Report

最後に短く要約する。どの内容をどの指示ファイルへ加え、どのmemoryファイルを退役させたか、すでに記載済みとして何件の冗長コピーを削除したか、スコープに指示ファイルがないため残したmemory、ユーザーによる手動解決が必要な矛盾を示す。
