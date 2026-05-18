#!/usr/bin/env zsh
source ~/.zshrc || true
set -euo pipefail

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update started ==="

brew update
brew upgrade
brew cleanup

pipx upgrade-all

npm update -g

sudo tlmgr update --self --all

if command -v rbenv &>/dev/null && [[ "$(rbenv version-name 2>/dev/null)" != "system" ]]; then
  gem update --system
  gem update
  gem cleanup
fi

command -v zprezto-update &>/dev/null && zprezto-update

mas upgrade
softwareupdate -i -a

ghq-update --all

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update completed ==="
