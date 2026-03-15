#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPTS_DIR}/.env"
ENV_EXAMPLE="${SCRIPTS_DIR}/.env.example"

# .env が存在しない場合は案内して終了
if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_EXAMPLE}" "${ENV_FILE}"
  echo "scripts/.env を作成しました。"
  echo "GIST_ID を設定してから再実行してください:"
  echo "  ${ENV_FILE}"
  exit 1
fi

# .env を読み込む
# shellcheck source=/dev/null
source "${ENV_FILE}"

# GIST_ID の確認
if [[ -z "${GIST_ID:-}" || "${GIST_ID}" == "your_gist_id_here" ]]; then
  echo "エラー: scripts/.env に有効な GIST_ID を設定してください。"
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

# Gist の内容を表示
echo "Gist (${GIST_ID}) のファイル一覧:"
gh gist view "${GIST_ID}"
echo ""

DOTFILES_DIR="$(cd "${SCRIPTS_DIR}/.." && pwd)"
PRIVATE_DIR="${DOTFILES_DIR%-private}-private"

read -r -p "${PRIVATE_DIR} に取得しますか？ [y/N]: " answer
if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
  echo "キャンセルしました。"
  exit 0
fi
if [[ -d "${PRIVATE_DIR}" ]]; then
  echo "既存の ${PRIVATE_DIR} を更新します..."
  git -C "${PRIVATE_DIR}" pull
else
  gh gist clone "${GIST_ID}" "${PRIVATE_DIR}"
fi

# private gist の setup.sh を実行してシンボリックリンクを作成
# setup.sh の例（private gist で管理）:
#   #!/usr/bin/env bash
#   set -euo pipefail
#   PRIVATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   mkdir -p "${HOME}/.gitconfig.d" "${HOME}/.ssh"
#   ln -sf "${PRIVATE_DIR}/gitconfig.d-includes" "${HOME}/.gitconfig.d/includes"
#   ln -sf "${PRIVATE_DIR}/gitconfig.d-local"    "${HOME}/.gitconfig.d/local"
#   ln -sf "${PRIVATE_DIR}/gitconfig.d-private"  "${HOME}/.gitconfig.d/private"
#   ln -sf "${PRIVATE_DIR}/gitconfig.d-public"   "${HOME}/.gitconfig.d/public"
#   ln -sf "${PRIVATE_DIR}/gitconfig.d-overleaf" "${HOME}/.gitconfig.d/overleaf"
#   ln -sf "${PRIVATE_DIR}/ssh-config"           "${HOME}/.ssh/config"
#   echo "完了: ${PRIVATE_DIR}"
if [[ -f "${PRIVATE_DIR}/setup.sh" ]]; then
  bash "${PRIVATE_DIR}/setup.sh"
else
  echo "警告: ${PRIVATE_DIR}/setup.sh が見つかりません。"
  echo "シンボリックリンクは手動で作成してください。"
fi
