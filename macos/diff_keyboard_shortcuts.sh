#!/usr/bin/env bash
# Compare the managed application shortcuts with the current macOS preferences.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
exec python3 "${DOTFILES_DIR}/macos/keyboard_shortcuts.py" diff "$@"
