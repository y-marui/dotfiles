#!/usr/bin/env python3
"""Measure Markdown size (lines, sentence width, approximate tokens).

Output only: this never fails on an exceeded guideline (exit code is 0).
Also the shared library for scripts/doc-lint.py (scope, config, evaluation).
--inventory scans every ghq repository using each repo's .doc-lint.toml.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

MAX_LINES = 200
MAX_WIDTH = 200  # per sentence fragment (see max_width)
MAX_TOKENS = {"always": 3000, "reference": 6000}
MAX_BLOB_BYTES = 2 * 1024 * 1024  # larger files are not analysed (kept fast)

URL_RE = re.compile(r"https?://")
FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})")
# Sentence ends: after 。！？!? and after "." followed by whitespace.
SENTENCE_SPLIT_RE = re.compile(r"(?<=[。！？!?])|(?<=\.)(?=\s)")

ALWAYS_NAMES = {"CLAUDE.md", "AGENTS.md", "GEMINI.md", "SKILL.md"}
FRONTMATTER_EXEMPT_NAMES = {
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "CODE_OF_CONDUCT.md",
    "DEVELOPING.md",
}
CONFIG_NAME = ".doc-lint.toml"
VALID_SCOPES = ("default", "all")


def char_width(ch: str) -> int:
    return 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1


def approx_tokens(text: str) -> int:
    """ASCII / 4 + non-ASCII * 1. No exact Claude tokenizer is available offline."""
    ascii_chars = sum(1 for c in text if ord(c) < 128)
    return round(ascii_chars / 4 + (len(text) - ascii_chars))


def max_width(text: str) -> int:
    """Widest sentence fragment; code blocks, table rows and URL lines are exempt.

    Each line is cut at sentence ends (。！？!? and ". " followed by whitespace) and
    the widest fragment is reported, so a long line of short sentences is fine.
    """
    widest = 0
    fence = ""  # opening marker while inside a code block
    for line in text.splitlines():
        m = FENCE_RE.match(line)
        if m:
            marker = m.group(1)
            if not fence:
                fence = marker
            elif marker[0] == fence[0] and len(marker) >= len(fence):
                fence = ""
            continue
        if fence or line.lstrip().startswith("|") or URL_RE.search(line):
            continue
        for frag in SENTENCE_SPLIT_RE.split(line):
            widest = max(widest, sum(char_width(c) for c in frag.lstrip()))
    return widest


def split_frontmatter(text: str) -> tuple[list[str] | None, str]:
    """Return (frontmatter lines, body). Frontmatter is None when absent."""
    text = text.lstrip("\ufeff")
    lines = text.splitlines()
    if not lines or lines[0].rstrip() != "---":
        return None, text
    for i in range(1, len(lines)):
        if lines[i].rstrip() in ("---", "..."):
            return lines[1:i], "\n".join(lines[i + 1 :])
    return None, text


DESC_RE = re.compile(r"^description\s*:\s*(.*)$")


def description_status(fm: list[str] | None) -> str:
    """ok | no-frontmatter | no-description | empty-description | multiline-description."""
    if fm is None:
        return "no-frontmatter"
    for i, line in enumerate(fm):
        m = DESC_RE.match(line)
        if not m:
            continue
        val = m.group(1).strip()
        if not val:
            nxt = fm[i + 1] if i + 1 < len(fm) else ""
            return "multiline-description" if nxt[:1] in (" ", "\t") else "empty-description"
        if val[0] in "|>":
            return "multiline-description"
        if val[0] in "\"'" and (len(val) < 2 or val[-1] != val[0]):
            return "multiline-description"
        return "ok"
    return "no-description"


def kind_for(path: str) -> str:
    """Token guideline class: always-loaded docs (3000) or reference docs (6000)."""
    name = path.replace("\\", "/").rsplit("/", 1)[-1]
    if name in ALWAYS_NAMES or (name.startswith("AI_CONTEXT") and name.endswith(".md")):
        return "always"
    return "reference"


def metrics(text: str, kind: str) -> dict:
    """Size metrics of the body (frontmatter excluded) plus guideline overruns."""
    _, body = split_frontmatter(text)
    lines = len(body.splitlines())
    width = max_width(body)
    tokens = approx_tokens(body)
    over = []
    if lines > MAX_LINES:
        over.append("lines")
    if width > MAX_WIDTH:
        over.append("width")
    if tokens > MAX_TOKENS[kind]:
        over.append("tokens")
    return {"kind": kind, "lines": lines, "width": width, "tokens": tokens, "over": over}


def measure(path: Path, kind: str) -> dict:
    text = path.read_text(encoding="utf-8")
    return {"path": str(path), **metrics(text, kind)}


# --- scope / config (shared with scripts/doc-lint.py) ---


def glob_regex(pattern: str) -> re.Pattern:
    """gitignore-like glob: ** crosses directories, * and ? do not; no "/" => basename."""
    i, out = 0, ""
    while i < len(pattern):
        c = pattern[i]
        if pattern.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif pattern.startswith("**", i):
            out += ".*"
            i += 2
        elif c == "*":
            out += "[^/]*"
            i += 1
        elif c == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(c)
            i += 1
    return re.compile(out + r"\Z")


def glob_match(pattern: str, rel: str) -> bool:
    target = rel if "/" in pattern else rel.rsplit("/", 1)[-1]
    return bool(glob_regex(pattern).match(target))


def any_match(patterns: list[str], rel: str) -> bool:
    return any(glob_match(p, rel) for p in patterns)


def load_config(root: Path) -> dict:
    cfg: dict = {"scope": "default", "exempt_all": [], "exempt_size": [], "exempt_frontmatter": []}
    f = root / CONFIG_NAME
    if not f.is_file():
        return cfg
    try:
        import tomllib

        data = tomllib.loads(f.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001 - a broken config must never break a commit
        return cfg
    if data.get("scope") in VALID_SCOPES:
        cfg["scope"] = data["scope"]
    for key in ("exempt_all", "exempt_size", "exempt_frontmatter"):
        val = data.get(key)
        if isinstance(val, list) and all(isinstance(x, str) for x in val):
            cfg[key] = val
    return cfg


def in_scope(rel: str, cfg: dict) -> bool:
    if not rel.lower().endswith(".md") or any_match(cfg["exempt_all"], rel):
        return False
    parts = rel.split("/")
    if cfg["scope"] == "all":
        return not ({".git", ".obsidian"} & set(parts[:-1]))
    return not rel.startswith("docs/dev-charter/") and not ({".git", ".obsidian"} & set(parts[:-1]))


def frontmatter_exempt(rel: str, cfg: dict) -> bool:
    name = rel.rsplit("/", 1)[-1]
    return (
        name.startswith("README")
        or name.startswith("LICENSE")
        or name in FRONTMATTER_EXEMPT_NAMES
        or rel.startswith(".github/")
        or any_match(cfg["exempt_frontmatter"], rel)
    )


def evaluate(rel: str, text: str, cfg: dict) -> dict:
    """Lint one in-scope file. findings are warnings; info is reference-only."""
    kind = kind_for(rel)
    m = metrics(text, kind)
    fm, _ = split_frontmatter(text)
    fm_status = "exempt" if frontmatter_exempt(rel, cfg) else description_status(fm)
    findings: list[tuple[str, str, str]] = []
    info: list[tuple[str, str, str]] = []
    if not any_match(cfg["exempt_size"], rel):
        if "lines" in m["over"]:
            findings.append(("lines", str(m["lines"]), str(MAX_LINES)))
        if "tokens" in m["over"]:
            findings.append(("tokens", str(m["tokens"]), str(MAX_TOKENS[kind])))
        if "width" in m["over"]:
            info.append(("width", str(m["width"]), str(MAX_WIDTH)))
    if fm_status not in ("ok", "exempt"):
        findings.append(("frontmatter", fm_status, "-"))
    return {"path": rel, **m, "frontmatter": fm_status, "findings": findings, "info": info}


def repo_roots() -> list[Path]:
    try:
        out = subprocess.run(
            ["ghq", "list", "-p"], capture_output=True, text=True, check=True
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return []
    return [Path(p) for p in out.splitlines() if p]


def default_targets() -> list[tuple[Path, str]]:
    targets: list[tuple[Path, str]] = []
    for p in sorted((Path.home() / ".ai").glob("AI_CONTEXT*.md")):
        targets.append((p, "always"))
    for root in repo_roots():
        p = root / "AI_CONTEXT.md"
        if p.is_file():
            targets.append((p, "always"))
    return targets


VAULT_NAME = "obsidian-vault"


def tracked_markdown(root: Path) -> list[str]:
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--", "*.md"],
            capture_output=True, check=True,
        ).stdout.decode("utf-8", "replace")
    except (OSError, subprocess.CalledProcessError):
        return []
    return [p for p in out.split("\0") if p]


def inventory(roots: list[Path], include_private: bool) -> dict:
    """Scan repos. obsidian-vault private/** is only counted, never listed."""
    repos, files = [], []
    for root in roots:
        cfg = load_config(root)
        is_vault = root.name == VAULT_NAME
        summary = {"repo": root.name, "files": 0, "size_over": 0, "frontmatter_issues": 0, "width_info": 0}
        priv = {"files": 0, "size_over": 0, "frontmatter_issues": 0}
        for rel in tracked_markdown(root):
            private = is_vault and rel.startswith("private/")
            if private and (not include_private or rel.startswith("private/records/")):
                continue
            if not in_scope(rel, cfg):
                continue
            try:
                f = root / rel
                if f.stat().st_size > MAX_BLOB_BYTES:
                    continue
                r = evaluate(rel, f.read_text(encoding="utf-8", errors="replace"), cfg)
            except OSError:
                continue
            size_over = any(c in ("lines", "tokens") for c, _, _ in r["findings"])
            fm_issue = any(c == "frontmatter" for c, _, _ in r["findings"])
            if private:
                priv["files"] += 1
                priv["size_over"] += size_over
                priv["frontmatter_issues"] += fm_issue
                continue
            summary["files"] += 1
            summary["size_over"] += size_over
            summary["frontmatter_issues"] += fm_issue
            summary["width_info"] += bool(r["info"])
            files.append({
                "repo": root.name, "path": rel, "kind": r["kind"], "lines": r["lines"],
                "width": r["width"], "tokens": r["tokens"], "frontmatter": r["frontmatter"],
                "over": r["over"],
            })
        if include_private and is_vault:
            summary["private"] = priv
        repos.append(summary)
    return {"repos": repos, "files": files}


def print_inventory(inv: dict) -> None:
    print(f"{'REPO':<28} {'FILES':>5} {'SIZE>':>5} {'FM!':>4} {'WIDTH(i)':>8}")
    for r in inv["repos"]:
        print(f"{r['repo']:<28} {r['files']:>5} {r['size_over']:>5} "
              f"{r['frontmatter_issues']:>4} {r['width_info']:>8}")
        if "private" in r:
            p = r["private"]
            print(f"{'  private/** (counts only)':<28} {p['files']:>5} {p['size_over']:>5} "
                  f"{p['frontmatter_issues']:>4}")
    flagged = [f for f in inv["files"]
               if f["over"] or f["frontmatter"] not in ("ok", "exempt")]
    print(f"\nFlagged files ({len(flagged)}; * = exceeded, width is reference only):")
    print(f"{'LINES':>6} {'WIDTH':>6} {'~TOKENS':>8}  {'FRONTMATTER':<22} FILE")
    for f in flagged:
        mark = lambda key, v: f"{v}{'*' if key in f['over'] else ' '}"  # noqa: E731
        print(f"{mark('lines', f['lines']):>6} {f['width']:>6} {mark('tokens', f['tokens']):>8}  "
              f"{f['frontmatter']:<22} {f['repo']}/{f['path']}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--path", nargs="+", type=Path, help="measure these files instead")
    ap.add_argument(
        "--kind",
        choices=sorted(MAX_TOKENS),
        default="always",
        help="token guideline for --path files (always=3000, reference=6000)",
    )
    ap.add_argument("--json", action="store_true", help="emit JSON")
    ap.add_argument("--inventory", action="store_true",
                    help="scan all ghq repos by each .doc-lint.toml scope (size + frontmatter)")
    ap.add_argument("--root", nargs="+", type=Path,
                    help="with --inventory: scan these repo roots instead of ghq list -p")
    ap.add_argument("--include-private-counts", action="store_true",
                    help="with --inventory: count obsidian-vault private/** (never lists paths)")
    args = ap.parse_args()

    if args.inventory:
        roots = [r.expanduser().resolve() for r in args.root] if args.root else repo_roots()
        inv = inventory(roots, args.include_private_counts)
        if args.json:
            print(json.dumps(inv, ensure_ascii=False, indent=2))
        else:
            print_inventory(inv)
        return 0

    targets = (
        [(p, args.kind) for p in args.path] if args.path else default_targets()
    )
    results = []
    for path, kind in targets:
        try:
            results.append(measure(path.expanduser(), kind))
        except (OSError, UnicodeDecodeError) as e:
            print(f"skip {path}: {e}", file=sys.stderr)

    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
        return 0

    home = str(Path.home())
    print(f"{'LINES':>5} {'WIDTH':>5} {'~TOKENS':>7}  PATH")  # width: per sentence, reference only
    for r in results:
        mark = lambda key, v: f"{v}{'*' if key in r['over'] else ' '}"  # noqa: E731
        shown = r["path"].replace(home, "~", 1)
        print(
            f"{mark('lines', r['lines']):>5} {mark('width', r['width']):>5} "
            f"{mark('tokens', r['tokens']):>7}  {shown}"
        )
    exceeded = [r for r in results if r["over"]]
    kinds = sorted({r["kind"] for r in results})
    limits = "/".join(str(MAX_TOKENS[k]) for k in kinds)
    print(
        f"\n{len(results)} files, {len(exceeded)} over guideline "
        f"(lines>{MAX_LINES}, sentence width>{MAX_WIDTH}, ~tokens>{limits}; "
        "* = exceeded). Guidelines only; not enforced."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
