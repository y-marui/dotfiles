#!/usr/bin/env bash
# apply_packages.sh
# rpi/packages.txt に列挙された apt パッケージをインストールする
#
# 使い方:
#   DOTFILES_DIR=~/dotfiles bash rpi/apply_packages.sh
#   make rpi-packages

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
PACKAGES_FILE="$DOTFILES_DIR/rpi/packages.txt"

mapfile -t packages < <(grep -vE '^\s*(#|$)' "$PACKAGES_FILE")

echo "==> Installing packages from rpi/packages.txt..."
sudo apt-get update
sudo apt-get install -y "${packages[@]}"
