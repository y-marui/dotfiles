#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPTS_DIR}/.env"
ENV_EXAMPLE="${SCRIPTS_DIR}/.env.example"

# .env が存在しない場合は案内して終了
if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_EXAMPLE}" "${ENV_FILE}"
  echo "scripts/.env を作成しました。"
  echo "PRIVATE_REPO を設定してから再実行してください:"
  echo "  ${ENV_FILE}"
  exit 1
fi

# .env を読み込む
# shellcheck source=/dev/null
source "${ENV_FILE}"

# PRIVATE_REPO の確認
if [[ -z "${PRIVATE_REPO:-}" || "${PRIVATE_REPO}" == "owner/repo" ]]; then
  echo "エラー: scripts/.env に有効な PRIVATE_REPO を設定してください。"
  exit 1
fi

# gh コマンドの存在確認
if ! command -v gh &> /dev/null; then
  echo "エラー: gh コマンドが見つかりません。"
  echo "  brew install gh"
  exit 1
fi

# gh 認証確認
if ! gh auth status &> /dev/null; then
  echo "エラー: gh が認証されていません。"
  echo "  gh auth login"
  exit 1
fi

DOTFILES_DIR="$(cd "${SCRIPTS_DIR}/.." && pwd)"
PRIVATE_DIR="${DOTFILES_DIR%-private}-private"

read -r -p "${PRIVATE_DIR} に取得しますか？ [y/N]: " answer
if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
  echo "キャンセルしました。"
  exit 0
fi

if [[ -d "${PRIVATE_DIR}/.git" ]]; then
  echo "既存の ${PRIVATE_DIR} を更新します..."
  git -C "${PRIVATE_DIR}" pull
else
  gh repo clone "${PRIVATE_REPO}" "${PRIVATE_DIR}"
fi

# setup.sh を実行してシンボリックリンクを作成
if [[ -f "${PRIVATE_DIR}/setup.sh" ]]; then
  bash "${PRIVATE_DIR}/setup.sh"
else
  echo "警告: ${PRIVATE_DIR}/setup.sh が見つかりません。"
  echo "シンボリックリンクは手動で作成してください。"
fi
