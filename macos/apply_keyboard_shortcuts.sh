#!/usr/bin/env bash
# Apply managed application shortcuts while preserving unlisted shortcuts.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
exec python3 "${DOTFILES_DIR}/macos/keyboard_shortcuts.py" apply
