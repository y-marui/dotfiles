#!/usr/bin/env pwsh
# scripts/setup-user-path.ps1
# bin\windows のコマンド（git-sweep・obsidian-project-home 等）を、PowerShell
# プロファイルを読まないシェル（Claude Code の Bash/PowerShell ツール等）からも
# 呼べるよう、~\.local\bin\dotfiles をユーザー PATH に恒久的に追加する。
# べき等。`make install-windows` から呼ぶ（`make links` では PATH を触らない）。
#
# 使い方:
#   pwsh scripts/setup-user-path.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dotfilesBin = Join-Path $HOME '.local\bin\dotfiles'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$userEntries = @($userPath -split ';' | Where-Object { $_ })

if ($userEntries | Where-Object { $_.TrimEnd('\') -ieq $dotfilesBin }) {
    Write-Host "  SKIP    PATH $dotfilesBin"
    exit 0
}

$updatedPath = if ($userEntries.Count -gt 0) { "$userPath;$dotfilesBin" } else { $dotfilesBin }
[Environment]::SetEnvironmentVariable('Path', $updatedPath, 'User')
Write-Host "  PATH    $dotfilesBin"
