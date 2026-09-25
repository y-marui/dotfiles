#!/usr/bin/env bash
# Remove local-only application shortcuts that the managed file does not have.
# Options: --dry-run (show the plan only).
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
exec python3 "${DOTFILES_DIR}/macos/keyboard_shortcuts.py" prune "$@"
