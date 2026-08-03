#!/usr/bin/env bash
# Install the dotfiles-approved Zellij release into the user-local bin directory.

set -euo pipefail

readonly ZELLIJ_VERSION="0.43.1"
readonly INSTALL_DIR="${HOME}/.local/bin"
readonly INSTALL_PATH="${INSTALL_DIR}/zellij"

case "$(uname -s):$(uname -m)" in
  Darwin:arm64)  target="aarch64-apple-darwin" ;;
  Darwin:x86_64) target="x86_64-apple-darwin" ;;
  Linux:aarch64|Linux:arm64) target="aarch64-unknown-linux-musl" ;;
  Linux:x86_64) target="x86_64-unknown-linux-musl" ;;
  *)
    echo "Unsupported platform: $(uname -s) $(uname -m)" >&2
    exit 1
    ;;
esac

installed_version=""
if [[ -x "$INSTALL_PATH" ]]; then
  installed_version="$($INSTALL_PATH --version | awk '{print $2}')"
fi

if [[ "$installed_version" == "$ZELLIJ_VERSION" ]]; then
  echo "  SKIP    zellij $ZELLIJ_VERSION (installed at $INSTALL_PATH)"
  exit 0
fi

tmp_base="${TMPDIR:-/tmp}"
if [[ "$(uname -s)" == Linux && -d /var/tmp ]]; then
  # Some Raspberry Pi installations use a small tmpfs for /tmp.
  tmp_base="/var/tmp"
fi
tmpdir="$(mktemp -d "${tmp_base%/}/dotfiles-zellij.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

archive="$tmpdir/zellij.tar.gz"
download_url="https://github.com/zellij-org/zellij/releases/download/v${ZELLIJ_VERSION}/zellij-${target}.tar.gz"
checksum="$tmpdir/zellij.sha256sum"
checksum_url="https://github.com/zellij-org/zellij/releases/download/v${ZELLIJ_VERSION}/zellij-${target}.sha256sum"

echo "==> Installing Zellij $ZELLIJ_VERSION ($target)..."
curl -fsSL "$download_url" -o "$archive"
curl -fsSL "$checksum_url" -o "$checksum"
tar -xzf "$archive" -C "$tmpdir"

# Zellij's release checksum contains the build-time path to the uncompressed
# binary. Compare just its digest against the extracted release binary.
expected_checksum="$(awk '{print $1}' "$checksum")"
if command -v shasum >/dev/null 2>&1; then
  actual_checksum="$(shasum -a 256 "$tmpdir/zellij" | awk '{print $1}')"
else
  actual_checksum="$(sha256sum "$tmpdir/zellij" | awk '{print $1}')"
fi
if [[ "$actual_checksum" != "$expected_checksum" ]]; then
  echo "Zellij checksum verification failed" >&2
  exit 1
fi
echo "zellij: checksum verified"

downloaded_version="$("$tmpdir/zellij" --version | awk '{print $2}')"
if [[ "$downloaded_version" != "$ZELLIJ_VERSION" ]]; then
  echo "Unexpected Zellij version: expected $ZELLIJ_VERSION, got $downloaded_version" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
install -m 0755 "$tmpdir/zellij" "$INSTALL_PATH"

if [[ -n "$installed_version" ]]; then
  echo "  CHANGE  zellij $installed_version -> $ZELLIJ_VERSION ($INSTALL_PATH)"
else
  echo "  INSTALL zellij $ZELLIJ_VERSION ($INSTALL_PATH)"
fi
