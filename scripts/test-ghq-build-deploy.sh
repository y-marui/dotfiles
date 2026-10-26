#!/usr/bin/env bash
# bin/unix/ghq-build-deploy の回帰テスト。偽の ghq root にMakefile付きのリポジトリを
# 用意し、グループ判定・template除外・個別上書き・複数候補ターゲットの絞り込み・
# --dry-run・失敗時の終了コードを検証する。ネットワークには触れない（ghq コマンドは必要）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD="${ROOT_DIR}/bin/unix/ghq-build-deploy"
WORK="$(mktemp -d)"
FAILURES=0
trap 'rm -rf "$WORK"' EXIT

command -v ghq >/dev/null 2>&1 || { echo "skip: ghq が見つかりません" >&2; exit 0; }

export GHQ_ROOT="$WORK/ghq"
export GHQ_BUILD_DEPLOY_TARGETS_FILE="$WORK/ghq-build-deploy-targets"
: > "$GHQ_BUILD_DEPLOY_TARGETS_FILE"

check() {
  local desc="$1"; shift
  if "$@"; then echo "  ok   - $desc"; else echo "  FAIL - $desc" >&2; FAILURES=$((FAILURES + 1)); fi
}
contains() { [[ "$1" == *"$2"* ]]; }
not_contains() { [[ "$1" != *"$2"* ]]; }

# <name> <makefile targets...> を持つリポジトリを作る
_make_repo() {
  local name="$1" dir t
  dir="$GHQ_ROOT/github.com/testowner/$name"
  shift
  mkdir -p "$dir"
  git init -q "$dir"
  {
    for t in "$@"; do
      printf '%s:\n\t@echo ran-%s-%s\n' "$t" "$name" "$t"
    done
  } > "$dir/Makefile"
}

_make_repo swift-app deploy ios
_make_repo swift-maconly deploy
_make_repo swift-special-template deploy ios   # template除外の確認（通常はswift-*に一致）
_make_repo chrome-ext build
_make_repo chrome-nomake                        # Makefile無し（候補はあるが実在しない）
_make_repo tauri-app deploy build
_make_repo unrelated-repo deploy build           # どのグループにも一致しない

echo "== group matching + template除外 + makefile絞り込み (--dry-run) =="
out="$("$CMD" --dry-run 2>&1)"
check "swift-app: deploy実行対象" contains "$out" "swift-app: make deploy"
check "swift-app: ios実行対象" contains "$out" "swift-app: make ios"
check "swift-maconly: deployのみ（iosはMakefileに無い）" contains "$out" "swift-maconly: make deploy"
check "swift-maconly: iosは対象外" not_contains "$out" "swift-maconly: make ios"
check "swift-special-template: template除外で対象外" not_contains "$out" "swift-special-template"
check "chrome-ext: build実行対象" contains "$out" "chrome-ext: make build"
check "chrome-nomake: Makefile無しで対象外" not_contains "$out" "chrome-nomake"
check "tauri-app: deployのみ（候補はdeployだけ）" contains "$out" "tauri-app: make deploy"
check "tauri-app: buildは候補外" not_contains "$out" "tauri-app: make build"
check "unrelated-repo: どのグループにも一致せず対象外" not_contains "$out" "unrelated-repo"
check "dry-runではmakeを実行しない" not_contains "$out" "ran-"

echo "== -f/--filter =="
out="$("$CMD" --dry-run -f swift-app 2>&1)"
check "filterでswift-appだけに絞り込める" contains "$out" "swift-app: make deploy"
check "filterでchrome-extは除外される" not_contains "$out" "chrome-ext"

echo "== bin/ghq-build-deploy-targets による個別上書き =="
printf 'swift-maconly deploy ios\n' > "$GHQ_BUILD_DEPLOY_TARGETS_FILE"
out="$("$CMD" --dry-run -f swift-maconly 2>&1)"
check "上書きでMakefileに無いiosは依然対象外" not_contains "$out" "swift-maconly: make ios"
printf 'swift-maconly deploy ios\n' > "$GHQ_BUILD_DEPLOY_TARGETS_FILE"
_make_repo swift-maconly deploy ios   # 上書き確認用にiosターゲットも追加
out="$("$CMD" --dry-run -f swift-maconly 2>&1)"
check "上書き後はiosも実行対象になる" contains "$out" "swift-maconly: make ios"
printf 'unrelated-repo deploy\n' > "$GHQ_BUILD_DEPLOY_TARGETS_FILE"
out="$("$CMD" --dry-run -f unrelated-repo 2>&1)"
check "上書きでグループ外のリポジトリも対象にできる" contains "$out" "unrelated-repo: make deploy"
: > "$GHQ_BUILD_DEPLOY_TARGETS_FILE"

echo "== 実際の実行（--dry-runなし） =="
out="$("$CMD" -f 'swift-app|chrome-ext' 2>&1)"
check "swift-appのdeployを実行する" contains "$out" "ran-swift-app-deploy"
check "swift-appのiosを実行する" contains "$out" "ran-swift-app-ios"
check "chrome-extのbuildを実行する" contains "$out" "ran-chrome-ext-build"

echo "== 失敗時の継続と終了コード =="
_make_repo chrome-broken build
# buildターゲットを失敗させる
dir="$GHQ_ROOT/github.com/testowner/chrome-broken"
printf 'build:\n\t@echo about-to-fail-chrome-broken; exit 1\n' > "$dir/Makefile"
out="$("$CMD" -f 'chrome-broken|chrome-ext' 2>&1)" && rc=0 || rc=$?
check "失敗しても他のリポジトリは実行する" contains "$out" "ran-chrome-ext-build"
check "失敗したターゲットは実行を試みる" contains "$out" "about-to-fail-chrome-broken"
check "失敗一覧に表示される" contains "$out" "chrome-broken: make build"
check "失敗があれば終了コード1" [ "$rc" -eq 1 ]

echo "== 対象が無い場合 =="
out="$("$CMD" -f 'does-not-exist' 2>&1)" && rc=0 || rc=$?
check "対象無しでも終了コード0" [ "$rc" -eq 0 ]
check "対象無しの案内が出る" contains "$out" "対象リポジトリ"

echo
if (( FAILURES > 0 )); then echo "FAILED: $FAILURES" >&2; exit 1; fi
echo "all passed"
