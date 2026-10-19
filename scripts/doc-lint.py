#!/usr/bin/env python3
"""Warn-only Markdown lint for staged files (size and frontmatter).

Called from git/hooks/pre-commit (and git/hooks/commit-msg for Doc-Lint-Override).
Never blocks: any problem, including internal errors, ends with exit code 0.
Spec: docs/specification.md#doc-lint
"""

from __future__ import annotations

import importlib.util
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

MAX_SHOWN = 10
OVERRIDE_RE = re.compile(r"^Doc-Lint-Override:[ \t]*(\S.*)$", re.MULTILINE)


def load_lib():
    path = Path(__file__).resolve().parent / "measure-doc-size.py"
    spec = importlib.util.spec_from_file_location("measure_doc_size", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def git(*args: str, cwd: str | None = None) -> bytes:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, check=True).stdout


def repo_name(top: str) -> str:
    common = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=top).decode().strip())
    return common.parent.name if common.name == ".git" else common.name


def staged_markdown(top: str) -> list[str]:
    out = git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z", cwd=top)
    names = [n.decode("utf-8", "replace") for n in out.split(b"\0") if n]
    return [n for n in names if n.lower().endswith(".md") and "\n" not in n]


def read_blobs(top: str, names: list[str], limit: int):
    """Yield (name, text or None when larger than limit) from the index, one git process."""
    proc = subprocess.Popen(
        ["git", "cat-file", "--batch"], cwd=top,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    try:
        for name in names:
            proc.stdin.write(f":{name}\n".encode())
            proc.stdin.flush()
            header = proc.stdout.readline().split()
            if len(header) != 3 or header[1] != b"blob":
                continue
            size = int(header[2])
            data = proc.stdout.read(size)
            proc.stdout.read(1)  # trailing newline
            yield name, (None if size > limit else data.decode("utf-8", "replace"))
    finally:
        proc.stdin.close()
        proc.wait()


def shown(rel: str) -> str:
    """Never print or log paths below private/ (may carry personal titles)."""
    return "private/<redacted>" if rel.startswith("private/") else rel


def log_path() -> Path:
    env = os.environ.get("DOC_LINT_LOG")
    return Path(env) if env else Path.home() / ".local/state/doc-lint/deviations.log"


def append_log(rows: list[list[str]]) -> None:
    if not rows:
        return
    try:
        p = log_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        with p.open("a", encoding="utf-8") as f:
            for row in rows:
                f.write("\t".join(c.replace("\t", " ").replace("\n", " ") for c in row) + "\n")
    except OSError:
        pass


def lint(top: str) -> list[dict]:
    lib = load_lib()
    cfg = lib.load_config(Path(top))
    names = [n for n in staged_markdown(top) if lib.in_scope(n, cfg)]
    results = []
    for name, text in read_blobs(top, names, lib.MAX_BLOB_BYTES):
        if text is None:
            results.append({"path": name, "findings": [("size-bytes", f">{lib.MAX_BLOB_BYTES}", str(lib.MAX_BLOB_BYTES))], "info": []})
        else:
            results.append(lib.evaluate(name, text, cfg))
    return results


def report(results: list[dict]) -> None:
    warned = [r for r in results if r["findings"]]
    infos = [r for r in results if r["info"] and not r["findings"]]
    lines = []
    for r in warned:
        parts = [f"{c} {v}" + (f">{lim}" if lim != "-" else "") for c, v, lim in r["findings"]]
        parts += [f"{c} {v}>{lim} (info)" for c, v, lim in r["info"]]
        lines.append(f"  {shown(r['path'])}: " + "; ".join(parts))
    for r in infos:
        lines.append(f"  {shown(r['path'])}: " + "; ".join(f"{c} {v}>{lim} (info)" for c, v, lim in r["info"]))
    if not lines:
        return
    head = f"doc-lint (warn only): {len(warned)} file(s)" if warned else "doc-lint (info only):"
    out = [head, *lines[:MAX_SHOWN]]
    if len(lines) > MAX_SHOWN:
        out.append(f"  ... and {len(lines) - MAX_SHOWN} more")
    out.append("  override reason: add 'Doc-Lint-Override: <reason>' to the commit message")
    print("\n".join(out), file=sys.stderr)


def run(argv: list[str]) -> None:
    top = git("rev-parse", "--show-toplevel").decode().strip()
    reason = ""
    if argv[:1] == ["--commit-msg"]:
        m = OVERRIDE_RE.search(Path(argv[1]).read_text(encoding="utf-8", errors="replace"))
        if not m:
            return
        reason = m.group(1).strip()
    results = lint(top)
    now = datetime.now().astimezone().isoformat(timespec="seconds")
    name = repo_name(top)
    rows = [
        [now, name, shown(r["path"]), c, v, lim, *([reason] if reason else [])]
        for r in results for c, v, lim in r["findings"]
    ]
    append_log(rows)
    if not reason:
        report(results)


def main() -> int:
    try:
        run(sys.argv[1:])
    except Exception:  # noqa: BLE001 - warn-only: never block a commit
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
