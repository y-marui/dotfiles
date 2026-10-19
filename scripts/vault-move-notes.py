#!/usr/bin/env python3
"""Move or rename Obsidian vault notes and rewrite wikilink targets vault-wide.

Notes are moved with `git mv`; nothing is committed or pushed. All rewrites are
computed and verified in memory first, so a failed verification writes nothing.
If applying fails midway, the moves and file contents are restored.

Verification (any failure exits non-zero without writing):
  1. In every changed file, the text before and after is identical once link
     targets are masked (only the target part of a link may differ).
  2. Every rewritten link resolves to the moved note, and no link in a changed
     file newly fails to resolve (links already broken are only reported).
  3. Every destination is free, and every source is an existing tracked note.
"""

from __future__ import annotations

import argparse
import os
import posixpath
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_VAULT = "~/src/github.com/y-marui/obsidian-vault"
SKIP_DIRS = {".git", ".obsidian", ".trash"}
PRIVATE_DIR = "private"

LINK_RE = re.compile(r"(!?)\[\[([^\[\]\n]*)\]\]")
FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})")
INLINE_CODE_RE = re.compile(r"(`+)(.+?)\1")

TEST_FAIL = os.environ.get("VAULT_MOVE_NOTES_TEST_FAIL", "")


class ToolError(Exception):
    pass


def parse_link(inner: str) -> tuple[str, str]:
    """Split link inner text into (target, rest). rest keeps heading/alias/escape."""
    cut = len(inner)
    for ch in ("|", "#"):
        i = inner.find(ch)
        if i != -1:
            cut = min(cut, i)
    target = inner[:cut]
    rest = inner[cut:]
    if target.endswith("\\"):
        # table-escaped pipe: [[path\|alias]]
        return target[:-1], "\\" + rest
    return target, rest


class Index:
    """Path set with Obsidian-style link resolution."""

    def __init__(self, files: set[str]):
        self.files = files
        self.by_key: dict[str, list[str]] = {}
        for f in files:
            base = posixpath.basename(f)
            keys = {base}
            if f.endswith(".md"):
                keys.add(base[:-3])
            for k in keys:
                self.by_key.setdefault(k, []).append(f)

    def resolve(self, target: str) -> str | None:
        t = target.strip()
        if not t:
            return None
        if "/" in t:
            t = posixpath.normpath(t)
            for cand in (t, t + ".md"):
                if cand in self.files:
                    return cand
            return None
        hits = self.by_key.get(t, [])
        return hits[0] if len(hits) == 1 else None


def list_files(vault: Path, include_private: bool) -> set[str]:
    out: set[str] = set()
    for root, dirs, names in os.walk(vault):
        rel_root = os.path.relpath(root, vault)
        dirs[:] = [
            d
            for d in dirs
            if d not in SKIP_DIRS
            and not (rel_root == "." and d == PRIVATE_DIR and not include_private)
        ]
        for n in names:
            rel = n if rel_root == "." else f"{rel_root}/{n}"
            out.add(rel.replace(os.sep, "/"))
    return out


def split_segments(text: str):
    """Yield (segment, is_code) pieces; fenced blocks and inline code are code."""
    fence = ""
    for line in text.splitlines(keepends=True):
        m = FENCE_RE.match(line)
        if m:
            marker = m.group(1)
            if not fence:
                fence = marker
                yield line, True
                continue
            if marker[0] == fence[0] and len(marker) >= len(fence):
                fence = ""
            yield line, True
            continue
        if fence:
            yield line, True
            continue
        pos = 0
        for im in INLINE_CODE_RE.finditer(line):
            if im.start() > pos:
                yield line[pos : im.start()], False
            yield im.group(0), True
            pos = im.end()
        if pos < len(line):
            yield line[pos:], False


def mask_targets(text: str) -> str:
    def sub(m: re.Match) -> str:
        _, rest = parse_link(m.group(2))
        return f"{m.group(1)}[[\0{rest}]]"

    return LINK_RE.sub(sub, text)


