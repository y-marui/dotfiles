#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_DIR="${DOTFILES_DIR}/templates/dotfiles-private"
DESTINATION="${1:-${DOTFILES_DIR}-private}"

if [[ -e "${DESTINATION}" || -L "${DESTINATION}" ]]; then
  echo "エラー: 生成先が既に存在します: ${DESTINATION}" >&2
  echo "既存リポジトリを上書きしません。別の PRIVATE_SCAFFOLD_DIR を指定してください。" >&2
  exit 1
fi

mkdir -p "${DESTINATION}"
cp -R "${TEMPLATE_DIR}/." "${DESTINATION}/"
git init -b main "${DESTINATION}" >/dev/null

printf 'dotfiles-private の安全な雛形を生成しました: %s\n' "${DESTINATION}"
printf '%s\n' \
  'README.md に従って .example から実設定を作成してください。' \
  '設定完了後に .dotfiles-private-scaffold を削除し、make private-validate を実行してください。'
