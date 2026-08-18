#!/usr/bin/env pwsh
# ghq-pull: ghq 管理リポジトリの全リポジトリを fetch + pull する
#
# 使い方:
#   ghq-pull [options]
#
# オプション:
#   --fetch-only        fetch のみ実行（pull をスキップ）
#   -f, --filter PATTERN  リポジトリパスが正規表現 PATTERN にマッチするものだけを対象にする
#   -h, --help          ヘルプを表示
#
# 動作:
#   - git fetch origin --prune を実行する（dirty でも実行）
#   - fetch 失敗・detached HEAD・upstream 未設定の場合は pull をスキップ
#   - uv.lock のみ dirty な場合は一時的に stash して pull し、pull 後に復元する
#     （復元時にコンフリクトした場合は stash を残したまま警告を表示する）
#   - uv.lock 以外にも dirty な変更がある場合は pull をスキップ
#   - それ以外は git pull --ff-only を実行する

Set-StrictMode -Version Latest

. "$PSScriptRoot\_ghq-lib.ps1"

function Show-Help {
    $lines = @(Get-Content -LiteralPath $PSCommandPath)
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line -eq '') { break }
        Write-Host ($line -replace '^#\s?', '')
    }
}

$FETCH_ONLY = $false
$FILTER = ''

$i = 0
while ($i -lt $args.Count) {
    $arg = $args[$i]
    if ($arg -eq '--fetch-only') {
        $FETCH_ONLY = $true
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

    $global:LASTEXITCODE = $null
    & git -C $f fetch origin --prune
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [skip pull] fetch failed"
        continue
    }

    if (-not $FETCH_ONLY) {
        $global:LASTEXITCODE = $null
        & git -C $f symbolic-ref --short HEAD *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [skip pull] detached HEAD"
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
        & git -C $f pull --ff-only
        Pop-GhqUvLockStash $f | Out-Null
    }
}
