#!/usr/bin/env bash
# setup_zellij.sh
# zellij を GitHub Releases のビルド済みバイナリから /usr/local/sbin に配置する
# （Debian の apt リポジトリに zellij パッケージが存在しないため）
#
# /usr/local/sbin を使うのは、このマシンで過去に手動導入された zellij が
# 同じ場所に置かれており、shell/profile の PATH 順序（/usr/local/sbin が
# ~/.local/bin より前）でもそちらが優先されるため。同じ場所を上書き管理する。
#
# 使い方:
#   bash rpi/setup_zellij.sh

set -euo pipefail

INSTALL_DIR="/usr/local/sbin"
INSTALLED_VERSION=""
if [[ -x "$INSTALL_DIR/zellij" ]]; then
  INSTALLED_VERSION="$("$INSTALL_DIR/zellij" --version | awk '{print $2}')"
fi

ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64) TARGET="aarch64-unknown-linux-musl" ;;
  x86_64)        TARGET="x86_64-unknown-linux-musl" ;;
  *)             echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

# /tmp は tmpfs で容量が小さいため /var/tmp を使う（展開後バイナリが約 40MB になる）
tmpdir="$(mktemp -d --tmpdir=/var/tmp)"
trap 'rm -rf "$tmpdir"' EXIT

curl -fsSL "https://github.com/zellij-org/zellij/releases/latest/download/zellij-${TARGET}.tar.gz" \
  -o "$tmpdir/zellij.tar.gz"
tar -xzf "$tmpdir/zellij.tar.gz" -C "$tmpdir"

LATEST_VERSION="$("$tmpdir/zellij" --version | awk '{print $2}')"
if [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]]; then
  echo "  SKIP    zellij $INSTALLED_VERSION (インストール済み)"
  exit 0
fi

sudo install -m 0755 "$tmpdir/zellij" "$INSTALL_DIR/zellij"

if [[ -n "$INSTALLED_VERSION" ]]; then
  echo "  UPGRADE zellij $INSTALLED_VERSION -> $LATEST_VERSION"
else
  echo "  INSTALL zellij $LATEST_VERSION"
fi
