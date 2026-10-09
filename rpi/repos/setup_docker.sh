#!/usr/bin/env bash
# Docker Engine and the Compose plugin from Docker's signed Debian repository.
set -euo pipefail

if [[ "$(uname -s)" != Linux ]] || ! grep -q 'Raspberry Pi' /proc/device-tree/model; then
  echo "ERROR: Raspberry Pi Linux only" >&2
  exit 1
fi
# shellcheck source=/dev/null
source /etc/os-release
case "${VERSION_CODENAME:-}" in
  bookworm|trixie) ;;
  *) echo "ERROR: unsupported Debian release" >&2; exit 1 ;;
esac

# Do not silently replace a different container runtime or remove its data.
for pkg in docker.io docker-compose podman-docker containerd runc; do
  if [[ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)" == 'install ok installed' ]]; then
    echo "ERROR: conflicting package $pkg; review its workloads before removal" >&2
    exit 1
  fi
done

sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -d -m 0755 /etc/apt/keyrings
docker_key=$(mktemp)
trap 'rm -f "$docker_key"' EXIT
curl -fsSL https://download.docker.com/linux/debian/gpg -o "$docker_key"
sudo install -m 0644 "$docker_key" /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $VERSION_CODENAME
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker info >/dev/null
sudo docker compose version
