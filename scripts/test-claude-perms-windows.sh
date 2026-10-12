#!/usr/bin/env bash
# bin/windows/claude-perms.ps1 の回帰テスト。bin/unix/claude-perms（bash + jq）を正本として、
# 同じ入力（使い捨ての HOME 配下の設定ファイル）に対する出力・終了コード・書き戻した
# ファイルが一致することを確認する。リポジトリ外・実際の ~/.claude には一切影響しない。
# pwsh または jq が無い環境では何もせず成功扱いで終了する。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIX_CMD="${ROOT}/bin/unix/claude-perms"
PS_CMD="${ROOT}/bin/windows/claude-perms.ps1"

if ! command -v pwsh > /dev/null 2>&1 || ! command -v jq > /dev/null 2>&1; then
  echo "skip: pwsh と jq が必要です"
  exit 0
fi

WORK="$(mktemp -d)"
FAILURES=0
trap 'rm -rf "${WORK}"' EXIT

# pwsh へ渡すパス（Git Bash 等の /c/... を C:\... に変換する。変換不要な環境ではそのまま）
native_path() {
  if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

# Windows の jq は CRLF で出力し、bin/unix/claude-perms（bash）が壊れるため、正本の実行時だけ CR を除去する
# シムを PATH の先頭に置く（macOS / Linux の jq には影響しない）。
make_jq_shim() {
  local dir="$1" real
  real="$(command -v jq)"
  mkdir -p "${dir}"
  cat > "${dir}/jq" << SHIM
#!/usr/bin/env bash
"${real}" "\$@" | tr -d '\r'
exit "\${PIPESTATUS[0]}"
SHIM
  chmod +x "${dir}/jq"
}

make_fixture() {
  local home="$1"
  mkdir -p "${home}/.claude" "${home}/proj/a/.claude" "${home}/proj/b/.claude" \
    "${home}/proj/c/.claude" "${home}/proj/e/.claude" "${home}/proj/f/.claude" "${home}/other/d"
  cat > "${home}/.claude/settings.json" << 'JSON'
{
  "model": "x",
  "permissions": {
    "allow": ["Bash(gh:*)", "Bash(git *)", "WebFetch(domain:example.com)", "Bash(run-quiet:*)", "Bash(make:*)", "Bash(git commit:*)"],
    "deny": ["Bash(rm:*)", "Bash(curl *)"]
  }
}
JSON
  cat > "${home}/.claude/claude-perms.json" << 'JSON'
{
  "forbiddenAllow": ["Bash(run-quiet *)"],
  "pathRules": [
    {"pathGlob": ["~/proj/*", "~/other/z"], "allow": ["Bash(dotnet:*)", "Bash(dotnet build:*)", "mcp__github__issue_read"]},
    {"pathGlob": "~/aaa", "allow": ["Bash(zz:*)"]}
  ]
}
JSON
  cat > "${home}/proj/a/.claude/settings.local.json" << 'JSON'
{
  "permissions": {
    "allow": ["Bash(git commit:*)", "Bash(gh api *)", "Bash(npm run *)", "Bash(npm run *)", "Bash(docker ps)", "Bash(ghost:*)", "Bash(run-quiet:*)", "Bash(dotnet build:*)", "mcp__x", "Bash(make test:*)"],
    "deny": ["WebFetch", "Bash(curl *)"],
    "ask": ["Bash(zeta:*)", "Bash(alpha *)"]
  },
  "env": {"A": "1"}
}
JSON
  printf '{"permissions": {"allow": []}}\n' > "${home}/proj/b/.claude/settings.local.json"
  printf '{ bad\n' > "${home}/proj/c/.claude/settings.local.json"
  printf '{"permissions": {"allow": ["Bash(gh:*)"]}}\n' > "${home}/proj/e/.claude/settings.local.json"
  printf '{"permissions": {"allow": ["Bash(npm test:*)", "Bash(npm run build)"]}}\n' > "${home}/proj/f/.claude/settings.local.json"
}

# run_scenarios <unix|ps> <home>: 同じ操作列を実行し、出力・終了コード・対象ファイルを標準出力へ出す
run_scenarios() {
  local impl="$1" home="$2" nhome
  nhome="$(native_path "${home}")"

  run() {
    local rc=0
    echo "\$ $*"
    if [[ "${impl}" == unix ]]; then
      (cd "${home}" && MSYS2_ARG_CONV_EXCL='"~/;["~/' PATH="${WORK}/shim:${PATH}" HOME="${home}" bash "${UNIX_CMD}" "$@" 2>&1) || rc=$?
    else
      (cd "${home}" && CLAUDE_PERMS_HOME="${nhome}" pwsh -NoLogo -NoProfile -File "$(native_path "${PS_CMD}")" "$@" 2>&1) || rc=$?
    fi
    echo "[exit ${rc}]"
  }
  dump() {
    local f
    for f in "$@"; do
      echo "--- ${f}"
      if [[ -f "${home}/${f}" ]]; then cat "${home}/${f}"; else echo "(なし)"; fi
    done
  }

  run check proj/a proj/b proj/c proj/e other/d proj/nothing
  run candidates proj/a proj/f proj/e
  run candidates --json proj/a proj/f proj/e
  run candidates --verbose proj/b other/d
  run format proj/a proj/b proj/c proj/e other/d
  dump proj/a/.claude/settings.local.json proj/b/.claude/settings.local.json proj/e/.claude/settings.local.json
  run format proj/a
  run check proj/a
  run merge proj/f other/d
  dump proj/f/.claude/settings.local.json
  run apply proj/a
  dump proj/a/.claude/settings.local.json
  run remove 'Bash(dotnet:*)' proj/a proj/f
  run remove 'Bash(dotnet *)' proj/a proj/f --apply
  run remove 'Bash(*)' proj/f --glob
  run remove 'mcp__*' proj/a proj/f --glob -y
  dump proj/a/.claude/settings.local.json proj/f/.claude/settings.local.json
  printf '[{"target":"proj/f","allow":["Bash(dotnet:*)"]},{"target":"proj/a","allow":["Bash(dotnet build:*)"]}]\n' > "${home}/rm.json"
  run remove --json rm.json
  run remove --json rm.json --apply
  dump proj/a/.claude/settings.local.json proj/f/.claude/settings.local.json
  run format-global
  dump .claude/settings.json .claude/claude-perms.json
  run remove-global 'Bash(make:*)'
  run remove-global 'Bash(git *)' --apply
  dump .claude/settings.json
  run bogus
  run remove
  run format-global extra
}

normalize() {
  # 一時ディレクトリの絶対パス（/c/... と C:\... の両表記）を <HOME> に、\ を / に揃える。
  # JSON 構文エラーの詳細行（jq と .NET でパーサの文言が異なる）は比較対象から外す
  local home="$1" nhome
  nhome="$(native_path "${home}")"
  nhome="${nhome//\\//}"
  sed -e 's#\\#/#g' -e 's#\r$##' \
    | sed -e "s#${nhome}#<HOME>#g" -e "s#${home}#<HOME>#g" \
    | awk 'skip { skip = 0; print "  (JSON parse detail)"; next } /^error: 無効なJSON:/ { skip = 1 } { print }'
}

make_jq_shim "${WORK}/shim"
U_HOME="${WORK}/u"
W_HOME="${WORK}/w"
mkdir -p "${U_HOME}" "${W_HOME}"
make_fixture "${U_HOME}"
make_fixture "${W_HOME}"

run_scenarios unix "${U_HOME}" 2>&1 | normalize "${U_HOME}" > "${WORK}/unix.out"
run_scenarios ps "${W_HOME}" 2>&1 | normalize "${W_HOME}" > "${WORK}/ps.out"

if diff -au "${WORK}/unix.out" "${WORK}/ps.out" > "${WORK}/diff.out"; then
  echo "  ok   - bin/windows/claude-perms.ps1 は bin/unix/claude-perms と同じ出力・同じファイル結果"
else
  echo "  FAIL - unix 版と PowerShell 版で出力またはファイル結果が異なる" >&2
  head -200 "${WORK}/diff.out" >&2
  FAILURES=$((FAILURES + 1))
fi

echo
if (( FAILURES > 0 )); then
  echo "${FAILURES} 件失敗" >&2
  exit 1
fi
echo "すべて成功"
