#!/usr/bin/env bash
# Merge this Mac's current application shortcuts into the managed private
# configuration without discarding entries the managed file already has.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
exec python3 "${DOTFILES_DIR}/macos/keyboard_shortcuts.py" merge
