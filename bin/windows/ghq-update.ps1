#!/usr/bin/env pwsh
# ghq-update: ghq 管理リポジトリを更新する
#
# 使い方:
#   ghq-update [options]
#
# オプション:
#   --all        全リポジトリを fetch + pull し、uv sync は keep-up-to-date=true のみ
#                （省略時は keep-up-to-date=true のリポジトリのみ pull + uv sync）
#   --pull-only  uv sync --upgrade をスキップ
#   --no-auto-pr uv sync --upgrade で uv.lock のみ更新された場合の自動 PR 作成を無効化し、
#                従来通り working tree に dirty な差分を残す
#   -f, --filter PATTERN  リポジトリパスが正規表現 PATTERN にマッチするものだけを対象にする
#   -h, --help   ヘルプを表示
#
# 動作:
#   デフォルト:
#     - keep-up-to-date=true のリポジトリのみ git fetch + pull --ff-only
#     - uv.lock のみ dirty な場合は一時的に stash して pull し、pull 後に復元する
#     - uv.lock 以外にも dirty な変更がある場合は fetch のみ実行し pull をスキップ
#     - .venv があれば uv sync --upgrade（pull 成功時のみ）
#   --all:
#     - 全リポジトリを git fetch origin --prune + git pull --ff-only
#     - detached HEAD・upstream 未設定の場合は pull をスキップ（fetch は実行）
#     - uv.lock のみ dirty な場合は一時的に stash して pull し、pull 後に復元する
#     - uv.lock 以外にも dirty な変更がある場合は pull をスキップ
#     - 復元時にコンフリクトした場合は stash を残したまま警告を表示する
#     - .venv があり keep-up-to-date=true のリポジトリのみ uv sync --upgrade（pull 成功時のみ）
#   auto-pr（デフォルト有効。--no-auto-pr で無効化）:
#     - uv sync --upgrade の結果 uv.lock のみが dirty な場合、chore/uv-lock-update
#       ブランチにコミットして force push し、gh で PR を作成する
#     - 既に同名ブランチで open な PR があれば push だけでその PR に反映される
#     - gh 未インストール・未認証、または uv.lock 以外にも dirty な変更がある場合はスキップし、
#       従来通り working tree に差分を残す

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
$PULL_ONLY = $false
$AUTO_PR = $true
$FILTER = ''

$i = 0
while ($i -lt $args.Count) {
    $arg = $args[$i]
    if ($arg -eq '--all') {
        $ALL = $true
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

if (-not (Get-Command ghq -ErrorAction SilentlyContinue)) {
    Write-GhqStderr "error: 'ghq' が見つかりません。"
    exit 1
}

$repos = @(& ghq list -p) | Sort-Object
if ($FILTER) {
    # owner/repo 記法（"/"区切り）でフィルタを書けるよう、Windowsのバックスラッシュ
    # パスを比較用に正規化する（実際のファイル操作には元のパスを使う）
    $repos = @($repos | Where-Object { ($_ -replace '\\', '/') -match $FILTER })
}

foreach ($f in $repos) {
    Write-Host ""
    Write-Host "==> $f"

    if ($ALL) {
        $global:LASTEXITCODE = $null
        $baseBranch = (& git -C $f symbolic-ref --short HEAD 2>$null)
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [skip] detached HEAD"
            continue
        }

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
        if (-not (Push-GhqUvLockStash $f)) {
            Write-Host "  [skip pull] dirty working tree"
            continue
        }

        $global:LASTEXITCODE = $null
        & git -C $f pull --ff-only
        $pulled = ($LASTEXITCODE -eq 0)
        if (-not (Pop-GhqUvLockStash $f)) {
            continue
        }

        if ($pulled -and (-not $PULL_ONLY) -and (Get-KeepUpToDate $f) -and (Test-Path -LiteralPath (Join-Path $f '.venv'))) {
            Push-Location $f
            try { & uv sync --upgrade } finally { Pop-Location }
            if ($AUTO_PR) { Invoke-GhqAutoPrUvLock $f $baseBranch }
        }
    } else {
        if (-not (Get-KeepUpToDate $f)) {
            continue
        }

        $global:LASTEXITCODE = $null
        $baseBranch = (& git -C $f symbolic-ref --short HEAD 2>$null)
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [skip] detached HEAD"
            continue
        }

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
        if (-not (Push-GhqUvLockStash $f)) {
            Write-Host "  [skip pull] dirty working tree"
            continue
        }

        $global:LASTEXITCODE = $null
        & git -C $f pull --ff-only
        $pulled = ($LASTEXITCODE -eq 0)
        if (-not (Pop-GhqUvLockStash $f)) {
            continue
        }

        if ($pulled -and (-not $PULL_ONLY) -and (Test-Path -LiteralPath (Join-Path $f '.venv'))) {
            Push-Location $f
            try { & uv sync --upgrade } finally { Pop-Location }
            if ($AUTO_PR) { Invoke-GhqAutoPrUvLock $f $baseBranch }
        }
    }
}
