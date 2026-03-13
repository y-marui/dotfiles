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

echo ""
echo "編集してください:"
echo "  ${ZSH_FILE}"
echo "  ${GIT_FILE}"
