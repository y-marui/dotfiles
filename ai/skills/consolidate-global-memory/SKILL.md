---
name: consolidate-global-memory
description: "Scan the global memory store (~/.claude/memory) together with every per-project memory store (~/.claude/projects/*/memory) and fold each memory's content into the user's hand-maintained instruction files instead — ~/.ai/AI_CONTEXT.md, ~/.ai/AI_CONTEXT_CLI.md, or ~/.claude/CLAUDE.md for anything global/cross-project, or that project's own AI_CONTEXT.md/CLAUDE.md for anything project-specific — then delete the memory file once it's captured there (or delete it outright if already covered). Memory-to-memory moves are out of scope; the goal is to empty memory into instructions wherever a suitable instruction file exists. Use when the user asks to deduplicate, consolidate, sync, or 'globalize' memory across projects, or says memory is scattered/duplicated. Different from the single-directory consolidate-memory pass: this one compares across all project boundaries and the instruction-file hierarchy, not just one memory directory."
---

# Consolidate Global Memory

Two systems record durable context here, and they overlap:

- **Instruction files** — hand-maintained, always loaded, the authoritative
  source: `~/.ai/AI_CONTEXT.md` (cross-tool, every project), `~/.ai/AI_CONTEXT_CLI.md`
  (CLI-tool-specific, every project), `~/.claude/CLAUDE.md` (Claude Code
  only — imports the two files above, then adds Claude-Code-only rules),
  and each project's own `AI_CONTEXT.md`. In every project in this user's
  setup, `<project-root>/CLAUDE.md` is just a one-line `@AI_CONTEXT.md`
  import shim — the real content lives in `AI_CONTEXT.md`. Never edit a
  `CLAUDE.md` directly; edit the `AI_CONTEXT.md` it imports.
- **Auto-memory** — one store per project directory
  (`~/.claude/projects/<escaped-project-path>/memory/`) plus a standalone
  global store with no project of its own (`~/.claude/memory/`).

This skill's job: for each memory, find where it belongs in the
instruction-file hierarchy and put it there, then delete the memory.
There is no "move it to another memory store" outcome — memory is a
holding area, not the destination. A memory only stays a memory if no
instruction file exists to hold it (see Phase 4).

Your system prompt's auto-memory section defines the memory file format
(frontmatter, `MEMORY.md` index format, the four memory types) — you
still need to recognize it to read what a memory says, even though the
destination here is never another memory file.

## Phase 1 — Inventory memory

Run the bundled script to list every memory file across every store in one
pass, instead of reading each project's `MEMORY.md` one at a time:

```bash
bash <skill-dir>/scripts/list-memories.sh
```

Each line is TSV: `scope<TAB>type<TAB>name<TAB>description<TAB>path`, where
`scope` is `global` or `project:<project-dir-name>`. `MEMORY.md` index
files themselves come back with empty type/name/description — ignore
those rows here, you'll edit the indices in Phase 5.

Group the remaining rows by apparent topic (similar name/description
across scopes, or the same underlying content recorded independently in
different projects) — several project-scoped memories describing the same
thing is itself evidence it belongs at a global tier, not project-local.

## Phase 2 — Classify scope

Open the full content of each candidate and decide which tier it belongs
to, broadest to narrowest:

1. **Universal + CLI-specific** — makes sense for a CLI coding agent
   specifically (e.g. how to batch tool calls, when to commit), but
   applies to any project. Target: `~/.ai/AI_CONTEXT_CLI.md`.
2. **Universal** — applies to any project, any tool/surface (coding
   style, git conventions, how the user wants to work in general).
   Target: `~/.ai/AI_CONTEXT.md`.
3. **Claude-Code-only** — genuinely specific to Claude Code as a product
   (not Codex, not Gemini CLI), not to CLI agents in general. Target:
   `~/.claude/CLAUDE.md` (appended after its `@` imports).
4. **One project only** — content tied to that repo and not useful
   elsewhere. Target: that project's own `AI_CONTEXT.md`, reconstructing
   its real path from the escaped project-dir name (replace `-` with `/`;
   where the org/repo name itself contains dashes, try candidate splits
   and confirm by checking which resulting path exists, ideally
   containing `.git`).

This applies to every memory type, not just `feedback` — a `user`-type
identity fact, a `reference` pointer, or `project` status can all belong
in an instruction file if the target file already has a place for that
kind of content (e.g. this user's `AI_CONTEXT.md` already has an
"アカウント情報" section for reference-style pointers — a duplicate
account/identity memory belongs there, not scattered across projects).

Never guess on a genuine conflict — if two memories, or a memory and an
instruction file, state contradictory things, leave both in place and
flag the conflict in your closing summary instead of picking one.

## Phase 3 — Check what's already covered

Before writing anything, read the applicable instruction file(s) for the
tier you picked (and, for a project-scoped candidate, that project's
`AI_CONTEXT.md`, if it exists).

- **Already covered**, even worded differently: delete the memory
  file(s) that record it. Do not write anything.
- **Not covered anywhere**: proceed to Phase 4.

## Phase 4 — Fold in, then delete the memory

Add the content to the instruction file for the tier you picked. Match
that file's existing language (Japanese, in this user's files), heading
structure, and terse instructional style — no "Why:"/"How to apply:"
narrative, that's the memory format, not this one. Slot the addition
under an existing heading if one clearly fits; otherwise add the smallest
reasonable new heading. Don't reorganize or rewrite unrelated existing
content. Then delete every memory file this content was promoted from —
across however many projects had independently recorded it.

Be conservative: an instruction file is loaded into every future session
(global tiers) or every session in that repo (project tier), so only add
something you're confident is genuinely durable and correctly
generalized. The same content recorded independently in two or more
places is strong evidence; a single one-off memory is weaker evidence but
still promotable if it's unambiguous.

**No instruction file exists for this scope** (e.g. a project-scoped
memory whose project has no `AI_CONTEXT.md`/`CLAUDE.md` at all): this is
the one case where the memory stays a memory. Don't invent a new
`AI_CONTEXT.md` file for a project that doesn't have one — leave the
memory in place and note it in the closing summary. Never delete a
memory's only copy without its content surviving somewhere.

## Phase 5 — Tidy every touched index

For every memory store you deleted a file from, update that store's
`MEMORY.md` to match reality: remove pointers to deleted files, keep the
`- [Title](file.md) — hook` format and the under-200-lines/~25KB budget
from the system prompt.

## Phase 6 — Report

Finish with a short summary: which content you added to which instruction
file (and which memory files that retired), how many redundant copies
were deleted outright as already-covered, which memories you left in
place because no instruction file exists for their scope, and any
conflicts left for the user to resolve manually.
