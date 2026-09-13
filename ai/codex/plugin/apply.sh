#!/usr/bin/env bash
# plugins.json にあって未導入の Codex plugin を追加する。未宣言 plugin は削除しない。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"

echo "==> Adding missing plugins from plugins.json..."
exec bash "${DOTFILES_DIR}/ai/codex/plugin/diff.sh" apply
