#!/usr/bin/env pwsh
# scripts/uninstall.ps1
# Windows 向けシンボリックリンク削除スクリプト。
# macOS/Linux の scripts/uninstall.sh に相当。
#
# 使い方:
#   pwsh scripts/uninstall.ps1 [-Yes]

param(
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\_links.ps1"

function Test-DotfilesTarget([string]$Target) {
    $resolved = $Target
    if (-not [System.IO.Path]::IsPathRooted($resolved)) {
        $resolved = Join-Path $DOTFILES_DIR $resolved
    }
    return $resolved.StartsWith($DOTFILES_DIR, [System.StringComparison]::OrdinalIgnoreCase)
}

if (-not $Yes) {
    Write-Host "以下のシンボリックリンクを削除します（dotfiles を指すもののみ）:"
    foreach ($link in $Links) {
        $item = Get-Item -LiteralPath $link.Dest -ErrorAction SilentlyContinue -Force
        if ($item -and $item.LinkType -eq 'SymbolicLink' -and (Test-DotfilesTarget([string]$item.Target))) {
            Write-Host "  $($link.Dest)"
        }
    }
    Write-Host ""
    $answer = Read-Host "続けますか？ [y/N]"
    if ($answer -notmatch '^[Yy]$') {
        Write-Host "キャンセルしました。"
        exit 0
    }
}

$countRemoved = 0
$countSkip    = 0

foreach ($link in $Links) {
    $dest = $link.Dest
    $item = Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue -Force

    if ($item -and $item.LinkType -eq 'SymbolicLink') {
        if (Test-DotfilesTarget([string]$item.Target)) {
            Remove-Item -LiteralPath $dest -Force
            Write-Host "  REMOVED $dest"
            $countRemoved++
        } else {
            Write-Host "  SKIP    $dest (dotfiles 以外を指すリンク)"
            $countSkip++
        }
    } else {
        $countSkip++
    }
}

Write-Host ""
Write-Host "完了: 削除=$countRemoved  スキップ=$countSkip"
