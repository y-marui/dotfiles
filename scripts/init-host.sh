#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOSTNAME="$(hostname -s)"
HOST_DIR="${DOTFILES_DIR}/host"

mkdir -p "${HOST_DIR}"

# host/.gitignore（既存ならスキップ）
if [[ ! -f "${HOST_DIR}/.gitignore" ]]; then
  printf '*\n!.gitignore\n' > "${HOST_DIR}/.gitignore"
fi

# host/${HOSTNAME}.zsh テンプレート
ZSH_FILE="${HOST_DIR}/${HOSTNAME}.zsh"
if [[ ! -f "${ZSH_FILE}" ]]; then
  cat > "${ZSH_FILE}" <<EOF
# Host-specific zsh settings for: ${HOSTNAME}
# This file is NOT committed to git.
#
# Usage: put machine-specific env vars, paths, and secrets here.
# Example:
#   export WORK_DIR="\$HOME/Work"
#   export SOME_API_KEY=""
#
# マシン固有設定の例:
#   export GHQ_ROOT="\$HOME/src"
#
#   # ghq 等で ~/dotfiles 以外にクローンした場合は設定する
#   export DOTFILES_DIR="/path/to/dotfiles"
#
#   # brew search 等で GitHub API レート制限に当たる場合に設定（任意）
#   export HOMEBREW_GITHUB_API_TOKEN=""
EOF
  echo "作成: ${ZSH_FILE}"
else
  echo "既存: ${ZSH_FILE} (スキップ)"
fi

# host/${HOSTNAME}.gitconfig テンプレート
GIT_FILE="${HOST_DIR}/${HOSTNAME}.gitconfig"
if [[ ! -f "${GIT_FILE}" ]]; then
  cat > "${GIT_FILE}" <<EOF
# Host-specific git settings for: ${HOSTNAME}
# This file is NOT committed to git.
# Reference this from ~/.gitconfig.local if needed.
#
# [user]
#     name = Your Name
#     email = your@email.com
EOF
  echo "作成: ${GIT_FILE}"
else
  echo "既存: ${GIT_FILE} (スキップ)"
fi

# 変数が active / commented どちらの形でも存在しない場合のみ追記するヘルパー
_append_if_missing() {
  local target_file="$1"
  local var_name="$2"
  local description="$3"
  local example_value="$4"
  if grep -qE "^\s*#?\s*export\s+${var_name}=" "${target_file}" 2>/dev/null; then
    return 0
  fi
  {
    echo ""
    echo "# ${description}"
    echo "# export ${var_name}=\"${example_value}\""
  } >> "${target_file}"
  echo "追記: ${target_file} に ${var_name} を追加"
}

# ~/.zshrc.local — 変数が未設定の場合のみコメントアウトで追記
ZSHRC_LOCAL="${HOME}/.zshrc.local"

if [[ ! -f "${ZSHRC_LOCAL}" ]]; then
  touch "${ZSHRC_LOCAL}"
  echo "作成: ${ZSHRC_LOCAL}"
fi

_append_if_missing "${ZSHRC_LOCAL}" "DOTFILES_DIR" \
  "dotfiles のクローン先（~/dotfiles 以外にクローンした場合は設定する）" \
  "/path/to/dotfiles"


_append_if_missing "${ZSHRC_LOCAL}" "HOMEBREW_GITHUB_API_TOKEN" \
  "brew search 等で GitHub API レート制限に当たる場合に設定（任意）" \
  ""

# ~/.bashrc.local — 変数が未設定の場合のみコメントアウトで追記
BASHRC_LOCAL="${HOME}/.bashrc.local"

if [[ ! -f "${BASHRC_LOCAL}" ]]; then
  touch "${BASHRC_LOCAL}"
  echo "作成: ${BASHRC_LOCAL}"
fi

_append_if_missing "${BASHRC_LOCAL}" "DOTFILES_DIR" \
  "dotfiles のクローン先（~/dotfiles 以外にクローンした場合は設定する）" \
  "/path/to/dotfiles"


_append_if_missing "${BASHRC_LOCAL}" "HOMEBREW_GITHUB_API_TOKEN" \
  "brew search 等で GitHub API レート制限に当たる場合に設定（任意）" \
  ""

# macos/Brewfile.local テンプレート（存在しない場合のみ）
BREWFILE_LOCAL="${DOTFILES_DIR}/macos/Brewfile.local"
if [[ ! -f "${BREWFILE_LOCAL}" ]]; then
  cat > "${BREWFILE_LOCAL}" <<'EOF'
# Brewfile.local — このマシン固有の Homebrew パッケージ
# このファイルは git 管理外（.gitignore 済み）。
#
# 書き方: Brewfile と同じ形式で記述する。
#
# brew "パッケージ名"          # CLI ツール
# cask "アプリ名"              # GUI アプリ（Cask）
# tap "tap名/リポジトリ"       # Tap
# mas "アプリ名", id: XXXXXXX  # Mac App Store
# vscode "拡張機能ID"          # VS Code 拡張
#
# 自動整合（make brew-sync 実行時）:
#   - システムからアンインストールされたパッケージは自動で除去される
#   - メインの Brewfile に追記されたパッケージは自動で除去される（重複防止）
EOF
  echo "作成: ${BREWFILE_LOCAL}"
else
  echo "既存: ${BREWFILE_LOCAL} (スキップ)"
fi

echo ""
echo "編集してください:"
echo "  ${ZSH_FILE}"
echo "  ${GIT_FILE}"
echo "  ${ZSHRC_LOCAL}"
echo "  ${BASHRC_LOCAL}"
echo "  ${BREWFILE_LOCAL}"
