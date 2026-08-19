#!/usr/bin/env pwsh
# ghq-update: ghq 管理リポジトリを更新する
#
# 使い方:
#   ghq-update [options]
#
# オプション:
#   --all           sync 対象を「keep-up-to-date=true」から
#                   「keep-up-to-date=true ∪ .venv/node_modules が存在する」に拡張する
#   --pull-all      fetch + pull 対象を全リポジトリに拡張する（sync 対象には影響しない）
#   --uv-sync-only  fetch + pull をスキップし、sync 対象への処理（uv sync --upgrade /
#                   npm update && npm run build --if-present）のみ実行する
#                   （事前に ghq-pull 等で pull 済みであることが前提）
#   --pull-only     fetch + pull のみ実行し、sync 対象への処理をスキップする
#                   （--uv-sync-only と同時指定は不可）
#   --no-auto-pr    uv sync --upgrade / npm update でロックファイルのみ更新された場合の
#                   自動 PR 作成を無効化し、従来通り working tree に dirty な差分を残す
#   -f, --filter PATTERN  リポジトリパスが正規表現 PATTERN にマッチするものだけを対象にする
#   -h, --help      ヘルプを表示
#
# 動作:
#   sync 対象（uv/npm 共通）:
#     - デフォルト: keep-up-to-date=true のリポジトリ
#     - --all:      上記 ∪ .venv または node_modules が存在するリポジトリ
#     - .venv が存在する場合: uv sync --upgrade を実行する
#       （pyproject.toml/uv.lock はあるが .venv が無い場合は warning を出し
#         uv sync のみスキップする。uv 設定自体が無ければ何もしない）
#     - node_modules が存在する場合: npm update && npm run build --if-present を実行する
#       （package.json はあるが node_modules が無い場合は warning を出し
#         npm 処理のみスキップする。install 済みでなければ自動 install はしない。
#         package.json 自体が無ければ何もしない）
#     - pull は通常通り行う
#   fetch + pull 対象（pull 対象）:
#     - デフォルト: sync 対象と同じ
#     - --pull-all: 全リポジトリに拡張する（旧 --all 相当。--all と併用すると
#       「全リポジトリ pull + sync 対象を sync」というフル動作になる）
#     - --uv-sync-only 指定時は pull 自体を行わず、sync 対象にのみ処理する
#   共通:
#     - dotfiles・dev-charter は他より先に処理する（ghq-status の基準バージョン等、
#       他リポジトリの処理より先に最新化しておきたいため）
#     - detached HEAD・upstream 未設定の場合は pull をスキップ（fetch は実行）
#     - uv.lock/package-lock.json のみ dirty な場合は一時的に stash して pull し、
#       pull 後に復元する（復元時にコンフリクトした場合は stash を残したまま警告を表示する）
#     - それら以外にも dirty な変更がある場合は pull をスキップ
#   auto-pr（デフォルト有効。--no-auto-pr で無効化）:
#     - uv sync --upgrade / npm update の結果、対応するロックファイル（uv.lock /
#       package-lock.json）のみが dirty な場合、専用ブランチ（chore/uv-lock-update /
#       chore/npm-lock-update）にコミットして force push し、gh で PR を作成する
#     - 既に同名ブランチで open な PR があれば push だけでその PR に反映される
#     - gh 未インストール・未認証、またはロックファイル以外にも dirty な変更がある場合は
#       スキップし、従来通り working tree に差分を残す

Set-StrictMode -Version Latest

. "$PSScriptRoot\_ghq-lib.ps1"

function Show-Help {
    $lines = @(Get-Content -LiteralPath $PSCommandPath)
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line -eq '') { break }
        Write-Host ($line -replace '^#\s?', '')
    }
}

function Get-KeepUpToDate([string]$Repo) {
    $val = (& git -C $Repo config --bool local.keep-up-to-date 2>$null)
    return $val -eq 'true'
}

$ALL = $false
$PULL_ALL = $false
$UV_SYNC_ONLY = $false
$PULL_ONLY = $false
$AUTO_PR = $true
$FILTER = ''

