#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/_links.sh
source "$(dirname "${BASH_SOURCE[0]}")/_links.sh"

# --yes オプションで確認をスキップ
skip_confirm=false
for arg in "$@"; do
  if [[ "${arg}" == "--yes" ]]; then
    skip_confirm=true
  fi
done

if [[ "${skip_confirm}" == false ]]; then
  echo "以下のシンボリックリンクを削除します（dotfiles を指すもののみ）:"
  for entry in "${LINKS[@]}"; do
    dest="${entry##*|}"
    if [[ -L "${dest}" ]]; then
      link_target="$(readlink "${dest}")"
      if [[ "${link_target}" == "${DOTFILES_DIR}"* ]]; then
        echo "  ${dest}"
      fi
    fi
  done
  echo ""
  read -r -p "続けますか？ [y/N]: " answer
  if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
    echo "キャンセルしました。"
    exit 0
  fi
fi

count_removed=0
count_skip=0

for entry in "${LINKS[@]}"; do
  dest="${entry##*|}"

  if [[ -L "${dest}" ]]; then
    link_target="$(readlink "${dest}")"
    if [[ "${link_target}" == "${DOTFILES_DIR}"* ]]; then
      rm "${dest}"
      echo "  REMOVED ${dest}"
      (( count_removed++ )) || true
    else
      echo "  SKIP    ${dest} (dotfiles 以外を指すリンク)"
      (( count_skip++ )) || true
    fi
  else
    (( count_skip++ )) || true
  fi
done

echo ""
echo "完了: 削除=${count_removed}  スキップ=${count_skip}"
