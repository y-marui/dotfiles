#!/usr/bin/env bash
# dots の動詞契約（bin/unix/_dots-verbs.sh のテーブル、N/A・未実装・オプションゲート、
# npm / pipx の apply・prune・sync・merge の --dry-run・--no-prune・--yes、
# brew の sync・merge・prune、dock の sync・merge、shortcuts の適用計画、diff --exit-code）の回帰テスト。
#
# dots 本体と各ドメインのスクリプトを一時ディレクトリへコピーし、npm・pipx・brew・dockutil・
# mysides コマンドはスタブに差し替えて検証する。実環境のパッケージ・宣言ファイル・
# ~/.dotfiles-backup には一切影響しない。ネットワークアクセスも行わない。
set -euo pipefail

# 実環境の DOTFILES_DIR を引き継ぐと、コピーではなく実リポジトリのキャッシュを書き換えてしまう
unset DOTFILES_DIR

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
FAILURES=0

trap 'rm -rf "$WORK"' EXIT

ROOT="$WORK/dotfiles"
STUBS="$WORK/stubs"
STATE="$WORK/state"
export HOME="$WORK/home"
export STATE
PRIVATE="$ROOT-private"
mkdir -p "$ROOT/bin/unix" "$ROOT/npm" "$ROOT/pipx" "$ROOT/macos" "$PRIVATE/macos" "$STUBS" "$STATE" "$HOME"
cp "$REPO/bin/unix/dots" "$REPO/bin/unix/_dots-verbs.sh" "$ROOT/bin/unix/"
cp "$REPO"/npm/*.sh "$ROOT/npm/"
cp "$REPO"/pipx/*.sh "$ROOT/pipx/"
cp "$REPO"/macos/*.sh "$REPO"/macos/*.py "$ROOT/macos/"
export PATH="$STUBS:$PATH"
DOTS="$ROOT/bin/unix/dots"

# ── スタブ: 状態は $STATE/<tool> の1行1パッケージ ────────────────────────────
cat > "$STUBS/npm" <<'STUB'
#!/usr/bin/env bash
f="$STATE/npm"; touch "$f"
case "$1" in
  list)
    printf '{"dependencies":{"npm":{}'
    while IFS= read -r p; do [[ -n "$p" ]] && printf ',"%s":{}' "$p"; done < "$f"
    printf '}}\n' ;;
  install) printf '%s\n' "$3" >> "$f" ;;
  uninstall) grep -vxF "$3" "$f" > "$f.tmp" || true; mv "$f.tmp" "$f" ;;
esac
STUB
cat > "$STUBS/pipx" <<'STUB'
#!/usr/bin/env bash
f="$STATE/pipx"; touch "$f"
case "$1" in
  list)
    printf '{"venvs":{'
    first=1
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      [[ $first -eq 1 ]] || printf ','
      first=0
      printf '"%s":{}' "$p"
    done < "$f"
    printf '}}\n' ;;
  install) printf '%s\n' "$2" >> "$f" ;;
  uninstall) grep -vxF "$2" "$f" > "$f.tmp" || true; mv "$f.tmp" "$f" ;;
esac
STUB
# brew: `bundle dump` は $STATE/brew_dump を書き出し、`bundle cleanup` / `install` は呼び出しを記録する
cat > "$STUBS/brew" <<'STUB'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "bundle dump")
    for a in "$@"; do case "$a" in --file=*) f="${a#--file=}" ;; esac; done
    cp "$STATE/brew_dump" "$f" ;;
  "bundle cleanup") echo "cleanup $*" >> "$STATE/brew_calls" ;;
  "bundle install") echo "install $*" >> "$STATE/brew_calls" ;;
  "list --pinned") : ;;
esac
STUB
# dockutil / mysides: 現在の Dock・サイドバーを $STATE から返す
cat > "$STUBS/dockutil" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == "--list" ]] || exit 0
while IFS= read -r p; do
  [[ -n "$p" ]] && printf '%s\tfile://%s/\tpersistentApps\t/x\n' "$(basename "$p")" "$p"
done < "$STATE/dock"
STUB
cat > "$STUBS/mysides" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == "list" ]] || exit 0
cat "$STATE/sidebar"
STUB
chmod +x "$STUBS/npm" "$STUBS/pipx" "$STUBS/brew" "$STUBS/dockutil" "$STUBS/mysides"

check() {
  local desc="$1"
  shift
  if "$@"; then
    echo "  ok   - $desc"
  else
    echo "  FAIL - $desc" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

contains() { [[ "$1" == *"$2"* ]]; }
not_contains() { [[ "$1" != *"$2"* ]]; }
eq() { [[ "$1" == "$2" ]]; }
section() { echo; echo "== $1 =="; }

# dots を実行して標準出力・標準エラー・終了コードを OUT / ERR / RC に入れる
run_dots() {
  local o="$WORK/out" e="$WORK/err"
  RC=0
  bash "$DOTS" "$@" >"$o" 2>"$e" || RC=$?
  OUT="$(cat "$o")"
  ERR="$(cat "$e")"
}

# ── テーブル ──────────────────────────────────────────────────────────────────
section "動詞テーブル（dots verbs / help）"
run_dots verbs
check "dots verbs が成功する" eq "$RC" 0
check "66行（11ドメイン×6動詞）" eq "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" 66
check "未知の状態を含まない" eq "$(printf '%s\n' "$OUT" | awk -F'\t' '$3!="ok" && $3!="na" && $3!="todo"' | wc -l | tr -d ' ')" 0
check "npm は全動詞が ok" eq "$(printf '%s\n' "$OUT" | awk -F'\t' '$1=="npm" && $3=="ok"' | wc -l | tr -d ' ')" 6
check "na の行には理由がある" eq "$(printf '%s\n' "$OUT" | awk -F'\t' '$3=="na" && $4==""' | wc -l | tr -d ' ')" 0
run_dots npm help
check "dots npm help が成功する" eq "$RC" 0
check "dots npm help に prune が載る" contains "$OUT" "prune"
run_dots dock help
check "dots dock help に N/A と未実装が載る" contains "$OUT" "N/A"
run_dots help
check "dots help が成功し verbs を案内する" contains "$OUT" "dots verbs"

# ── N/A・未実装・ゲート ───────────────────────────────────────────────────────
section "N/A・未実装・オプションゲート"
run_dots claude sync
check "N/A は終了コード0" eq "$RC" 0
check "N/A は標準エラーに理由を出す" contains "$ERR" "N/A: dots claude sync"
check "N/A は標準出力に何も出さない" eq "$OUT" ""
run_dots ghq cache
check "ghq cache は N/A" contains "$ERR" "N/A: dots ghq cache"
# 実テーブルには todo（未実装）が残っていないため、テーブルを差し替えてゲートの分岐を検証する
ERR="$(bash -c 'source "$1"; _dots_domain_spec() { echo "apply=todo diff=ok sync=ok merge=ok prune=ok cache=ok"; }; _dots_gate demo apply' _ "$ROOT/bin/unix/_dots-verbs.sh" 2>&1 >/dev/null)" && RC=0 || RC=$?
check "未実装はエラー" eq "$RC" 1
check "未実装のメッセージ" contains "$ERR" "未実装"
run_dots npm bogus
check "未知の動詞はエラー" eq "$RC" 1
check "未知の動詞のメッセージ" contains "$ERR" "unknown npm action: bogus"
run_dots npm
check "動詞なしは usage エラー" eq "$RC" 1
run_dots dock apply --yes
check "受け付けないオプションはエラー" eq "$RC" 1
check "受け付けないオプションのメッセージ" contains "$ERR" "--yes を受け付けません"
run_dots dock prune
check "dock prune は N/A" contains "$ERR" "N/A: dots dock prune"
run_dots brew apply --exit-code
check "apply は --exit-code を受け付けない" eq "$RC" 1
run_dots claude diff --summary
check "ai の diff は --summary を受け付けない" eq "$RC" 1
run_dots ghq apply --yes
check "ghq apply は --yes を受け付けない" eq "$RC" 1
run_dots ghq sync --no-prune
check "ghq sync は --no-prune を受け付けない" eq "$RC" 1
run_dots ghq diff --dry-run
check "diff は --dry-run を受け付けない" eq "$RC" 1
run_dots ghq help
check "ghq help に prune が載る" contains "$OUT" "prune"
run_dots npm merge --yes
check "merge は --yes を受け付けない" eq "$RC" 1
run_dots npm prune --no-prune
check "prune は --no-prune を受け付けない" eq "$RC" 1

# ── npm / pipx の契約（同じテストを両方に流す） ───────────────────────────────
declared_file() { printf '%s/%s/%sfile' "$ROOT" "$1" "$1"; }
state_of() { sort "$STATE/$1" | tr '\n' ' ' | sed 's/ $//'; }
set_state() { local t="$1"; shift; : > "$STATE/$t"; local p; for p in "$@"; do echo "$p" >> "$STATE/$t"; done; }
set_declared() { local t="$1"; shift; { echo "# ${t}file"; local p; for p in "$@"; do echo "$p"; done; } > "$(declared_file "$t")"; }
backup_count() { find "$HOME/.dotfiles-backup" -name "$1-removed.txt" 2>/dev/null | wc -l | tr -d ' '; }
reset_backups() { rm -rf "$HOME/.dotfiles-backup"; }

for tool in npm pipx; do
  section "$tool: apply / prune"
  reset_backups
  set_declared "$tool" a b
  set_state "$tool" a x

  run_dots "$tool" apply --dry-run
  check "apply --dry-run は成功する" eq "$RC" 0
  check "apply --dry-run は追加予定を表示する" contains "$OUT" "[dry-run] install  b"
  check "apply --dry-run は削除予定を表示する" contains "$OUT" "[dry-run] uninstall  x"
  check "apply --dry-run は状態を変えない" eq "$(state_of "$tool")" "a x"
  check "apply --dry-run はバックアップを作らない" eq "$(backup_count "$tool")" 0
  check "apply --dry-run はキャッシュを書かない" test ! -e "$ROOT/$tool/${tool}file.cache"

  run_dots "$tool" apply --no-prune
  check "apply --no-prune は成功する" eq "$RC" 0
  check "apply --no-prune は追加する" eq "$(state_of "$tool")" "a b x"
  check "apply --no-prune は未管理を一覧表示する" contains "$OUT" "    x"
  check "apply --no-prune はバックアップを作らない" eq "$(backup_count "$tool")" 0

  run_dots "$tool" apply
  check "apply は成功する" eq "$RC" 0
  check "apply は未管理を削除して宣言と一致させる" eq "$(state_of "$tool")" "a b"
  check "apply は削除前に一覧をバックアップする" eq "$(backup_count "$tool")" 1
  check "バックアップに削除対象が入る" contains "$(cat "$HOME"/.dotfiles-backup/*/"$tool"-removed.txt)" "x"

  run_dots "$tool" apply
  check "差分がなければ何もしない" contains "$OUT" "(no unmanaged packages)"
  check "差分なしでバックアップを増やさない" eq "$(backup_count "$tool")" 1

  set_state "$tool" a b y
  reset_backups
  run_dots "$tool" prune --dry-run
  check "prune --dry-run は削除予定だけ表示する" contains "$OUT" "[dry-run] uninstall  y"
  check "prune --dry-run は状態を変えない" eq "$(state_of "$tool")" "a b y"
  run_dots "$tool" prune --backup-dir "$WORK/bk"
  check "prune は削除する" eq "$(state_of "$tool")" "a b"
  check "prune は --backup-dir に退避する" test -f "$WORK/bk/$tool-removed.txt"

  section "$tool: sync / merge"
  set_declared "$tool" a zz
  set_state "$tool" a c
  before="$(cat "$(declared_file "$tool")")"

  run_dots "$tool" sync --dry-run
  check "sync --dry-run は成功する" eq "$RC" 0
  check "sync --dry-run は追加・削除予定を表示する" contains "$OUT" "[remove] zz"
  check "sync --dry-run は宣言を変えない" eq "$(cat "$(declared_file "$tool")")" "$before"

  run_dots "$tool" sync
  check "削除を伴う sync は --yes なしで失敗する" eq "$RC" 2
  check "--yes が必要なことを示す" contains "$ERR" "--yes"
  check "失敗時は宣言を変えない" eq "$(cat "$(declared_file "$tool")")" "$before"

  run_dots "$tool" merge
  check "merge は --yes なしで成功する" eq "$RC" 0
  check "merge は追加だけ行い削除しない" contains "$(cat "$(declared_file "$tool")")" "zz"
  check "merge は実状態のパッケージを追加する" contains "$(cat "$(declared_file "$tool")")" "c"

  set_declared "$tool" a zz
  run_dots "$tool" sync --yes
  check "sync --yes は成功する" eq "$RC" 0
  check "sync --yes は宣言から削除する" not_contains "$(cat "$(declared_file "$tool")")" "zz"
  check "sync --yes は実状態を追加する" contains "$(cat "$(declared_file "$tool")")" "c"
  check "コメントを保持する" contains "$(cat "$(declared_file "$tool")")" "# ${tool}file"

  set_declared "$tool" a c
  set_state "$tool" a c
  run_dots "$tool" sync
  check "削除がなければ --yes なしで成功する" eq "$RC" 0

  section "$tool: diff / cache"
  run_dots "$tool" cache
  check "cache は成功しキャッシュを書く" test -e "$ROOT/$tool/${tool}file.cache"
  run_dots "$tool" cache extra
  check "cache は引数を取らない" eq "$RC" 1
  run_dots "$tool" diff
  check "diff は差分なしで成功する" contains "$OUT" "No diff"
  set_state "$tool" a c q
  DOTFILES_DIR="$ROOT" bash "$ROOT/$tool/update_${tool}cache.sh" >/dev/null
  run_dots "$tool" diff
  check "diff は差分があっても終了コード0" eq "$RC" 0
  check "diff は差分を表示する" contains "$OUT" "[+cache]"
  run_dots "$tool" diff --summary
  check "diff --summary は1行で示す" contains "$OUT" "cache のみ"
  run_dots "$tool" diff --exit-code
  check "diff --exit-code は差分があれば終了コード1" eq "$RC" 1
  check "diff --exit-code でも差分を表示する" contains "$OUT" "[+cache]"
  set_state "$tool" a c
  DOTFILES_DIR="$ROOT" bash "$ROOT/$tool/update_${tool}cache.sh" >/dev/null
  run_dots "$tool" diff --exit-code
  check "diff --exit-code は差分がなければ終了コード0" eq "$RC" 0
