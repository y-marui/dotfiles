#!/usr/bin/env bash
# diff.sh
# ~/.claude/plugins/{installed_plugins,known_marketplaces}.json（システム実態）と
# plugins.json（管理ファイル）の差分を表示する
#
# `claude plugin list --json` / `marketplace list --json` は CLI 起動に3秒前後かかるため、
# 代わりに実体である JSON ファイルを直接読む（0.2秒程度）。Claude.app（GUI）経由の
# インストールも同じファイルに書き込まれるため、CLI 経由かどうかを問わず検知できる。
# ただしこれらは非公開の内部ファイルなので、Claude Code のバージョンアップで
# 形式が変わる可能性がある点は留意する。
#
# 使い方:
#   bash ai/claude/plugin/diff.sh           # 差分を詳細表示
#   bash ai/claude/plugin/diff.sh --summary # 1行サマリーのみ出力
#
# 実体ファイルまたは plugins.json が見つからない場合は終了コード 1 で何も出力しない

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PLUGINS_FILE="$DOTFILES_DIR/ai/claude/plugin/plugins.json"
INSTALLED_JSON="$HOME/.claude/plugins/installed_plugins.json"
MARKETPLACES_JSON="$HOME/.claude/plugins/known_marketplaces.json"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

if [[ ! -f "$PLUGINS_FILE" || ! -f "$INSTALLED_JSON" || ! -f "$MARKETPLACES_JSON" ]]; then
  exit 1
fi

python3 - "$PLUGINS_FILE" "$INSTALLED_JSON" "$MARKETPLACES_JSON" "$SUMMARY_MODE" << 'PYEOF'
import json
import sys

declared_path, installed_path, marketplaces_path, summary_mode = (
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
)

with open(declared_path, encoding="utf-8") as f:
    declared = json.load(f)
with open(installed_path, encoding="utf-8") as f:
    installed = json.load(f)
with open(marketplaces_path, encoding="utf-8") as f:
    marketplaces = json.load(f)

declared_mkt = {m["name"] for m in declared.get("marketplaces", [])}
actual_mkt = set(marketplaces.keys())
declared_plugins = set(declared.get("plugins", []))
actual_plugins = set(installed.get("plugins", {}).keys())

only_in_actual = sorted(actual_mkt - declared_mkt) + sorted(actual_plugins - declared_plugins)
only_in_files = sorted(declared_mkt - actual_mkt) + sorted(declared_plugins - actual_plugins)

if summary_mode:
    parts = []
    if only_in_actual:
        parts.append(f"+{len(only_in_actual)} actual のみ")
    if only_in_files:
        parts.append(f"-{len(only_in_files)} files のみ")
    if parts:
        print(" / ".join(parts))
    sys.exit(0)

if not only_in_actual and not only_in_files:
    print("No diff: 実際のインストール状態と plugins.json は一致しています。")
    sys.exit(0)

if only_in_actual:
    print("インストール済みだが plugins.json 未記載 (+actual のみ):")
    for name in only_in_actual:
        print(f"  [+actual]  {name}")
    print()
if only_in_files:
    print("plugins.json にあるが未インストール (-files のみ):")
    for name in only_in_files:
        print(f"  [-files]  {name}")

sys.exit(1)
PYEOF
