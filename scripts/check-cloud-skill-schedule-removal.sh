#!/usr/bin/env bash
# ai/skills/cloud.json で scheduled_tasks が設定されたskillのエントリ削除、または
# synced_hashの削除を検知する。claude.aiのScheduled Taskから参照されているskillを
# うっかりcloud側から外せなくするためのガード（今後も同種のskillが増える前提）。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MANIFEST_REL="ai/skills/cloud.json"
MANIFEST="${DOTFILES_DIR}/${MANIFEST_REL}"

[[ -f "${MANIFEST}" ]] || exit 0

python3 - "${DOTFILES_DIR}" "${MANIFEST_REL}" <<'PYEOF'
import json
import subprocess
import sys

dotfiles_dir, manifest_rel = sys.argv[1:]


def load(text):
    return {entry["name"]: entry for entry in json.loads(text).get("skills", [])}


try:
    old_text = subprocess.run(
        ["git", "-C", dotfiles_dir, "show", f"HEAD:{manifest_rel}"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
except subprocess.CalledProcessError:
    old_text = '{"skills": []}'

with open(f"{dotfiles_dir}/{manifest_rel}", encoding="utf-8") as file:
    new_text = file.read()

old_by_name = load(old_text)
new_by_name = load(new_text)

blocked = []
for name, old_entry in old_by_name.items():
    tasks = old_entry.get("scheduled_tasks") or []
    if not tasks:
        continue
    new_entry = new_by_name.get(name)
    if new_entry is None:
        blocked.append((name, tasks, "cloud.jsonのエントリごと削除"))
    elif old_entry.get("synced_hash") and not new_entry.get("synced_hash"):
        blocked.append((name, tasks, "synced_hashの削除"))

if blocked:
    for name, tasks, reason in blocked:
        print(
            f"Error: {name} はclaude.aiのScheduled Task {tasks} から参照されているため、"
            f"{reason}を拒否しました。",
            file=sys.stderr,
        )
    print(
        "  claude.ai側で該当Scheduled Taskを削除・付け替えてから、"
        "ai/skills/cloud.jsonのscheduled_tasksを空にしてください。",
        file=sys.stderr,
    )
    sys.exit(1)
PYEOF