done

# ── brew ──────────────────────────────────────────────────────────────────────
section "brew: sync / merge / prune"
BREWFILE="$ROOT/macos/Brewfile"
reset_brew() {
  cat > "$BREWFILE" <<'BF'
# Brewfile
# ── 基本 ──────────────────────────────────────────────────────────────────────
brew "kept"
brew "gone"
BF
  rm -f "$ROOT/macos/Brewfile.local" "$STATE/brew_calls"
  printf 'brew "kept"\nbrew "fresh"\n' > "$STATE/brew_dump"
}
reset_brew
before="$(cat "$BREWFILE")"

run_dots brew sync --dry-run
check "brew sync --dry-run は成功する" eq "$RC" 0
check "brew sync --dry-run は削除予定を表示する" contains "$OUT" '[remove]    brew "gone"'
check "brew sync --dry-run は追加予定を表示する" contains "$OUT" '[add]       brew "fresh"'
check "brew sync --dry-run は Brewfile を変えない" eq "$(cat "$BREWFILE")" "$before"
check "brew sync --dry-run はキャッシュを書かない" test ! -e "$ROOT/macos/Brewfile.cache"

run_dots brew sync
check "削除を伴う brew sync は --yes なしで失敗する" eq "$RC" 2
check "brew sync の失敗メッセージが --yes を示す" contains "$ERR" "--yes"
check "失敗時は Brewfile を変えない" eq "$(cat "$BREWFILE")" "$before"

