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
#   # Claude Code の完了通知に使う ntfy.sh トピック（任意）
#   export NTFY_TOPIC="your-topic"
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

# ~/.zshrc.local — 変数が未設定の場合のみコメントアウトで追記
ZSHRC_LOCAL="${HOME}/.zshrc.local"

if [[ ! -f "${ZSHRC_LOCAL}" ]]; then
  touch "${ZSHRC_LOCAL}"
  echo "作成: ${ZSHRC_LOCAL}"
fi

# 変数が active / commented どちらの形でも存在しない場合のみ追記するヘルパー
_zshrc_append_if_missing() {
  local var_name="$1"
  local description="$2"
  local example_value="$3"
  if grep -qE "^\s*#?\s*export\s+${var_name}=" "${ZSHRC_LOCAL}" 2>/dev/null; then
    return 0
  fi
  {
    echo ""
    echo "# ${description}"
    echo "# export ${var_name}=\"${example_value}\""
  } >> "${ZSHRC_LOCAL}"
  echo "追記: ${ZSHRC_LOCAL} に ${var_name} を追加"
}

_zshrc_append_if_missing "DOTFILES_DIR" \
  "dotfiles のクローン先（~/dotfiles 以外にクローンした場合は設定する）" \
  "/path/to/dotfiles"

_zshrc_append_if_missing "NTFY_TOPIC" \
  "Claude Code の完了通知に使う ntfy.sh トピック（任意）" \
  "your-topic"

_zshrc_append_if_missing "HOMEBREW_GITHUB_API_TOKEN" \
  "brew search 等で GitHub API レート制限に当たる場合に設定（任意）" \
  ""

echo ""
echo "編集してください:"
echo "  ${ZSH_FILE}"
echo "  ${GIT_FILE}"
echo "  ${ZSHRC_LOCAL}"
