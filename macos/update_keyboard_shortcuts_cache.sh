#!/usr/bin/env bash
# Save a diagnostic snapshot of this Mac's current application shortcuts.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
exec python3 "${DOTFILES_DIR}/macos/keyboard_shortcuts.py" cache
