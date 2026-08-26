#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIVATE_DIR="${1:-${DOTFILES_DIR}-private}"
TEMPLATE_DIR="${DOTFILES_DIR}/templates/dotfiles-private"
CONTRACT_FILE="${DOTFILES_DIR}/templates/dotfiles-private.contract"
ERRORS=0

if [[ ! -d "${PRIVATE_DIR}" ]] || \
  ! git -C "${PRIVATE_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'dotfiles-private が隣接していないため構造検証をスキップします: %s\n' "${PRIVATE_DIR}"
  exit 0
fi

report_error() {
  printf 'エラー: %s\n' "$1" >&2
  ERRORS=$((ERRORS + 1))
}

while IFS= read -r -d '' example; do
  relative_path="${example#"${TEMPLATE_DIR}/"}"
  private_example="${PRIVATE_DIR}/${relative_path}"
  if [[ ! -f "${private_example}" ]]; then
    report_error "dotfiles-private に雛形ファイルがありません: ${relative_path}"
  elif ! cmp -s "${example}" "${private_example}"; then
    report_error "dotfiles-private の雛形が公開側と一致しません: ${relative_path}"
  fi
done < <(find "${TEMPLATE_DIR}" -type f -name '*.example' -print0)

while IFS= read -r -d '' runtime_file; do
  relative_path="${runtime_file#"${PRIVATE_DIR}/"}"
  case "${relative_path}" in
    docs/dev-charter/*) ;;
    *) report_error "private 側に実行ロジックを置けません: ${relative_path}" ;;
  esac
done < <(find "${PRIVATE_DIR}" -path "${PRIVATE_DIR}/.git" -prune -o \
  -type f \( -name '*.sh' -o -name '*.ps1' \) -print0)

if [[ -e "${PRIVATE_DIR}/Makefile" || -L "${PRIVATE_DIR}/Makefile" ]]; then
  report_error 'private 側に Makefile を置けません。実行ロジックは public 側へ置いてください。'
fi

if [[ -f "${PRIVATE_DIR}/.dotfiles-private-scaffold" ]]; then
  if [[ -e "${PRIVATE_DIR}/links.conf" || -L "${PRIVATE_DIR}/links.conf" ]]; then
    report_error 'scaffold モードでは links.conf を有効化できません。設定完了後にマーカーを削除してください。'
  fi
  if ((ERRORS > 0)); then
    exit 1
  fi
  printf 'dotfiles-private は未有効化の scaffold として有効です: %s\n' "${PRIVATE_DIR}"
  exit 0
fi

while IFS='|' read -r kind relative_path extra || \
  [[ -n "${kind}${relative_path}${extra}" ]]; do
  kind="${kind%$'\r'}"
  relative_path="${relative_path%$'\r'}"
  extra="${extra%$'\r'}"
  [[ -n "${kind}${relative_path}${extra}" ]] || continue
  [[ "${kind}" != \#* ]] || continue

  if [[ -n "${extra}" || -z "${relative_path}" ]]; then
    report_error "公開側の private 構造契約が不正です: ${CONTRACT_FILE#"${DOTFILES_DIR}/"}"
    continue
  fi
  case "${relative_path}" in
    /*|~*|*'/../'*|../*|*/..|*'/./'*|./*|*/.)
      report_error "公開側の private 構造契約に不正なパスがあります: ${relative_path}"
      continue
      ;;
  esac

  case "${kind}" in
    file)
      if [[ ! -f "${PRIVATE_DIR}/${relative_path}" ]]; then
        report_error "dotfiles-private に必須ファイルがありません: ${relative_path}"
      fi
      ;;
    glob)
      if ! compgen -G "${PRIVATE_DIR}/${relative_path}" >/dev/null; then
        report_error "dotfiles-private に一致する設定がありません: ${relative_path}"
      fi
      ;;
    *) report_error "公開側の private 構造契約に未対応 kind があります: ${kind}" ;;
  esac
done < "${CONTRACT_FILE}"

if [[ -f "${PRIVATE_DIR}/links.conf" ]] && \
  ! cmp -s "${TEMPLATE_DIR}/links.conf.example" "${PRIVATE_DIR}/links.conf"; then
  report_error 'links.conf が公開側の links.conf.example と一致しません。対応表を両方更新してください。'
fi

if ((ERRORS > 0)); then
  exit 1
fi

printf 'dotfiles-private の構造契約は有効です: %s\n' "${PRIVATE_DIR}"