$i = 0
while ($i -lt $args.Count) {
    $arg = $args[$i]
    if ($arg -eq '--all') {
        $ALL = $true
        $i++
    } elseif ($arg -eq '--pull-all') {
        $PULL_ALL = $true
        $i++
    } elseif ($arg -eq '--uv-sync-only') {
        $UV_SYNC_ONLY = $true
        $i++
    } elseif ($arg -eq '--pull-only') {
        $PULL_ONLY = $true
        $i++
    } elseif ($arg -eq '--no-auto-pr') {
        $AUTO_PR = $false
        $i++
    } elseif ($arg -eq '-f' -or $arg -eq '--filter') {
        if ($i + 1 -ge $args.Count) {
            Write-GhqStderr "error: --filter requires an argument"
            exit 1
        }
        $FILTER = $args[$i + 1]
        $i += 2
    } elseif ($arg -eq '-h' -or $arg -eq '--help') {
        Show-Help
        exit 0
    } else {
        Write-GhqStderr "error: unknown option: $arg"
        exit 1
    }
}

if ($PULL_ONLY -and $UV_SYNC_ONLY) {
    Write-GhqStderr "error: --pull-only と --uv-sync-only は同時に指定できません"
    exit 1
}

if (-not (Get-Command ghq -ErrorAction SilentlyContinue)) {
    Write-GhqStderr "error: 'ghq' が見つかりません。"
    exit 1
}

$repos = Get-GhqOrderedList $FILTER

foreach ($f in $repos) {
    $kutd = Get-KeepUpToDate $f
    $hasVenv = Test-Path -LiteralPath (Join-Path $f '.venv')
    $hasNodeModules = Test-Path -LiteralPath (Join-Path $f 'node_modules')

    $inSyncTarget = $kutd -or ($ALL -and ($hasVenv -or $hasNodeModules))
    $inVisitSet = $inSyncTarget -or $PULL_ALL

    if (-not $inVisitSet) { continue }

    Write-Host ""
    Write-Host "==> $f"

    $global:LASTEXITCODE = $null
    $baseBranch = (& git -C $f symbolic-ref --short HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [skip] detached HEAD"
        continue
    }

    if ($UV_SYNC_ONLY) {
        $pulled = $true
    } else {
        $global:LASTEXITCODE = $null
        & git -C $f fetch origin --prune
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [skip pull] fetch failed"
            continue
        }

        $global:LASTEXITCODE = $null
        & git -C $f rev-parse '@{u}' *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [skip pull] no upstream"
            continue
        }
        if (-not (Push-GhqLockfileStash $f)) {
            Write-Host "  [skip pull] dirty working tree"
            continue
        }

        $global:LASTEXITCODE = $null
        & git -C $f pull --ff-only
        $pulled = ($LASTEXITCODE -eq 0)
        if (-not (Pop-GhqLockfileStash $f)) {
            continue
        }
    }

    if ($inSyncTarget -and (-not $PULL_ONLY) -and $pulled) {
        if ($hasVenv) {
            Push-Location $f
            try { & uv sync --upgrade } finally { Pop-Location }
            if ($AUTO_PR) {
                Invoke-GhqAutoPrLockfile $f $baseBranch 'uv.lock' 'chore/uv-lock-update' `
                    'chore: update uv.lock' `
                    'uv sync --upgrade により生成された uv.lock の更新です（ghq-update の自動 PR 機能）。'
            }
        } else {
            $hasUvProject = (Test-Path -LiteralPath (Join-Path $f 'pyproject.toml')) -or (Test-Path -LiteralPath (Join-Path $f 'uv.lock'))
            if ($hasUvProject) {
                Write-GhqStderr "  [warn] keep-up-to-date=true ですが .venv が見つかりません（uv 設定はあるので uv sync 未実行の可能性があります。uv sync をスキップします）"
            }
        }

        if ($hasNodeModules) {
            Push-Location $f
            try {
                $global:LASTEXITCODE = $null
                & npm update
                if ($LASTEXITCODE -eq 0) { & npm run build --if-present }
            } finally { Pop-Location }
            if ($AUTO_PR) {
                Invoke-GhqAutoPrLockfile $f $baseBranch 'package-lock.json' 'chore/npm-lock-update' `
                    'chore: update package-lock.json' `
                    'npm update により生成された package-lock.json の更新です（ghq-update の自動 PR 機能）。'
            }
        } else {
            $hasNpmProject = Test-Path -LiteralPath (Join-Path $f 'package.json')
            if ($hasNpmProject) {
                Write-GhqStderr "  [warn] keep-up-to-date=true ですが node_modules が見つかりません（npm install 未実行の可能性があります。npm update/build をスキップします）"
            }
        }
    }
}
