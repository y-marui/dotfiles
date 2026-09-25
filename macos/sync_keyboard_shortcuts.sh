#!/usr/bin/env bash
# Make this Mac's current application shortcuts the managed private configuration.
# Options: --dry-run (show the plan only), --yes (required when entries would be removed).
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
exec python3 "${DOTFILES_DIR}/macos/keyboard_shortcuts.py" sync "$@"
