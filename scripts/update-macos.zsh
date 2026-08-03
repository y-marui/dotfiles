#!/usr/bin/env zsh
set -euo pipefail

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update started ==="

brew update
brew upgrade
brew cleanup

# Zellij is intentionally managed outside Homebrew while the iTerm2 rendering
# compatibility issue is open. Re-assert the approved version on every update.
bash "${0:A:h}/setup-zellij.sh"

pipx upgrade-all

npm update -g

sudo tlmgr update --self --all

if command -v rbenv &>/dev/null && [[ "$(rbenv version-name 2>/dev/null)" != "system" ]]; then
  gem update --system
  gem update
  gem cleanup
fi

bash "${0:A:h}/update-prezto.sh"

mas upgrade
softwareupdate -i -a

ghq-update --all

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update completed ==="
