#!/usr/bin/env pwsh
# update-wsl: WSLに登録されたapt系ディストリビューション（Ubuntu・Debian等）のOSパッケージを更新する
# 使い方: update-wsl [--list] [<distro>...]
#   <distro>      更新するディストリビューション名（wsl -l -q の名前）。省略すると登録済みの全apt系が対象
#   --list        更新せず、対象と判定結果だけを表示
#   -h, --help    ヘルプを表示
#
# 対象は wsl.exe の登録一覧から毎回取得するため、ディストリビューションの追加・名前変更に追従する。
# apt-get があるものだけ更新し、それ以外（docker-desktop等の内部ディストリビューションを含む）は
# スキップする。更新はrootで非対話に実行する（apt update/upgrade/dist-upgrade/autoremove/autoclean）。
# 一部が失敗しても残りを続け、最後に失敗を報告して終了コード1で終わる。

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-Help {
    $lines = @(Get-Content -LiteralPath $PSCommandPath)
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line -eq '') { break }
        Write-Host ($line -replace '^#\s?', '')
    }
}

$listOnly = $false
$requested = @()
foreach ($argument in $args) {
    switch -CaseSensitive ($argument) {
        { $_ -in '-h', '--help' } { Show-Help; exit 0 }
        '--list' { $listOnly = $true }
        default {
            if ($argument.StartsWith('-')) {
                Write-Host "unknown option: $argument"
                exit 1
            }
            $requested += $argument
        }
    }
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Host '  SKIP    WSL (wsl.exe not found)'
    exit 0
}

# wsl -l -q はUTF-16LEで出力する。
function Get-WslDistributions {
    $previous = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        $names = @(& wsl.exe -l -q 2>$null)
        if ($LASTEXITCODE -ne 0) { return @() }
    } finally {
        [Console]::OutputEncoding = $previous
    }
    $names | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ }
}

# Docker Desktop等が作る内部ディストリビューションは、OSとして更新しない。
$internalPattern = '^(docker-desktop(-data)?|rancher-desktop(-data)?)$'

$installed = @(Get-WslDistributions)
if ($installed.Count -eq 0) {
    Write-Host '  SKIP    WSL (no distributions registered)'
    exit 0
}

if ($requested.Count -gt 0) {
    $missing = @($requested | Where-Object { $_ -notin $installed })
    if ($missing.Count -gt 0) {
        Write-Host "unknown distribution: $($missing -join ', ') (registered: $($installed -join ', '))"
        exit 1
    }
    $targets = $requested
} else {
    $targets = @($installed | Where-Object { $_ -notmatch $internalPattern })
}

# apt-getの有無で更新方式を判定する。名前（Ubuntu-24.04等）には依存しない。
$updateScript = @'
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get -y upgrade && apt-get -y dist-upgrade && apt-get -y autoremove && apt-get -y autoclean
'@

$failed = @()
foreach ($distro in $targets) {
    & wsl.exe -d $distro -u root -- sh -c 'command -v apt-get >/dev/null 2>&1' *>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  SKIP    $distro (apt-get not found)"
        continue
    }
    if ($listOnly) {
        Write-Host "  TARGET  $distro"
        continue
    }

    Write-Host "=== $distro ==="
    & wsl.exe -d $distro -u root -- sh -c $updateScript
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "$distro の更新に失敗しました（exit $LASTEXITCODE）"
        $failed += $distro
    }
}

if ($failed.Count -gt 0) {
    Write-Host "failed: $($failed -join ', ')"
    exit 1
}