def new_target(old_target: str, new_path: str, post: Index) -> str:
    """Target text for a link that pointed at a moved note."""
    t = old_target.strip()
    keep_ext = t.endswith(".md")
    if "/" in t:
        return new_path if keep_ext else new_path[:-3]
    base = posixpath.basename(new_path)
    cand = base if keep_ext else base[:-3]
    if post.resolve(cand) == new_path:
        return cand
    return new_path if keep_ext else new_path[:-3]


def plan(vault: Path, moves: list[tuple[str, str]], include_private: bool):
    pre_files = list_files(vault, include_private)
    move_map = dict(moves)

    # (3) preconditions
    seen_new: set[str] = set()
    for old, new in moves:
        for p in (old, new):
            if not p.endswith(".md"):
                raise ToolError(f"not a .md note: {p}")
            if not include_private and (p == PRIVATE_DIR or p.startswith(PRIVATE_DIR + "/")):
                raise ToolError(f"private path needs --include-private: {p}")
        if old == new:
            raise ToolError(f"source equals destination: {old}")
        if old not in pre_files:
            raise ToolError(f"source does not exist: {old}")
        if (vault / new).exists() or new in pre_files:
            raise ToolError(f"destination already exists: {new}")
        if new in seen_new:
            raise ToolError(f"duplicate destination: {new}")
        seen_new.add(new)
    if len(move_map) != len(moves):
        raise ToolError("duplicate source")

    pre = Index(pre_files)
    post = Index((pre_files - set(move_map)) | set(move_map.values()))

    changes: dict[str, tuple[str, str, int]] = {}  # old path -> (before, after, links)
    warnings: list[str] = []
    pre_broken: dict[str, set[str]] = {}
    expected: dict[str, list[tuple[str, str]]] = {}  # new path of file -> [(target, dest)]

    for f in sorted(pre_files):
        if not f.endswith(".md"):
            continue
        try:
            before = (vault / f).read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            warnings.append(f"skipped (not UTF-8): {f}")
            continue
        count = 0
        pieces: list[str] = []
        file_expected: list[tuple[str, str]] = []
        broken: set[str] = set()

        def rewrite(m: re.Match, in_code: bool) -> str:
            nonlocal count
            target, rest = parse_link(m.group(2))
            if not target.strip():
                return m.group(0)
            dest = pre.resolve(target)
            if dest is None:
                if not in_code:
                    broken.add(target)
                return m.group(0)
            if dest not in move_map:
                return m.group(0)
            if in_code:
                warnings.append(f"link in code not rewritten: {f}: {m.group(0)}")
                return m.group(0)
            nt = new_target(target, move_map[dest], post)
            file_expected.append((nt, move_map[dest]))
            if TEST_FAIL == "verify":
                nt += "-broken"
            if nt == target:
                return m.group(0)
            count += 1
            return f"{m.group(1)}[[{nt}{rest}]]"

        for seg, is_code in split_segments(before):
            pieces.append(LINK_RE.sub(lambda m, c=is_code: rewrite(m, c), seg))
        after = "".join(pieces)
        pre_broken[f] = broken
        if after != before or f in move_map:
            changes[f] = (before, after, count)
        expected[move_map.get(f, f)] = file_expected

    # (1) only link targets may differ
    for f, (before, after, _) in changes.items():
        if mask_targets(before) != mask_targets(after):
            raise ToolError(f"verification failed (non-target diff): {f}")

    # (2) rewritten links resolve to the moved note; no newly broken links
    for f, (_, after, _) in changes.items():
        new_f = move_map.get(f, f)
        for nt, dest in expected.get(new_f, []):
            if post.resolve(nt) != dest:
                raise ToolError(f"verification failed ({new_f}): '{nt}' does not resolve to {dest}")
        for seg, is_code in split_segments(after):
            if is_code:
                continue
            for m in LINK_RE.finditer(seg):
                target, _ = parse_link(m.group(2))
                if target.strip() and post.resolve(target) is None and target not in pre_broken[f]:
                    raise ToolError(f"verification failed (new broken link in {new_f}): [[{target}]]")
    broken_report = sorted(f"{f}: [[{t}]]" for f, ts in pre_broken.items() if f in changes for t in ts)

    # warnings: references the tool does not rewrite
    olds = [o[:-3] for o in move_map]
    extra = [p for p in pre_files if p.endswith(".base")]
    obs = vault / ".obsidian"
    if obs.is_dir():
        for root, _, names in os.walk(obs):
            for n in names:
                extra.append(os.path.relpath(os.path.join(root, n), vault).replace(os.sep, "/"))
    for p in sorted(extra):
        try:
            text = (vault / p).read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for stem in olds:
            if stem in text:
                warnings.append(f"old path referenced (not rewritten): {p}: {stem}")
    return changes, warnings, broken_report, move_map


