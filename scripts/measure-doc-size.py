#!/usr/bin/env python3
"""Measure AI_CONTEXT document size (lines, display width, approximate tokens).

Output only: this never fails on an exceeded guideline (exit code is 0).
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
MAX_WIDTH = 100
MAX_TOKENS = {"always": 3000, "reference": 6000}

URL_RE = re.compile(r"https?://")
FENCE_RE = re.compile(r"^\s*(```|~~~)")


def char_width(ch: str) -> int:
    return 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1


def approx_tokens(text: str) -> int:
    """ASCII / 4 + non-ASCII * 1. No exact Claude tokenizer is available offline."""
    ascii_chars = sum(1 for c in text if ord(c) < 128)
    return round(ascii_chars / 4 + (len(text) - ascii_chars))


def max_width(text: str) -> int:
    """Longest line width; code blocks, table rows and URL lines are exempt."""
    widest = 0
    in_fence = False
    for line in text.splitlines():
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence or line.lstrip().startswith("|") or URL_RE.search(line):
            continue
        widest = max(widest, sum(char_width(c) for c in line))
    return widest


def measure(path: Path, kind: str) -> dict:
    text = path.read_text(encoding="utf-8")
    lines = len(text.splitlines())
    width = max_width(text)
    tokens = approx_tokens(text)
    over = []
    if lines > MAX_LINES:
        over.append("lines")
    if width > MAX_WIDTH:
        over.append("width")
    if tokens > MAX_TOKENS[kind]:
        over.append("tokens")
    return {
        "path": str(path),
        "kind": kind,
        "lines": lines,
        "width": width,
        "tokens": tokens,
        "over": over,
    }


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
    args = ap.parse_args()

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
    print(f"{'LINES':>5} {'WIDTH':>5} {'~TOKENS':>7}  PATH")
    for r in results:
        mark = lambda key, v: f"{v}{'*' if key in r['over'] else ' '}"  # noqa: E731
        shown = r["path"].replace(home, "~", 1)
        print(
            f"{mark('lines', r['lines']):>5} {mark('width', r['width']):>5} "
            f"{mark('tokens', r['tokens']):>7}  {shown}"
        )
    exceeded = [r for r in results if r["over"] and r["kind"] == "always"]
    print(
        f"\n{len(results)} files, {len(exceeded)} always-loaded over guideline "
        f"(lines>{MAX_LINES}, width>{MAX_WIDTH}, ~tokens>{MAX_TOKENS['always']}; "
        "* = exceeded). Guidelines only; not enforced."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
