#!/usr/bin/env python3
"""Validate dotfiles-managed Agent Skill names and OpenAI UI metadata."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SKILL_ROOTS = (ROOT / "ai/skills", ROOT / "ai/claude/skills", ROOT / "ai/codex/skills")
MANIFEST = ROOT / "ai/skills/naming.json"


def field(path: Path, name: str) -> str | None:
    match = re.search(
        rf"^[ \t]*{re.escape(name)}:\s*[\"']?(.+?)[\"']?\s*$",
        path.read_text(),
        re.MULTILINE,
    )
    return match.group(1) if match else None


def main() -> int:
    manifest = json.loads(MANIFEST.read_text())
    rules = manifest["skills"]
    found: dict[str, Path] = {}
    errors: list[str] = []

    for root in SKILL_ROOTS:
        for skill_file in root.glob("*/SKILL.md"):
            skill_dir = skill_file.parent
            name = field(skill_file, "name")
            if not name:
                errors.append(f"{skill_file.relative_to(ROOT)}: missing frontmatter name")
                continue
            if skill_dir.name != name:
                errors.append(
                    f"{skill_file.relative_to(ROOT)}: directory name {skill_dir.name!r} does not match name {name!r}"
                )
            if name in found:
                errors.append(f"duplicate managed skill name: {name}")
            found[name] = skill_dir

            metadata = skill_dir / "agents/openai.yaml"
            if not metadata.is_file():
                errors.append(f"{skill_dir.relative_to(ROOT)}: missing agents/openai.yaml")
                continue
            display_name = field(metadata, "display_name")
            short_description = field(metadata, "short_description")
            if not display_name:
                errors.append(f"{metadata.relative_to(ROOT)}: missing interface.display_name")
            if not short_description:
                errors.append(f"{metadata.relative_to(ROOT)}: missing interface.short_description")

            rule = rules.get(name)
            if rule is None:
                errors.append(f"{name}: missing entry in {MANIFEST.relative_to(ROOT)}")
                continue
            kind = rule.get("kind")
            if kind not in {"generic", "service", "domain"}:
                errors.append(f"{name}: invalid kind {kind!r}")
                continue
            if kind == "generic":
                if set(rule) != {"kind"}:
                    errors.append(f"{name}: generic skill must not define prefixes")
                continue

            skill_prefix = rule.get("skill_name_prefix")
            display_prefix = rule.get("display_name_prefix")
            if not isinstance(skill_prefix, str) or not name.startswith(f"{skill_prefix}-"):
                errors.append(f"{name}: must start with {skill_prefix!r}-")
            if not isinstance(display_prefix, str) or not display_name or not display_name.startswith(f"{display_prefix} "):
                errors.append(f"{metadata.relative_to(ROOT)}: display_name must start with {display_prefix!r} followed by one space")

    for name in sorted(set(rules) - set(found)):
        errors.append(f"{MANIFEST.relative_to(ROOT)}: declares unknown skill {name!r}")

    if errors:
        print("Skill naming validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"OK: {len(found)} skill(s) match naming and UI metadata rules.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
