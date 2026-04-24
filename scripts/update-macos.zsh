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

gem update --system
gem update
gem cleanup

command -v zprezto-update &>/dev/null && zprezto-update

mas upgrade
softwareupdate -i -a

ghq-update --all

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update completed ==="
