#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/_links.sh
source "$(dirname "${BASH_SOURCE[0]}")/_links.sh"

BACKUP_DIR="${HOME}/.dotfiles-backup/$(date +%Y%m%d%H%M%S)"

count_ok=0
count_skip=0
count_backup=0

# Codex の旧配置にある自作 skill を、削除せずバックアップへ退避する。
# ~/.codex/skills/.system や curated skills は対象にしない。
for skill_name in "${CODEX_LEGACY_SKILLS[@]}"; do
  src="${DOTFILES_DIR}/ai/codex/skills/${skill_name}"
  legacy_dest="${HOME}/.codex/skills/${skill_name}"

  if [[ ! -e "${src}" || ( ! -e "${legacy_dest}" && ! -L "${legacy_dest}" ) ]]; then
    continue
  fi

  legacy_backup_dir="${BACKUP_DIR}/codex-skills"
  mkdir -p "${legacy_backup_dir}"
  mv "${legacy_dest}" "${legacy_backup_dir}/${skill_name}"
  echo "  MIGRATE ${legacy_dest} -> ${legacy_backup_dir}/${skill_name}"
  (( count_backup++ )) || true
done

# 現行設定では使わない旧 zsh キャッシュを、削除せずバックアップへ退避する。
# Prezto の補完キャッシュは ~/.cache/prezto/zcompdump を使用する。
for legacy_cache in "${HOME}/.zcompdump" "${HOME}/.zcompdump.zwc"; do
  if [[ ! -e "${legacy_cache}" && ! -L "${legacy_cache}" ]]; then
    continue
  fi

  legacy_backup_dir="${BACKUP_DIR}/obsolete-shell"
  mkdir -p "${legacy_backup_dir}"
  mv "${legacy_cache}" "${legacy_backup_dir}/$(basename "${legacy_cache}")"
  echo "  MIGRATE ${legacy_cache} -> ${legacy_backup_dir}/$(basename "${legacy_cache}")"
  (( count_backup++ )) || true
done

# PowerShell / Oh My Posh は Windows 専用。過去の Unix インストーラーが作成した
# dotfiles 直結のリンクだけを退避し、ユーザーが独自に作成した設定には触れない。
legacy_windows_links=(
  "terminal/ohmyposh/p10k-lean.json|${HOME}/.config/oh-my-posh/p10k-lean.json"
  "terminal/powershell/profile.ps1|${HOME}/.config/powershell/Microsoft.PowerShell_profile.ps1"
)
for entry in "${legacy_windows_links[@]}"; do
  src="${DOTFILES_DIR}/${entry%%|*}"
  dest="${entry##*|}"
  if [[ ! -L "${dest}" || "$(readlink "${dest}")" != "${src}" ]]; then
    continue
  fi

  legacy_backup_dir="${BACKUP_DIR}/obsolete-shell"
  mkdir -p "${legacy_backup_dir}"
  mv "${dest}" "${legacy_backup_dir}/$(basename "${dest}")"
  echo "  MIGRATE ${dest} -> ${legacy_backup_dir}/$(basename "${dest}")"
  (( count_backup++ )) || true
done

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

# dotfiles リポジトリのフックパスを設定
git -C "$DOTFILES_DIR" config core.hooksPath git/hooks-dotfiles
chmod +x "$DOTFILES_DIR/git/hooks-dotfiles/"*
echo "  HOOKS   git/hooks-dotfiles → dotfiles repo"

# dotfiles-private のフックパスを設定（存在する場合）
PRIVATE_DIR="${DOTFILES_DIR}-private"
if [[ -d "${PRIVATE_DIR}/.git" ]]; then
  git -C "$PRIVATE_DIR" config core.hooksPath "${DOTFILES_DIR}/git/hooks-private"
  echo "  HOOKS   git/hooks-private → dotfiles-private repo"
fi
