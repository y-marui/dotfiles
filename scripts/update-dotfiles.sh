#!/usr/bin/env bash
set -euo pipefail

dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -d "${dotfiles_dir}/.git" ]]; then
  echo "error: ${dotfiles_dir} is not a Git repository" >&2
  exit 1
fi

if [[ -n "$(git -C "${dotfiles_dir}" status --short)" ]]; then
  echo "  SKIP    dotfiles pull (working tree has local changes)"
elif git -C "${dotfiles_dir}" rev-parse --verify '@{upstream}' >/dev/null 2>&1; then
  git -C "${dotfiles_dir}" pull --ff-only
  echo "  UPDATE  dotfiles (${dotfiles_dir})"
else
  echo "  SKIP    dotfiles pull (upstream is not configured)"
fi

# Existing links reflect file edits immediately, but rerunning the installer also
# applies links that were added by the update.
bash "${dotfiles_dir}/scripts/install.sh"

if [[ "$(uname -s)" == "Darwin" ]]; then
  bash "${dotfiles_dir}/macos/setup_dots_check_launchagent.sh" install
fi
