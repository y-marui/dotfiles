#!/usr/bin/env bash
# bin/unix/install-my-apps の回帰テスト。Build フォルダも Applications も一時ディレクトリに
# 差し替え、--no-gui で実行するため、実環境の /Applications・iCloud・起動中のアプリには触れない。
# macOS 専用（hdiutil で本物の DMG を作る）。
set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "skip: install-my-apps のテストは macOS 専用です"
  exit 0
fi

CMD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/unix/install-my-apps"
WORK="$(mktemp -d)"
FAILURES=0
trap 'rm -rf "$WORK"' EXIT

BUILD="$WORK/build"
APPS="$WORK/apps"
export INSTALL_MY_APPS_BUILD_DIR="$BUILD"
export INSTALL_MY_APPS_APPS_ROOT="$APPS"

check() {
  local label="$1"
  shift
  if "$@"; then
    echo "ok   - $label"
  else
    echo "FAIL - $label"
    FAILURES=$((FAILURES + 1))
  fi
}
exists() { [[ -d "$1" ]]; }
missing() { [[ ! -e "$1" ]]; }
contains() { [[ "$1" == *"$2"* ]]; }

make_app() { # dir name bundle-id [mas]
  mkdir -p "$1/$2.app/Contents"
  cat > "$1/$2.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>$3</string></dict></plist>
PLIST
  [[ "${4:-}" == mas ]] && mkdir -p "$1/$2.app/Contents/_MASReceipt"
  return 0
}

make_dmg() { # dest-dir name bundle-id
  local src
  src="$(mktemp -d "$WORK/src.XXXXXX")"
  make_app "$src" "$2" "$3"
  mkdir -p "$1"
  hdiutil create -quiet -srcfolder "$src" -volname "tst-$2-$RANDOM" -format UDZO "$1/$2.dmg"
}

run() { "$CMD" --no-gui "$@" 2>&1; }

reset() { rm -rf "$BUILD" "$APPS"; mkdir -p "$BUILD" "$APPS"; }

# ── 種類ごとのフォルダ ──────────────────────────────
reset
make_dmg "$BUILD/Swift" "Alpha" "test.alpha"
make_dmg "$BUILD/Tauri" "Beta" "test.beta"
out=$(run)
check "Swift DMG goes to My Swift" exists "$APPS/My Swift/Alpha.app"
check "Tauri DMG goes to My Tauri" exists "$APPS/My Tauri/Beta.app"
check "nothing is placed directly in the Applications root" missing "$APPS/Alpha.app"
check "the install folders are shown" contains "$out" "My Swift"

# ── 移行前の Build 直下の DMG は Swift 扱い ────────────
reset
make_dmg "$BUILD" "Gamma" "test.gamma"
out=$(run)
check "a DMG left in Build is installed as Swift" exists "$APPS/My Swift/Gamma.app"
check "a notice says to move it" contains "$out" "Build/Swift へ移してください"

# ── Build/Swift に同名があれば Build 直下の DMG は使わない ─
reset
make_dmg "$BUILD" "Delta" "test.old"
make_dmg "$BUILD/Swift" "Delta" "test.new"
run >/dev/null
id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APPS/My Swift/Delta.app/Contents/Info.plist")
check "Build/Swift wins over a same-named DMG in Build" [ "$id" = "test.new" ]

# ── 名前を指定する ──────────────────────────────────
reset
make_dmg "$BUILD/Swift" "Alpha" "test.alpha"
make_dmg "$BUILD/Tauri" "Beta" "test.beta"
run Beta >/dev/null
check "a named app finds its DMG in the Tauri folder" exists "$APPS/My Tauri/Beta.app"
check "only the named app is installed" missing "$APPS/My Swift/Alpha.app"

# ── 旧い置き場の整理（移行期間の措置、既定 ON）────────
reset
make_dmg "$BUILD/Swift" "Eps" "test.eps"
make_app "$APPS" "Eps" "test.eps"
out=$(run)
check "migration removes the old copy with the same bundle id" missing "$APPS/Eps.app"
check "the new copy is installed" exists "$APPS/My Swift/Eps.app"

