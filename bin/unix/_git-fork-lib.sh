# shellcheck shell=bash
# bin/unix/_git-fork-lib.sh
# git-sweep・_ghq-lib.sh（ghq-pull/ghq-update/ghq-sweep）から source される、
# GitHub 標準の fork 運用（`upstream` という名前の remote）に関する共通関数。
# ghq を前提としないため、ghq 系スクリプト専用の _ghq-lib.sh とは分離している。

# _git_fork_remote_owner_repo <repo> <remote>
# <remote> の URL から owner/repo を切り出す。`gh repo view <url>` による解決は
# ~/.ssh/config の Host エイリアス（例: github-public:owner/repo.git）を解釈できない
# ため使わず、正規表現で抜き出す。
_git_fork_remote_owner_repo() {
  local repo="$1" remote="$2"
  git -C "$repo" remote get-url "$remote" 2>/dev/null \
    | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#' || true
}

# _git_fork_sync_upstream_via_git <repo>
# `gh` が使えない（未インストール・未認証。macOS では SSH セッションからログイン
# キーチェーンのトークンを読めず未認証扱いになる）ときのフォールバック。upstream
# のデフォルトブランチを git だけで fetch し、origin の同名ブランチへ
# fast-forward で push する。認証は各 remote の URL（SSH 鍵等）にそのまま従う。
# 失敗（fetch/push 不可・diverge・origin にブランチ無し）は警告のみで常に 0 を返す。
_git_fork_sync_upstream_via_git() {
  local repo="$1" ref branch up_sha origin_sha output

  ref="$(git -C "$repo" ls-remote --symref upstream HEAD 2>/dev/null \
    | sed -n 's#^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$#\1#p' | head -n 1 || true)"
  branch="${ref}"
  if [[ -z "${branch}" ]]; then
    echo "  [skip upstream-sync] (${repo}) upstream のデフォルトブランチを取得できませんでした" >&2
    return 0
  fi

  if ! output="$(git -C "$repo" fetch --no-tags upstream "refs/heads/${branch}" 2>&1)"; then
    echo "  [warn][upstream-sync] (${repo}) upstream の fetch に失敗しました: $(printf '%s' "${output}" | tr '\n' ' ' | cut -c1-300)" >&2
    return 0
  fi
  up_sha="$(git -C "$repo" rev-parse --verify -q FETCH_HEAD 2>/dev/null || true)"
  if [[ -z "${up_sha}" ]]; then
    echo "  [warn][upstream-sync] (${repo}) upstream/${branch} の取得結果を解決できませんでした" >&2
    return 0
  fi

  if ! output="$(git -C "$repo" fetch --no-tags origin "refs/heads/${branch}" 2>&1)"; then
    echo "  [skip upstream-sync] (${repo}) origin に ${branch} がありません、または fetch に失敗しました" >&2
    return 0
  fi
  origin_sha="$(git -C "$repo" rev-parse --verify -q FETCH_HEAD 2>/dev/null || true)"
  if [[ "${origin_sha}" == "${up_sha}" ]]; then
    return 0
  fi
  if ! git -C "$repo" merge-base --is-ancestor "${origin_sha}" "${up_sha}" 2>/dev/null; then
    echo "  [warn][upstream-sync] (${repo}) origin/${branch} が upstream と分岐しているため同期しません（手動で確認してください）" >&2
    return 0
  fi

  if output="$(git -C "$repo" push origin "${up_sha}:refs/heads/${branch}" 2>&1)"; then
    echo "  [upstream-sync] upstream と同期しました（git）: ${repo}"
  else
    echo "  [warn][upstream-sync] (${repo}) push に失敗しました: $(printf '%s' "${output}" | tr '\n' ' ' | cut -c1-300)" >&2
  fi
  return 0
}

# _git_fork_sync_upstream <repo>
# upstream という名前の remote があるリポジトリ（GitHub標準のfork運用）に限り、
# `gh repo sync` で upstream のデフォルトブランチを origin（自分のfork）へ
# fast-forward反映する（diverge していれば警告のみで自動マージはしない）。
# `gh` が使えない場合は _git_fork_sync_upstream_via_git に切り替える。
# ローカルへの反映は、この関数の呼び出し元が続けて行う origin の
# fetch/pull に任せる。upstream remote が無いリポジトリには何もしない。
# 失敗時も常に 0 を返す。
_git_fork_sync_upstream() {
  local repo="$1" origin_repo upstream_repo output

  upstream_repo="$(_git_fork_remote_owner_repo "$repo" upstream)"
  [[ -n "${upstream_repo}" ]] || return 0

  if ! command -v gh >/dev/null 2>&1; then
    echo "  [upstream-sync] (${repo}) 'gh' が見つからないため git で同期します" >&2
    _git_fork_sync_upstream_via_git "$repo"
    return 0
  fi
  if ! (cd "$repo" && gh auth status) >/dev/null 2>&1; then
    echo "  [upstream-sync] (${repo}) gh が未認証のため git で同期します" >&2
    _git_fork_sync_upstream_via_git "$repo"
    return 0
  fi

  origin_repo="$(_git_fork_remote_owner_repo "$repo" origin)"
  if [[ -z "${origin_repo}" ]]; then
    echo "  [skip upstream-sync] (${repo}) origin リポジトリを解決できませんでした" >&2
    return 0
  fi

  # 引数無しの `gh repo sync` はローカルの origin remote URL を gh 自身が解決する
  # ため、~/.ssh/config の Host エイリアス（例: github-public:owner/repo.git）を
  # 解釈できず失敗する。正規表現で抜き出し済みの owner/repo を明示的に渡す。
  if output="$(cd "$repo" && gh repo sync "$origin_repo" --source "$upstream_repo" 2>&1)"; then
    echo "  [upstream-sync] upstream と同期しました: ${repo}"
  else
    echo "  [warn][upstream-sync] (${repo}) 同期に失敗しました（fast-forward不可の可能性があります。手動で確認してください）: $(printf '%s' "${output}" | tr '\n' ' ' | cut -c1-500)" >&2
  fi
  return 0
}