run_dots brew merge
check "brew merge は --yes なしで成功する" eq "$RC" 0
check "brew merge は削除しない" contains "$(cat "$BREWFILE")" 'brew "gone"'
check "brew merge は追加する" contains "$(cat "$BREWFILE")" 'brew "fresh"'

reset_brew
run_dots brew sync --yes
check "brew sync --yes は成功する" eq "$RC" 0
check "brew sync --yes は削除する" not_contains "$(cat "$BREWFILE")" 'brew "gone"'
check "brew sync --yes は追加する" contains "$(cat "$BREWFILE")" 'brew "fresh"'

run_dots brew prune --dry-run
check "brew prune --dry-run は成功する" eq "$RC" 0
check "brew prune --dry-run は --force なしで cleanup する" contains "$(cat "$STATE/brew_calls")" "cleanup bundle cleanup --file="
check "brew prune --dry-run は削除しない" not_contains "$(cat "$STATE/brew_calls")" "--force"
: > "$STATE/brew_calls"
run_dots brew prune
check "brew prune は成功する" eq "$RC" 0
check "brew prune は --force で cleanup する" contains "$(cat "$STATE/brew_calls")" "--force"
check "brew prune はインストールしない" not_contains "$(cat "$STATE/brew_calls")" "install"

: > "$STATE/brew_calls"
run_dots brew apply --no-prune --dry-run
check "brew apply --no-prune --dry-run は cleanup しない" not_contains "$(cat "$STATE/brew_calls")" "cleanup"

