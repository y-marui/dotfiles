# shellcheck shell=bash
# bin/unix/_git-branch-lib.sh
# git-sweep・git-pull-all から source される、ブランチ方針の解決と worktree 判定の共通関数。
#
# リポジトリのブランチ方針は .gitattributes に宣言する:
#   * repo-main-branch=develop
#   * repo-protected-branches=main,develop
# 優先順位は、コマンドライン引数 [main-branch]、上記属性、ローカルGit config
# (local.repo-main-branch / local.repo-protected-branches)、origin/HEAD、main。
# 旧 git-sweep-main / git-sweep-protected 属性も互換fallbackとして読み取る。
#
# 呼び出し側は _git_branch_resolve_policy を呼んだあと、引数で main-branch を
# 受け取った場合は MAIN を上書きしてから _protect_main を呼ぶ。
# 結果は大域変数 MAIN と PROTECTED（配列）に入る。

MAIN=""
PROTECTED=()

_get_attr() {
  local attr="$1"
  git check-attr "$attr" -- . 2>/dev/null | sed -n "s/.*: ${attr}: //p"
}

_get_config() {
  git config --get "$1" 2>/dev/null || true
}

_set_protected_from_csv() {
  local raw="$1" item existing
  local -a parsed
  PROTECTED=()
  IFS=',' read -ra parsed <<< "$raw"
  for item in "${parsed[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ -n "$item" ]] || continue
    if (( ${#PROTECTED[@]} > 0 )); then
      for existing in "${PROTECTED[@]}"; do
        [[ "$existing" == "$item" ]] && continue 2
      done
    fi
    PROTECTED+=("$item")
  done
}

_protect_main() {
  local branch
  if (( ${#PROTECTED[@]} > 0 )); then
    for branch in "${PROTECTED[@]}"; do
      [[ "$branch" == "$MAIN" ]] && return 0
    done
  fi
  PROTECTED+=("$MAIN")
}

# _git_branch_resolve_policy: カレントのリポジトリから MAIN と PROTECTED を解決する。
_git_branch_resolve_policy() {
  local attr_main attr_protected config_protected

  if git rev-parse --git-dir > /dev/null 2>&1; then
    attr_main=$(_get_attr repo-main-branch)
    if [[ -z "$attr_main" || "$attr_main" == "unspecified" ]]; then
      attr_main=$(_get_attr git-sweep-main)
    fi
    if [[ -n "$attr_main" && "$attr_main" != "unspecified" ]]; then
      MAIN="$attr_main"
    else
      MAIN=$(_get_config local.repo-main-branch)
    fi
    if [[ -z "$MAIN" ]]; then
      MAIN="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
      MAIN="${MAIN#origin/}"
      if [[ -n "$MAIN" ]] && ! git show-ref --verify --quiet "refs/remotes/origin/${MAIN}"; then
        MAIN=""
      fi
    fi

    attr_protected=$(_get_attr repo-protected-branches)
    if [[ -z "$attr_protected" || "$attr_protected" == "unspecified" ]]; then
      attr_protected=$(_get_attr git-sweep-protected)
    fi
    if [[ -n "$attr_protected" && "$attr_protected" != "unspecified" ]]; then
      _set_protected_from_csv "$attr_protected"
    else
      config_protected=$(_get_config local.repo-protected-branches)
      [[ -n "$config_protected" ]] && _set_protected_from_csv "$config_protected"
    fi
  fi

  [[ -z "$MAIN" ]] && MAIN="main"
  if [[ ${#PROTECTED[@]} -eq 0 ]]; then
    PROTECTED=("$MAIN")
    if [[ "$MAIN" != main ]] && {
      git show-ref --verify --quiet refs/heads/main ||
        git show-ref --verify --quiet refs/remotes/origin/main
    }; then
      PROTECTED+=("main")
    fi
  fi
  return 0
}

_is_protected() {
  local b="$1" p
  for p in "${PROTECTED[@]}"; do
    [[ "$b" == "$p" ]] && return 0
  done
  return 1
}

# ブランチ b が checkout されている worktree のパスを返す（無ければ失敗）。
# `git worktree list --porcelain` の各レコードは空行区切り。末尾レコードも
# 確実に処理するため、入力の末尾に空行を1つ追加してから読む。
_worktree_path_for_branch() {
  local b="$1" path="" branch=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *) path="${line#worktree }" ;;
      branch\ *) branch="${line#branch refs/heads/}" ;;
      "")
        if [[ -n "$path" && "$branch" == "$b" ]]; then
          printf '%s\n' "$path"
          return 0
        fi
        path=""; branch=""
        ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null; printf '\n')
  return 1
}

# ブランチ b が「現在の worktree 以外」で checkout されているかを判定する。
_branch_in_other_worktree() {
  local b="$1" wt cur
  wt=$(_worktree_path_for_branch "$b") || return 1
  cur=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  [[ "$wt" != "$cur" ]]
}
