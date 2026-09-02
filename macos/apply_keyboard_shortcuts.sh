#!/usr/bin/env bash
# Apply managed application shortcuts, removing any local-only shortcuts.
# Run 'dots shortcuts merge' first if you want to keep local-only shortcuts instead of losing them.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
exec python3 "${DOTFILES_DIR}/macos/keyboard_shortcuts.py" apply