# ── dock ──────────────────────────────────────────────────────────────────────
section "dock: sync / merge"
DOCKFILE="$PRIVATE/macos/dockfile"
reset_dock() {
  printf 'dock\t/Applications/Foo.app\ndock\t/nonexistent/Other.app\n' > "$DOCKFILE"
  printf '/Applications/Foo.app\n/Applications/Bar.app\n' > "$STATE/dock"
  printf 'Home -> file:///sidebar-fixture/home/\n' > "$STATE/sidebar"
}
reset_dock
before="$(cat "$DOCKFILE")"

run_dots dock sync --dry-run
check "dock sync --dry-run は成功する" eq "$RC" 0
check "dock sync --dry-run は他マシン由来の項目の削除予定を表示する" contains "$OUT" "[remove] dock"$'\t'"/nonexistent/Other.app"
check "dock sync --dry-run は追加予定を表示する" contains "$OUT" "[add]    dock"$'\t'"/Applications/Bar.app"
check "dock sync --dry-run は dockfile を変えない" eq "$(cat "$DOCKFILE")" "$before"

run_dots dock sync
check "削除を伴う dock sync は --yes なしで失敗する" eq "$RC" 2
check "dock merge の案内を出す" contains "$ERR" "dots dock merge"
check "失敗時は dockfile を変えない" eq "$(cat "$DOCKFILE")" "$before"

