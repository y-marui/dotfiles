#!/usr/bin/env bash
# plugins.json 未記載の Codex plugin を削除する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"

exec bash "${DOTFILES_DIR}/ai/codex/plugin/diff.sh" prune