def git(vault: Path, *args: str) -> None:
    r = subprocess.run(["git", "-C", str(vault), *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise ToolError(f"git {' '.join(args)} failed: {r.stderr.strip()}")


def apply(vault: Path, changes, move_map) -> None:
    done_moves: list[tuple[str, str]] = []
    written: dict[str, str] = {}  # current path -> original text
    created: list[Path] = []
    try:
        for old, new in move_map.items():
            r = subprocess.run(
                ["git", "-C", str(vault), "ls-files", "--error-unmatch", old],
                capture_output=True,
            )
            if r.returncode != 0:
                raise ToolError(f"not tracked by git: {old}")
        for old, new in move_map.items():
            parent = (vault / new).parent
            missing = []
            p = parent
            while not p.exists():
                missing.append(p)
                p = p.parent
            parent.mkdir(parents=True, exist_ok=True)
            created.extend(missing)
            git(vault, "mv", old, new)
            done_moves.append((old, new))
        for old, (before, after, _) in changes.items():
            cur = move_map.get(old, old)
            if after != before:
                (vault / cur).write_bytes(after.encode("utf-8"))
                written[cur] = before
        if TEST_FAIL == "apply":
            raise ToolError("injected failure")
    except BaseException:
        for cur, before in written.items():
            (vault / cur).write_bytes(before.encode("utf-8"))
        for old, new in reversed(done_moves):
            git(vault, "mv", new, old)
        for d in sorted(created, key=lambda x: len(x.parts), reverse=True):
            try:
                d.rmdir()
            except OSError:
                pass
        raise


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    ap.add_argument("--vault", default=DEFAULT_VAULT)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--include-private", action="store_true")
    ap.add_argument("paths", nargs="+", metavar="OLD NEW", help="vault-relative pairs")
    args = ap.parse_args(argv)

    if len(args.paths) % 2:
        ap.error("moves must be given as OLD NEW pairs")
    vault = Path(os.path.expanduser(args.vault)).resolve()
    if not (vault / ".git").exists():
        print(f"error: not a git vault: {vault}", file=sys.stderr)
        return 2
    moves = []
    for old, new in zip(args.paths[::2], args.paths[1::2]):
        pair = []
        for p in (old, new):
            n = posixpath.normpath(p)
            if n.startswith("/") or n == ".." or n.startswith("../"):
                print(f"error: path must be vault-relative: {p}", file=sys.stderr)
                return 2
            pair.append(n)
        moves.append((pair[0], pair[1]))

    try:
        changes, warnings, broken, move_map = plan(vault, moves, args.include_private)
        if not args.dry_run:
            apply(vault, changes, move_map)
    except ToolError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    print(("dry-run: " if args.dry_run else "") + "moves:")
    for old, new in moves:
        print(f"  {old} -> {new}")
    print("changed files (links rewritten):")
    for old, (_, _, n) in sorted(changes.items()):
        print(f"  {move_map.get(old, old)}: {n}")
    if broken:
        print("already-broken links (not changed):")
        for b in broken:
            print(f"  {b}")
    for w in warnings:
        print(f"warning: {w}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
