"""Merge public and optional private external skill declarations before mutation."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path, PurePosixPath


def load_manifest(public: Path, private: Path | None) -> dict:
    entries = []
    seen = set()
    for file in (public, private):
        if file is None:
            continue
        if file == private and not file.exists():
            continue
        data = json.loads(file.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or not isinstance(data.get("skills"), list):
            raise TypeError(f"{file}: expected skills array")
        for entry in data["skills"]:
            if not isinstance(entry, dict):
                raise TypeError(f"{file}: expected skill object")
            name = entry.get("name", "")
            path = entry.get("path", "")
            repo = entry.get("repo", "")
            ref = entry.get("ref", "main")
            targets = entry.get("targets", ["claude", "codex"])
            if not isinstance(name, str) or not re.fullmatch(
                r"[a-z0-9][a-z0-9-]*", name
            ):
                raise ValueError(f"{file}: invalid skill name")
            if name in seen:
                raise ValueError(f"duplicate external skill: {name}")
            if (
                not isinstance(path, str)
                or "\\" in path
                or any(c in path for c in "\t\r\n")
                or PurePosixPath(path).is_absolute()
                or any(part in {"", ".", ".."} for part in path.split("/"))
                or PurePosixPath(path).name != name
            ):
                raise ValueError(f"{file}: invalid skill path for {name}")
            if not isinstance(repo, str) or not re.fullmatch(
                r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo
            ):
                raise ValueError(f"{file}: invalid repository for {name}")
            if not isinstance(ref, str) or not ref or any(c in ref for c in "\t\r\n"):
                raise ValueError(f"{file}: invalid ref for {name}")
            if not isinstance(targets, list) or any(
                t not in {"claude", "codex"} for t in targets
            ):
                raise ValueError(f"{file}: invalid targets for {name}")
            seen.add(name)
            entries.append(entry)
    return {"skills": entries}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public", type=Path, required=True)
    parser.add_argument("--private", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(load_manifest(args.public, args.private), ensure_ascii=False))
    except (OSError, ValueError, TypeError) as error:
        parser.exit(1, f"External skill manifest: {error}\n")


if __name__ == "__main__":
    main()
