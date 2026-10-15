#!/usr/bin/env bash
set -euo pipefail

# scripts/cloud-bootstrap.sh と ai/skills/apply.sh（クラウド向け経路）の回帰テスト。
# テンポラリディレクトリの HOME・ローカル Git リポジトリだけを使い、ネットワーク・実 HOME・
# 実 dotfiles-private・実 vault へ影響しない。

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/cloud-bootstrap-test.XXXXXX")"
WORK="$(cd "${WORK}" && pwd)"
FAILURES=0

cleanup() {
  rm -rf "${WORK}"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

expect_link() {
  [[ -L "$1" ]] || fail "symlink expected: $1"
}

expect_absent() {
  [[ ! -e "$1" && ! -L "$1" ]] || fail "should not exist: $1"
}

git_quiet() {
  git -c core.hooksPath=/dev/null -c user.name=test -c user.email=test@example.invalid "$@" > /dev/null
}

HOME_DIR="${WORK}/home"
SRC="${WORK}/src"
DOTFILES="${SRC}/dotfiles"
PRIVATE="${SRC}/dotfiles-private"
BASE="${WORK}/gitbase"
mkdir -p "${HOME_DIR}" "${SRC}" "${BASE}/mattpocock" "${BASE}/y-marui"

# dotfiles 本体のコピー（作業ツリーの未コミット変更も含める）。
rsync -a --exclude '.git' --exclude 'docs/dev-charter' "${REPO_ROOT}/" "${DOTFILES}/"

# 外部 skill の取得元（ローカル）。
EXT="${BASE}/mattpocock/skills.git"
mkdir -p "${EXT}/skills/productivity/grilling"
printf -- '---\nname: grilling\ndescription: test\n---\n' > "${EXT}/skills/productivity/grilling/SKILL.md"
git -C "${EXT}" init -q
git -C "${EXT}" add -A
git_quiet -C "${EXT}" commit -m init
EXT_SHA="$(git -C "${EXT}" rev-parse HEAD)"
printf '{"skills":[{"name":"grilling","repo":"mattpocock/skills","ref":"%s","path":"skills/productivity/grilling"}]}\n' \
  "${EXT_SHA}" > "${WORK}/external.json"

# private・vault の取得元（ローカル）。blob:none の clone を許可する。
make_remote() {
  local dir="$1"
  mkdir -p "${dir}"
  git -C "${dir}" init -q
  git -C "${dir}" config uploadpack.allowFilter true
  git -C "${dir}" config uploadpack.allowAnySHA1InWant true
}
PRIVATE_REMOTE="${BASE}/y-marui/dotfiles-private.git"
make_remote "${PRIVATE_REMOTE}"
mkdir -p "${PRIVATE_REMOTE}/identity"
printf 'label: test\n' > "${PRIVATE_REMOTE}/identity/weather-location.yaml"
printf 'all|identity/weather-location.yaml|.identity/weather-location.yaml\n' > "${PRIVATE_REMOTE}/links.conf"
git -C "${PRIVATE_REMOTE}" add -A
git_quiet -C "${PRIVATE_REMOTE}" commit -m init

VAULT_REMOTE="${BASE}/y-marui/obsidian-vault.git"
make_remote "${VAULT_REMOTE}"
mkdir -p "${VAULT_REMOTE}/projects"
printf '# vault\n' > "${VAULT_REMOTE}/projects/README.md"
git -C "${VAULT_REMOTE}" add -A
git_quiet -C "${VAULT_REMOTE}" commit -m init

run_bootstrap() {
  HOME="${HOME_DIR}" \
    CODEX_HOME="${WORK}/no-codex" \
    DOTFILES_EXTERNAL_FILE="${WORK}/external.json" \
    SKILL_GIT_BASE="file://${BASE}" \
    CLOUD_GIT_BASE="file://${BASE}" \
    "$@"
}

# 既存のフックと、ハーネスが置く想定の設定を残せることの確認用。
mkdir -p "${HOME_DIR}/.claude"
printf '%s\n' '{"model":"keep","hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"echo existing"}]},{"matcher":"startup|resume","hooks":[{"type":"command","command":"bash /old/scripts/cloud-bootstrap.sh session"},{"type":"command","command":"echo sibling"}]}]}}' \
  > "${HOME_DIR}/.claude/settings.json"

# 以前の setup が展開した、いまはリストにない skill と、dotfiles 管理外の skill。
mkdir -p "${HOME_DIR}/.claude/skills/synced"
ln -s "${DOTFILES}/ai/skills/morning-brief" "${HOME_DIR}/.claude/skills/morning-brief"

# --- setup（トークンなし）を2回実行しても結果が変わらない ---
run_bootstrap bash "${DOTFILES}/scripts/cloud-bootstrap.sh" setup > /dev/null
run_bootstrap bash "${DOTFILES}/scripts/cloud-bootstrap.sh" setup > /dev/null

expect_link "${HOME_DIR}/.ai/AI_CONTEXT.md"
expect_link "${HOME_DIR}/.claude/CLAUDE.md"
expect_link "${HOME_DIR}/.claude/rules/cloud-environment.md"
for skill in grilling session-handoff session-finish; do
  [[ -f "${HOME_DIR}/.claude/skills/${skill}/SKILL.md" ]] || fail "skill missing: ${skill}"
done
expect_absent "${HOME_DIR}/.claude/skills/morning-brief"
expect_absent "${HOME_DIR}/.zshrc"
expect_absent "${HOME_DIR}/.gitconfig"
expect_absent "${HOME_DIR}/.claude/settings.json.cloud-orig"

settings="${HOME_DIR}/.claude/settings.json"
[[ "$(jq -r '.model' "${settings}")" == "keep" ]] || fail "existing settings key was lost"
[[ "$(jq '[.hooks.SessionStart[].hooks[].command] | map(select(. == "echo existing")) | length' "${settings}")" == "1" ]] \
  || fail "existing SessionStart hook was lost"
[[ "$(jq '[.hooks.SessionStart[].hooks[].command] | map(select(contains("cloud-bootstrap.sh"))) | length' "${settings}")" == "1" ]] \
  || fail "bootstrap hook must be registered exactly once"
[[ "$(jq '[.hooks.SessionStart[].hooks[].command] | map(select(. == "echo sibling")) | length' "${settings}")" == "1" ]] \
  || fail "sibling command in the same matcher was lost"
[[ "$(jq '[.hooks.SessionStart[].hooks[].command] | map(select(contains("/old/"))) | length' "${settings}")" == "0" ]] \
  || fail "stale bootstrap hook was not replaced"
expect_absent "${HOME_DIR}/.claude/skills/morning-brief"
[[ -d "${HOME_DIR}/.claude/skills/synced" ]] || fail "unmanaged skill dir was removed"

# --- session（トークンあり） ---
env_file="${WORK}/claude-env"
: > "${env_file}"
output="$(run_bootstrap env \
  DOTFILES_PRIVATE_TOKEN=dummy-private VAULT_TOKEN=dummy-vault CLAUDE_ENV_FILE="${env_file}" \
  bash "${DOTFILES}/scripts/cloud-bootstrap.sh" session)"

[[ "${output}" == *"private=ok"* && "${output}" == *"vault=ok"* ]] || fail "unexpected summary: ${output}"
[[ "${output}" != *dummy-private* && "${output}" != *dummy-vault* ]] || fail "token leaked into output"
[[ -f "${PRIVATE}/links.conf" ]] || fail "dotfiles-private was not cloned"
expect_link "${HOME_DIR}/.identity/weather-location.yaml"
vault_dir="${HOME_DIR}/src/github.com/y-marui/obsidian-vault"
[[ -d "${vault_dir}/.git" ]] || fail "vault was not cloned"
grep -q "OBSIDIAN_VAULT_ROOT" "${env_file}" || fail "OBSIDIAN_VAULT_ROOT was not exported"
grep -q ".local/bin/dotfiles" "${env_file}" || fail "PATH was not exported"
if grep -rq "dummy-" "${PRIVATE}/.git/config" "${vault_dir}/.git/config" 2> /dev/null; then
  fail "token value stored in git config"
fi

# --- 取得元が失敗したときは ok と報告しない ---
mv "${PRIVATE_REMOTE}" "${PRIVATE_REMOTE}.gone"
output="$(run_bootstrap env \
  DOTFILES_PRIVATE_TOKEN=dummy-private VAULT_TOKEN=dummy-vault \
  bash "${DOTFILES}/scripts/cloud-bootstrap.sh" session)"
[[ "${output}" == *"private=failed"* && "${output}" == *"vault=ok"* ]] \
  || fail "pull failure must be reported as failed: ${output}"
mv "${PRIVATE_REMOTE}.gone" "${PRIVATE_REMOTE}"

# --- session（トークンなし）は失敗せず、警告だけを出す ---
output="$(run_bootstrap env -u DOTFILES_PRIVATE_TOKEN -u VAULT_TOKEN \
  bash "${DOTFILES}/scripts/cloud-bootstrap.sh" session)"
[[ "${output}" == *"warnings:"* ]] || fail "missing token should be reported: ${output}"

if [[ "${FAILURES}" -gt 0 ]]; then
  printf '%d test(s) failed\n' "${FAILURES}" >&2
  exit 1
fi
printf 'OK: cloud-bootstrap tests passed\n'
