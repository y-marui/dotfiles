#!/usr/bin/env bash
# apply_pipxfile.sh
# pipxfile の内容をローカルの pipx 環境に適用する
#
# 動作:
#   1. pipxfile にあって未インストールのものをインストール
#      インストール元が `ghq:<ghq root からの相対パス>` の行は、host/role が work の端末では
#      ghq で取得した checkout から `pipx install --editable` で入れる（未取得なら ghq get し、
#      git+https で導入済みのものは editable で入れ直す）。work でない端末や ghq がない端末
#      では `git+https://<相対パス>` から通常どおり入れる
#   2. 続けて prune_pipxfile.sh で pipxfile にないものを削除（--no-prune で省略）
#      --no-prune の場合は未管理パッケージを一覧表示するだけで削除しない
#   3. pipxfile.cache を更新
#   --dry-run は何も変更せず、実行した場合の変更予定だけを表示する。
#
# 使い方:
#   DOTFILES_DIR=~/dotfiles bash pipx/apply_pipxfile.sh [--no-prune] [--dry-run] [--backup-dir DIR]

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PIPXFILE="$DOTFILES_DIR/pipx/pipxfile"
NO_PRUNE=0
DRY_RUN=0
BACKUP_ARGS=()

while (( $# > 0 )); do
  case "$1" in
    --no-prune) NO_PRUNE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --backup-dir)
      (( $# >= 2 )) || { echo "error: --backup-dir requires a directory" >&2; exit 2; }
      BACKUP_ARGS=(--backup-dir "$2")
      shift 2
      ;;
    *) echo "usage: apply_pipxfile.sh [--no-prune] [--dry-run] [--backup-dir DIR]" >&2; exit 2 ;;
  esac
done

# shellcheck source=../scripts/host-role.sh
source "$DOTFILES_DIR/scripts/host-role.sh"

load_names() {
  awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$1" | sort
}

package_spec_for() {
  local name="$1"

  awk -v name="$name" '
    $1 == name {
      $1 = ""
      sub(/^[[:space:]]+/, "")
      print length($0) ? $0 : name
      exit
    }
  ' "$PIPXFILE"
}

# インストール元の解決。出力: "<editable|plain>\t<pipx install に渡す指定>"
# `ghq:` 指定は work かつ ghq ありの端末では checkout のパス（editable）、それ以外は git+https。
resolve_install() {
  local spec="$1" rel path
  if [[ "$spec" != ghq:* ]]; then
    printf 'plain\t%s\n' "$spec"
    return 0
  fi
  rel="${spec#ghq:}"
  if dots_host_is_work && command -v ghq >/dev/null 2>&1; then
    path="$(ghq list -p -e "$rel" 2>/dev/null | head -n 1 || true)"
    if [[ -z "$path" ]]; then
      if [[ "$DRY_RUN" -eq 1 ]]; then
        printf 'editable\t%s\n' "<ghq get $rel>"
        return 0
      fi
      ghq get "$rel" >&2 || return 1
      path="$(ghq list -p -e "$rel" | head -n 1)"
    fi
    printf 'editable\t%s\n' "$path"
  else
    printf 'plain\tgit+https://%s\n' "$rel"
  fi
}

# 導入済みの仮想環境が editable かどうか
is_editable() {
  pipx list --json 2>/dev/null | python3 -c '
import json, sys
name = sys.argv[1]
venv = json.load(sys.stdin).get("venvs", {}).get(name)
args = (venv or {}).get("metadata", {}).get("main_package", {}).get("pip_args") or []
sys.exit(0 if any(a in ("-e", "--editable") for a in args) else 1)' "$1"
}

install_one() {
  local pkg="$1" force="$2" package_spec resolved mode target
  package_spec="$(package_spec_for "$pkg")"
  resolved="$(resolve_install "$package_spec")" || { echo "  [failed] $pkg: ghq get に失敗しました" >&2; return 1; }
  mode="${resolved%%$'\t'*}"
  target="${resolved#*$'\t'}"
  local args=()
  [[ "$force" -eq 0 ]] || args+=(--force)
  [[ "$mode" != editable ]] || args+=(--editable)
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] install  $pkg${mode:+ ($mode)}"
  else
    echo "  install  $pkg ($mode)"
    pipx install ${args[@]+"${args[@]}"} "$target"
  fi
}

installed=$(bash "$DOTFILES_DIR/pipx/update_pipxcache.sh" --print | sort)
to_install=$(comm -13 <(printf '%s\n' "$installed" | grep -v '^\s*$' || true) <(load_names "$PIPXFILE"))
to_remove=$(comm -23 <(printf '%s\n' "$installed" | grep -v '^\s*$' || true) <(load_names "$PIPXFILE"))

# ── インストール ───────────────────────────────────────────────────────────────
echo "==> Installing packages from pipxfile..."
if [[ -z "$to_install" ]]; then
  echo "  (already up to date)"
else
  while IFS= read -r pkg; do
    install_one "$pkg" 0
  done <<< "$to_install"
fi

# ── ghq: 指定の editable 化 ───────────────────────────────────────────────────
# work の端末で、git+https などから導入済みの ghq: 指定のパッケージを editable で入れ直す。
if dots_host_is_work && command -v ghq >/dev/null 2>&1; then
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    [[ "$(package_spec_for "$pkg")" == ghq:* ]] || continue
    grep -qxF -- "$pkg" <<< "$installed" || continue
    is_editable "$pkg" && continue
    echo "==> Reinstalling $pkg as editable from ghq checkout..."
    install_one "$pkg" 1
  done < <(load_names "$PIPXFILE")
fi

# ── 不要パッケージの削除 ───────────────────────────────────────────────────────
echo ""
if [[ "$NO_PRUNE" -eq 0 ]]; then
  prune_args=()
  [[ "$DRY_RUN" -eq 0 ]] || prune_args+=(--dry-run)
  bash "$DOTFILES_DIR/pipx/prune_pipxfile.sh" ${prune_args[@]+"${prune_args[@]}"} ${BACKUP_ARGS[@]+"${BACKUP_ARGS[@]}"}
else
  echo "==> Checking for packages not in pipxfile (--no-prune: 削除しません)..."
  if [[ -z "$to_remove" ]]; then
    echo "  (no unmanaged packages)"
  else
    echo "  以下のパッケージは pipxfile 未管理です（dots pipx prune で削除）:"
    while IFS= read -r pkg; do echo "    $pkg"; done <<< "$to_remove"
  fi
fi

# ── キャッシュ更新 ─────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" -eq 0 ]]; then
  echo ""
  bash "$DOTFILES_DIR/pipx/update_pipxcache.sh"
fi
