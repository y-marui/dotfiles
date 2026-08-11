#!/usr/bin/env bash
# plugins.json 未記載の Claude Code plugin / marketplace を削除する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PLUGINS_FILE="${DOTFILES_DIR}/ai/claude/plugin/plugins.json"
INSTALLED_JSON="${HOME}/.claude/plugins/installed_plugins.json"
MARKETPLACES_JSON="${HOME}/.claude/plugins/known_marketplaces.json"

python3 - "${PLUGINS_FILE}" "${INSTALLED_JSON}" "${MARKETPLACES_JSON}" <<'PYEOF'
import json
import subprocess
import sys

declared_path, installed_path, marketplaces_path = sys.argv[1:]
with open(declared_path, encoding="utf-8") as file:
    declared = json.load(file)


def load(path):
    try:
        with open(path, encoding="utf-8") as file:
            return json.load(file)
    except FileNotFoundError:
        return {}


declared_plugins = set(declared.get("plugins", []))
declared_marketplaces = {entry["name"] for entry in declared.get("marketplaces", [])}
actual_plugins = set(load(installed_path).get("plugins", {}))
actual_marketplaces = set(load(marketplaces_path))
remove_plugins = sorted(actual_plugins - declared_plugins)
remove_marketplaces = sorted(actual_marketplaces - declared_marketplaces)

if not remove_plugins and not remove_marketplaces:
    print("  (nothing to prune)")
    raise SystemExit(0)

for name in remove_plugins:
    print(f"  uninstall  {name}")
    subprocess.run(
        ["claude", "plugin", "uninstall", "-s", "user", "--keep-data", name],
        check=True,
    )
for name in remove_marketplaces:
    print(f"  marketplace remove  {name}")
    subprocess.run(
        ["claude", "plugin", "marketplace", "remove", "--scope", "user", name],
        check=True,
    )
PYEOF
