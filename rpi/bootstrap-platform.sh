#!/usr/bin/env bash
# Rebuild the host foundation without starting a second Homebridge instance.
set -euo pipefail

if [[ "$(uname -s)" != Linux ]] || ! grep -q 'Raspberry Pi' /proc/device-tree/model; then
  echo "ERROR: Raspberry Pi Linux only" >&2
  exit 1
fi
# shellcheck source=/dev/null
source /etc/os-release
if [[ "${VERSION_CODENAME:-}" != trixie ]]; then
  echo "ERROR: install or upgrade to Trixie before bootstrap" >&2
  exit 1
fi
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export DOTFILES_DIR="$repo_dir"
bash "$repo_dir/rpi/apply_packages.sh"
bash "$repo_dir/scripts/setup-prezto.sh"
bash "$repo_dir/scripts/install.sh"
bash "$repo_dir/rpi/repos/setup_tailscale.sh"
bash "$repo_dir/rpi/repos/setup_docker.sh"
bash "$repo_dir/scripts/setup-zellij.sh"
bash "$repo_dir/rpi/setup_zsh.sh"
bash "$repo_dir/rpi/setup_gpg_agent.sh"
echo "Host foundation ready. Authenticate Tailscale and load the Pi SSH key if needed."
echo "Restore Homebridge only after stopping the old instance; see docs/raspberry-pi-platform.md."