run_dots dock merge
check "dock merge は --yes なしで成功する" eq "$RC" 0
check "dock merge は他マシン由来の項目を保持する" contains "$(cat "$DOCKFILE")" "/nonexistent/Other.app"
check "dock merge は実機の項目を追加する" contains "$(cat "$DOCKFILE")" "/Applications/Bar.app"

reset_dock
run_dots dock sync --yes
check "dock sync --yes は成功する" eq "$RC" 0
check "dock sync --yes は他マシン由来の項目を削除する" not_contains "$(cat "$DOCKFILE")" "/nonexistent/Other.app"
check "dock sync --yes は実機の項目を追加する" contains "$(cat "$DOCKFILE")" "/Applications/Bar.app"
run_dots dock sync
check "削除がなければ dock sync は --yes なしで成功する" eq "$RC" 0

# ── shortcuts（適用計画は純粋関数なので直接検証する） ─────────────────────────
section "shortcuts: 適用計画（plan_apply / plan_sync）"
if python3 - "$REPO/macos" <<'PYTEST'
import sys

sys.path.insert(0, sys.argv[1])
import keyboard_shortcuts as ks

managed = {"A": {"x": "1", "y": "2"}}
current = {"A": {"y": "9", "z": "3"}, "B": {"q": "4"}}


def by_domain(plans):
    return {plan["domain"]: plan for plan in plans}


full = by_domain(ks.plan_apply(managed, current, "apply"))
assert full["A"]["final"] == {"x": "1", "y": "2"}, full
assert (full["A"]["added"], full["A"]["updated"], full["A"]["removed"]) == (["x"], ["y"], ["z"])
assert full["B"]["final"] is None and full["B"]["removed"] == ["q"], full

keep = by_domain(ks.plan_apply(managed, current, "apply-keep"))
assert keep["A"]["final"] == {"x": "1", "y": "2", "z": "3"}, keep
assert keep["A"]["removed"] == [] and "B" not in keep, keep

prune = by_domain(ks.plan_apply(managed, current, "prune"))
assert prune["A"]["final"] == {"y": "9"} and prune["A"]["removed"] == ["z"], prune
assert prune["A"]["added"] == [] and prune["A"]["updated"] == [], prune
assert prune["B"]["final"] is None and prune["B"]["removed"] == ["q"], prune

assert ks.plan_apply({"A": {"x": "1"}}, {"A": {"x": "1"}}, "apply") == []

result, changes = ks.plan_sync(managed, current, add_only=False)
assert result == {"A": {"y": "9", "z": "3"}, "B": {"q": "4"}}, result
assert "[remove] A: x" in changes and "[add]    A: z = 3" in changes, changes

result, changes = ks.plan_sync(managed, current, add_only=True)
assert result["A"] == {"x": "1", "y": "9", "z": "3"}, result
assert not [c for c in changes if c.startswith("[remove]")], changes
PYTEST
then
  echo "  ok   - plan_apply（apply / apply-keep / prune）と plan_sync（sync / merge）"
else
  echo "  FAIL - plan_apply / plan_sync" >&2
  FAILURES=$((FAILURES + 1))
fi
run_dots shortcuts prune --yes
check "shortcuts prune は --yes を受け付けない" eq "$RC" 1

echo
if (( FAILURES > 0 )); then
  echo "FAILED: ${FAILURES} 件" >&2
  exit 1
fi
echo "All tests passed."
