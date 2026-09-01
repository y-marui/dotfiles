#!/usr/bin/env pwsh
# ghq-sweep: ghq 管理リポジトリのマージ済みブランチを一括整理する
#
# 使い方:
#   ghq-sweep [options]
#
# オプション:
#   -f, --filter PATTERN  リポジトリパスが正規表現 PATTERN にマッチするものだけを対象にする
#   -s, --status-only    ghq-status で異常が検出されたリポジトリだけを対象にする
#                        （ghq-status --paths-only の結果を使う。-f と併用可）
#   -h, --help          ヘルプを表示
#
# 動作:
#   ghq list -p のリポジトリ（-s 指定時は ghq-status --paths-only の結果）に対して
#   git-sweep --all を実行する。
#   各リポジトリのマージ済みブランチをすべて削除し、main を最新に保つ。
#   uv.lock/package-lock.json のみ dirty な場合は一時的に stash して実行し、
#   実行後に復元する（復元時にコンフリクトした場合は stash を残したまま失敗として扱う）。
#   それら以外にも dirty な変更がある場合はスキップする。

Set-StrictMode -Version Latest

. "$PSScriptRoot\_ghq-lib.ps1"

function Show-Help {
    $lines = @(Get-Content -LiteralPath $PSCommandPath)
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line -eq '') { break }
        Write-Host ($line -replace '^#\s?', '')
    }
}

$FILTER = ''
$STATUS_ONLY = $false

$i = 0
while ($i -lt $args.Count) {
    $arg = $args[$i]
    if ($arg -eq '-f' -or $arg -eq '--filter') {
        if ($i + 1 -ge $args.Count) {
            Write-GhqStderr "error: --filter requires an argument"
            exit 1
        }
        $FILTER = $args[$i + 1]
        $i += 2
    } elseif ($arg -eq '-s' -or $arg -eq '--status-only') {
        $STATUS_ONLY = $true
        $i++
    } elseif ($arg -eq '-h' -or $arg -eq '--help') {
        Show-Help
        exit 0
    } else {
        Write-GhqStderr "error: unknown option: $arg"
        exit 1
    }
}

if (-not (Get-Command git-sweep -ErrorAction SilentlyContinue)) {
    Write-GhqStderr "error: 'git-sweep' が見つかりません。"
    exit 1
}

if (-not (Get-Command ghq -ErrorAction SilentlyContinue)) {
    Write-GhqStderr "error: 'ghq' が見つかりません。"
    exit 1
}

$ok = 0
$skipped = 0
$failed = 0

if ($STATUS_ONLY) {
    $global:LASTEXITCODE = $null
    $repos = @(& "$PSScriptRoot\ghq-status.ps1" --paths-only --filter $FILTER)
} else {
    $repos = @(& ghq list -p) | Sort-Object
    if ($FILTER) {
        # owner/repo 記法（"/"区切り）でフィルタを書けるよう、Windowsのバックスラッシュ
        # パスを比較用に正規化する（実際のファイル操作には元のパスを使う）
        $repos = @($repos | Where-Object { ($_ -replace '\\', '/') -match $FILTER })
    }
}

foreach ($repo in $repos) {
    Write-Host ""
    Write-Host "==> $repo"

    $global:LASTEXITCODE = $null
    & git -C $repo symbolic-ref --short HEAD *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [skip] detached HEAD"
        $skipped++
        continue
    }

    if (-not (Push-GhqLockfileStash $repo)) {
        Write-Host "  [skip] dirty working tree"
        $skipped++
        continue
    }

    $sweepOk = $true
    Push-Location $repo
    try {
        & git-sweep --all
        if ($LASTEXITCODE -ne 0) { $sweepOk = $false }
    } finally {
        Pop-Location
    }
    if (-not (Pop-GhqLockfileStash $repo)) { $sweepOk = $false }

    if ($sweepOk) {
        $ok++
    } else {
        Write-GhqStderr "  [failed]"
        $failed++
    }
}

Write-Host ""
Write-Host "完了: 成功 $ok / スキップ $skipped / 失敗 $failed"
