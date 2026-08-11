#!/usr/bin/env bash
# cache.sh
# 現在インストール済みの marketplace / plugin を plugins.cache.json に記録する
#
# 使い方:
#   bash ai/claude/plugin/cache.sh
#   dots claude cache --plugin-only

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
CACHE_FILE="$DOTFILES_DIR/ai/claude/plugin/plugins.cache.json"

MARKETPLACES_TMP="$(mktemp)"
PLUGINS_TMP="$(mktemp)"
trap 'rm -f "$MARKETPLACES_TMP" "$PLUGINS_TMP"' EXIT

claude plugin marketplace list --json > "$MARKETPLACES_TMP"
claude plugin list --json > "$PLUGINS_TMP"

python3 - "$MARKETPLACES_TMP" "$PLUGINS_TMP" "$CACHE_FILE" << 'PYEOF'
import json
import sys

marketplaces_path, plugins_path, cache_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(marketplaces_path, encoding="utf-8") as f:
    marketplaces = json.load(f)
with open(plugins_path, encoding="utf-8") as f:
    plugins = json.load(f)

out = {
    "marketplaces": sorted(
        (
            {"name": m["name"], "repo": m.get("repo")}
            for m in marketplaces
            if m.get("source") == "github"
        ),
        key=lambda m: m["name"],
    ),
    "plugins": sorted(p["id"] for p in plugins),
}

with open(cache_path, "w", encoding="utf-8") as f:
    json.dump(out, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"plugins.cache.json updated: {len(out['marketplaces'])} marketplace(s), {len(out['plugins'])} plugin(s).")
PYEOF
