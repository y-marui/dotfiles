#!/usr/bin/env bash
# Make this Mac's current application shortcuts the managed private configuration.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
exec python3 "${DOTFILES_DIR}/macos/keyboard_shortcuts.py" sync
