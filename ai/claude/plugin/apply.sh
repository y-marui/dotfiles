#!/usr/bin/env bash
# apply.sh
# plugins.json にあって未導入の marketplace / plugin を追加する
#
# 動作:
#   1. ~/.claude/plugins/{installed_plugins,known_marketplaces}.json を直接読む
#   2. 不足している marketplace を追加
#   3. 不足している plugin をインストール
#   4. 未宣言のものは削除しない
#
# 使い方:
#   bash ai/claude/plugin/apply.sh
#   dots claude apply --plugin-only

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PLUGINS_FILE="$DOTFILES_DIR/ai/claude/plugin/plugins.json"
INSTALLED_JSON="$HOME/.claude/plugins/installed_plugins.json"
MARKETPLACES_JSON="$HOME/.claude/plugins/known_marketplaces.json"

echo "==> Adding missing marketplaces / plugins from plugins.json..."
python3 - "$PLUGINS_FILE" "$INSTALLED_JSON" "$MARKETPLACES_JSON" << 'PYEOF'
import json
import subprocess
import sys

declared_path, installed_path, marketplaces_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(declared_path, encoding="utf-8") as f:
    declared = json.load(f)

def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

actual_mkt = set(load_json(marketplaces_path).keys())
actual_plugins = set(load_json(installed_path).get("plugins", {}).keys())

missing_mkt = [m for m in declared.get("marketplaces", []) if m["name"] not in actual_mkt]
missing_plugins = [p for p in declared.get("plugins", []) if p not in actual_plugins]

if not missing_mkt and not missing_plugins:
    print("  (already up to date)")
    sys.exit(0)

for mkt in missing_mkt:
    print(f"  marketplace add  {mkt['name']}")
    subprocess.run(
        ["claude", "plugin", "marketplace", "add", mkt["repo"]],
        check=True,
        stdout=subprocess.DEVNULL,
    )

for plugin in missing_plugins:
    print(f"  install  {plugin}")
    subprocess.run(
        ["claude", "plugin", "install", "-s", "user", plugin],
        check=True,
        stdout=subprocess.DEVNULL,
    )
PYEOF
