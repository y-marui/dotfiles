#!/usr/bin/env bash
# _dots-verbs.sh — dots の「ドメイン × 動詞」テーブル（単一の正本）。
#
# bin/unix/dots が source する。help・N/A 表示・オプション検証・README の動詞表との
# 整合チェック（scripts/check-dots-verb-table.sh）はすべてこのテーブルから導く。
# bin/windows/dots.ps1 の同名テーブル（ghq / winget）は、ここと同じ書式の文字列を持ち、
# 同じチェックで一致を検証する。
#
# 動詞の状態:
#   ok    実装済み
#   na    対象外（意図的に存在しない。理由を _dots_na_reason に書く）
#   todo  未実装（実装予定。README では「未実装」と表示される）
#
# bash 3.2（macOS標準）で動くよう、連想配列は使わず case 文で表現する。

DOTS_VERBS="apply diff sync merge prune cache"
DOTS_DOMAINS="brew dock shortcuts npm pipx ghq ai claude codex copilot winget"

# ドメインごとの動詞の状態。1行1ドメインの `verb=state` の並び。
_dots_domain_spec() {
  case "$1" in
    brew)      echo "apply=ok diff=ok sync=ok merge=ok prune=todo cache=ok" ;;
    dock)      echo "apply=ok diff=ok sync=ok merge=todo prune=na cache=ok" ;;
    shortcuts) echo "apply=ok diff=ok sync=ok merge=ok prune=todo cache=ok" ;;
    npm|pipx)  echo "apply=ok diff=ok sync=ok merge=ok prune=ok cache=ok" ;;
    ghq)       echo "apply=ok diff=ok sync=ok merge=ok prune=todo cache=na" ;;
    ai|claude|codex|copilot)
               echo "apply=ok diff=ok sync=na merge=na prune=ok cache=na" ;;
    winget)    echo "apply=ok diff=ok sync=na merge=na prune=todo cache=ok" ;;
    *) return 1 ;;
  esac
}

# 動詞の状態（ok / na / todo）。未知のドメイン・動詞は空文字で失敗する。
_dots_verb_state() {
  local domain="$1" verb="$2" spec entry
  spec="$(_dots_domain_spec "${domain}")" || return 1
  for entry in ${spec}; do
    if [[ "${entry%%=*}" == "${verb}" ]]; then
      printf '%s' "${entry#*=}"
      return 0
    fi
  done
  return 1
}

# 対象外（na）の理由。
_dots_na_reason() {
  case "$1:$2" in
    dock:prune)  echo "applyがDock・サイドバー全体を再構築するため、削除だけを分離できない" ;;
    ghq:cache)   echo "実状態をGit configから直接読むためキャッシュ不要" ;;
    ai:sync|ai:merge|claude:sync|claude:merge|codex:sync|codex:merge|copilot:sync|copilot:merge)
                 echo "宣言（ai/配下）は人が編集する。実状態から自動生成しない" ;;
    ai:cache|claude:cache|codex:cache|copilot:cache)
                 echo "キャッシュ不要。実状態を直接読む" ;;
    winget:sync|winget:merge)
                 echo "宣言（windows/WingetPin）は理由コメント付きで人が編集する" ;;
    *) echo "対象外" ;;
  esac
}

# 共通オプションのうち、(ドメイン, 動詞) が受け付けるもの。
# ここに載らない共通オプションはゲートがエラーにする（--full などドメイン固有のものは対象外）。
_dots_verb_options() {
  case "$1:$2" in
    npm:apply|pipx:apply) echo "--dry-run --no-prune --backup-dir" ;;
    npm:prune|pipx:prune) echo "--dry-run --backup-dir" ;;
    npm:sync|pipx:sync)   echo "--dry-run --yes" ;;
    npm:merge|pipx:merge) echo "--dry-run" ;;
    brew:apply)           echo "--no-prune --backup-dir" ;;
    dock:apply|shortcuts:apply) echo "--backup-dir" ;;
    ai:apply|claude:apply|codex:apply|copilot:apply) echo "--no-prune" ;;
    *) echo "" ;;
  esac
}

DOTS_COMMON_OPTIONS="--dry-run --yes --no-prune --backup-dir"

