#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/_links.sh
source "$(dirname "${BASH_SOURCE[0]}")/_links.sh"

BACKUP_DIR="${HOME}/.dotfiles-backup/$(date +%Y%m%d%H%M%S)"

count_ok=0
count_skip=0
count_backup=0

for entry in "${LINKS[@]}"; do
  src="${DOTFILES_DIR}/${entry%%|*}"
  dest="${entry##*|}"

  # ソースファイルが存在しない場合はスキップ
  if [[ ! -e "${src}" ]]; then
    echo "  SKIP    ${src} (ファイルが存在しません)"
    (( count_skip++ )) || true
    continue
  fi

  # リンク先のディレクトリを作成
  dest_dir="$(dirname "${dest}")"
  if [[ ! -d "${dest_dir}" ]]; then
    mkdir -p "${dest_dir}"
  fi

  # リンク先がすでにシンボリックリンクの場合: 上書き
  if [[ -L "${dest}" ]]; then
    ln -sfn "${src}" "${dest}"
    echo "  LINK    ${dest} -> ${src}"
    (( count_ok++ )) || true

  # リンク先が実ファイルの場合: バックアップして置換
  elif [[ -e "${dest}" ]]; then
    mkdir -p "${BACKUP_DIR}"
    mv "${dest}" "${BACKUP_DIR}/"
    ln -sfn "${src}" "${dest}"
    echo "  BACKUP  ${dest} -> ${BACKUP_DIR}/$(basename "${dest}")"
    echo "  LINK    ${dest} -> ${src}"
    (( count_backup++ )) || true
    (( count_ok++ )) || true

  # リンク先が存在しない場合: 新規作成
  else
    ln -sfn "${src}" "${dest}"
    echo "  LINK    ${dest} -> ${src}"
    (( count_ok++ )) || true
  fi
done

echo ""
echo "完了: リンク=${count_ok}  スキップ=${count_skip}  バックアップ=${count_backup}"
if [[ "${count_backup}" -gt 0 ]]; then
  echo "バックアップ先: ${BACKUP_DIR}"
fi