reset
make_dmg "$BUILD/Swift" "Zeta" "test.zeta"
make_app "$APPS" "Zeta" "other.zeta"
out=$(run)
check "an old copy with another bundle id is kept" exists "$APPS/Zeta.app"
check "and the user is told" contains "$out" "バンドル ID が違う"

reset
make_dmg "$BUILD/Swift" "Eta" "test.eta"
make_app "$APPS" "Eta" "test.eta" mas
out=$(run)
check "an App Store copy is kept" exists "$APPS/Eta.app"
check "and the user is told" contains "$out" "App Store 版"

reset
make_dmg "$BUILD/Swift" "Theta" "test.theta"
make_app "$APPS" "Theta" "test.theta"
make_app "$APPS/My Swift" "Theta" "test.theta"
out=$(run --force)
check "when both places have it, the old copy is not deleted" exists "$APPS/Theta.app"
check "and the user is told" contains "$out" "新旧の両方にある"

reset
make_dmg "$BUILD/Swift" "Iota" "test.iota"
make_app "$APPS" "Iota" "test.iota"
make_app "$APPS/My Swift" "Iota" "test.iota"
run --reinstall >/dev/null
check "a reinstall does not turn 'both' into a deletion" exists "$APPS/Iota.app"

# ── オプションで切る ────────────────────────────────
reset
make_dmg "$BUILD/Swift" "Kappa" "test.kappa"
make_app "$APPS" "Kappa" "test.kappa"
run --no-migrate-old >/dev/null
check "--no-migrate-old keeps the old copy" exists "$APPS/Kappa.app"

reset
make_dmg "$BUILD/Swift" "Lambda" "test.lambda"
make_app "$APPS" "Lambda" "test.lambda"
INSTALL_MY_APPS_MIGRATE_OLD=0 run >/dev/null
check "INSTALL_MY_APPS_MIGRATE_OLD=0 keeps the old copy" exists "$APPS/Lambda.app"

reset
make_dmg "$BUILD/Swift" "Mu" "test.mu"
make_app "$APPS" "Mu" "test.mu"
INSTALL_MY_APPS_MIGRATE_OLD=0 run --migrate-old >/dev/null
check "--migrate-old overrides the environment default" missing "$APPS/Mu.app"

# ── アンインストール ────────────────────────────────
reset
make_dmg "$BUILD/Swift" "Nu" "test.nu"
make_dmg "$BUILD/Tauri" "Xi" "test.xi"
run >/dev/null
make_app "$APPS" "Nu" "test.nu"
out=$(run --uninstall)
check "uninstall removes the app from My Swift" missing "$APPS/My Swift/Nu.app"
check "uninstall removes the app from My Tauri" missing "$APPS/My Tauri/Xi.app"
check "uninstall leaves an old copy and says so" exists "$APPS/Nu.app"
check "the notice names the old copy" contains "$out" "旧い置き場に残っています"

# ── 入れ先を環境変数で /Applications 直下（ここでは一時の Applications ルート）に変える ──
reset
make_dmg "$BUILD/Swift" "Pi" "test.pi"
make_app "$APPS" "Pi" "test.pi"
INSTALL_MY_APPS_SWIFT_DIR="$APPS" run >/dev/null
check "INSTALL_MY_APPS_SWIFT_DIR installs directly into the root" exists "$APPS/Pi.app"
check "and nothing goes to My Swift" missing "$APPS/My Swift/Pi.app"

reset
make_dmg "$BUILD/Tauri" "Rho" "test.rho"
INSTALL_MY_APPS_TAURI_DIR="$WORK/elsewhere" run >/dev/null
check "INSTALL_MY_APPS_TAURI_DIR changes the Tauri folder" exists "$WORK/elsewhere/Rho.app"

# ── 同バージョンはスキップ ──────────────────────────
reset
make_dmg "$BUILD/Swift" "Omicron" "test.omicron"
run >/dev/null
out=$(run)
check "an unchanged app is skipped the second time" contains "$out" "最新版がインストール済み"

if (( FAILURES > 0 )); then
  echo ""
  echo "$FAILURES check(s) failed"
  exit 1
fi
echo ""
echo "all checks passed"