# `dots verbs`（README の表との整合チェック用）: domain<TAB>verb<TAB>state<TAB>理由
_dots_print_verb_matrix() {
  local domain verb state reason
  for domain in ${DOTS_DOMAINS}; do
    for verb in ${DOTS_VERBS}; do
      state="$(_dots_verb_state "${domain}" "${verb}")"
      reason=""
      [[ "${state}" != na ]] || reason="$(_dots_na_reason "${domain}" "${verb}")"
      printf '%s\t%s\t%s\t%s\n' "${domain}" "${verb}" "${state}" "${reason}"
    done
  done
}

# 実装済み（ok）の動詞を `apply|diff|...` の形で返す。
_dots_ok_verbs() {
  local domain="$1" verb ok=""
  for verb in ${DOTS_VERBS}; do
    [[ "$(_dots_verb_state "${domain}" "${verb}")" != ok ]] || ok="${ok:+${ok}|}${verb}"
  done
  printf '%s' "${ok}"
}

# ドメインの usage 行。`dots <domain> {ok な動詞}` と、na / todo の一覧。
_dots_domain_help() {
  local domain="$1" verb state
  printf '  dots %s {%s}\n' "${domain}" "$(_dots_ok_verbs "${domain}")"
  for verb in ${DOTS_VERBS}; do
    state="$(_dots_verb_state "${domain}" "${verb}")"
    case "${state}" in
      na)   printf '    %s: N/A（%s）\n' "${verb}" "$(_dots_na_reason "${domain}" "${verb}")" ;;
      todo) printf '    %s: 未実装\n' "${verb}" ;;
    esac
  done
}

# 全ドメインの usage 行（dots help 用）。Unix で使えないドメインは除く。
# N/A・未実装の動詞は末尾に短く示し、詳細は `dots <domain> help` に任せる。
_dots_all_domains_help() {
  local domain verb state na todo note
  for domain in ${DOTS_DOMAINS}; do
    [[ "${domain}" != winget ]] || continue
    na=""
    todo=""
    for verb in ${DOTS_VERBS}; do
      state="$(_dots_verb_state "${domain}" "${verb}")"
      [[ "${state}" != na ]] || na="${na:+${na} }${verb}"
      [[ "${state}" != todo ]] || todo="${todo:+${todo} }${verb}"
    done
    note=""
    [[ -z "${na}" ]] || note="N/A: ${na}"
    [[ -z "${todo}" ]] || note="${note:+${note}; }未実装: ${todo}"
    printf '  dots %-9s {%s}%s\n' "${domain}" "$(_dots_ok_verbs "${domain}")" "${note:+  # ${note}}"
  done
}

# 動詞ゲート。呼び出し側は `_dots_gate <domain> [verb] [args...]` を実行し、
# 戻り値で次を判断する。
#   0  通常どおり実行してよい
#   10 対象外（N/A を標準エラーに表示済み。呼び出し側は何もせず正常終了する）
#   11 help を表示済み（正常終了する）
# 未実装・未知の動詞・受け付けないオプションは、エラーを表示して exit 1 する。
_dots_gate() {
  local domain="$1" verb="${2:-}" state opt allowed a
  if [[ -z "${verb}" ]]; then
    printf 'error: usage: dots %s {%s}\n' "${domain}" "$(_dots_ok_verbs "${domain}")" >&2
    exit 1
  fi
  if [[ "${verb}" == help || "${verb}" == -h || "${verb}" == --help ]]; then
    printf 'Usage:\n'
    _dots_domain_help "${domain}"
    return 11
  fi

  state="$(_dots_verb_state "${domain}" "${verb}")" || {
    printf 'error: unknown %s action: %s\n' "${domain}" "${verb}" >&2
    exit 1
  }
  case "${state}" in
    na)
      printf 'N/A: dots %s %s — %s\n' "${domain}" "${verb}" "$(_dots_na_reason "${domain}" "${verb}")" >&2
      return 10
      ;;
    todo)
      printf 'error: dots %s %s は未実装です\n' "${domain}" "${verb}" >&2
      exit 1
      ;;
  esac

  allowed="$(_dots_verb_options "${domain}" "${verb}")"
  shift 2
  for a in "$@"; do
    for opt in ${DOTS_COMMON_OPTIONS}; do
      [[ "${a}" == "${opt}" ]] || continue
      case " ${allowed} " in
        *" ${opt} "*) ;;
        *)
          printf 'error: dots %s %s は %s を受け付けません\n' "${domain}" "${verb}" "${opt}" >&2
          exit 1
          ;;
      esac
    done
  done
  return 0
}
