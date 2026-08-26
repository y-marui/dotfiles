#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/_links.sh
source "$(dirname "${BASH_SOURCE[0]}")/_links.sh"

link_points_inside() {
  local destination="$1"
  local source_root="$2"
  local link_target

  [[ -L "${destination}" ]] || return 1
  link_target="$(readlink "${destination}")"
  [[ "${link_target}" == "${source_root}" || "${link_target}" == "${source_root}/"* ]]
}

list_managed_links() {
  local source_root="$1"
  shift
  local entry destination

  for entry in "$@"; do
    destination="${entry##*|}"
    if link_points_inside "${destination}" "${source_root}"; then
      echo "  ${destination}"
    fi
  done
}

remove_link_set() {
  local source_root="$1"
  shift
  local entry destination

  for entry in "$@"; do
    destination="${entry##*|}"
    if link_points_inside "${destination}" "${source_root}"; then
      rm "${destination}"
      echo "  REMOVED ${destination}"
      (( count_removed++ )) || true
    elif [[ -L "${destination}" ]]; then
      echo "  SKIP    ${destination} (管理対象外を指すリンク)"
      (( count_skip++ )) || true
    else
      (( count_skip++ )) || true
    fi
  done
}

# --yes オプションで確認をスキップ
skip_confirm=false
for arg in "$@"; do
  if [[ "${arg}" == "--yes" ]]; then
    skip_confirm=true
  fi
done

if [[ "${skip_confirm}" == false ]]; then
  echo "以下のシンボリックリンクを削除します（dotfiles / dotfiles-private を指すもののみ）:"
  list_managed_links "${DOTFILES_DIR}" "${LINKS[@]}"
  if [[ -f "${PRIVATE_LINKS_FILE}" ]]; then
    list_managed_links "${PRIVATE_DIR}" "${PRIVATE_LINKS[@]}" "${PRIVATE_INACTIVE_LINKS[@]}"
  fi
  echo ""
  read -r -p "続けますか？ [y/N]: " answer
  if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
    echo "キャンセルしました。"
    exit 0
  fi
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  bash "${DOTFILES_DIR}/macos/setup_dots_check_launchagent.sh" uninstall
fi

count_removed=0
count_skip=0

remove_link_set "${DOTFILES_DIR}" "${LINKS[@]}"
if [[ -f "${PRIVATE_LINKS_FILE}" ]]; then
  remove_link_set "${PRIVATE_DIR}" "${PRIVATE_LINKS[@]}" "${PRIVATE_INACTIVE_LINKS[@]}"
fi

echo ""
echo "完了: 削除=${count_removed}  スキップ=${count_skip}"
