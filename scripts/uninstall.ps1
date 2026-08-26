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

function Test-ManagedTarget([string]$Target, [string]$SourceRoot) {
    $resolved = $Target
    if (-not [System.IO.Path]::IsPathRooted($resolved)) {
        $resolved = [System.IO.Path]::GetFullPath((Join-Path $HOME $resolved))
    }
    return $resolved.Equals($SourceRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $resolved.StartsWith("$SourceRoot\", [System.StringComparison]::OrdinalIgnoreCase)
}

function Show-ManagedLinks {
    param(
        [Parameter(Mandatory)] [string]$SourceRoot,
        [Parameter(Mandatory)] [array]$LinkEntries
    )

    foreach ($link in $LinkEntries) {
        $item = Get-Item -LiteralPath $link.Dest -ErrorAction SilentlyContinue -Force
        if ($item -and $item.LinkType -eq 'SymbolicLink' -and
            (Test-ManagedTarget -Target ([string]$item.Target) -SourceRoot $SourceRoot)) {
            Write-Host "  $($link.Dest)"
        }
    }
}

function Remove-LinkSet {
    param(
        [Parameter(Mandatory)] [string]$SourceRoot,
        [Parameter(Mandatory)] [array]$LinkEntries
    )

    foreach ($link in $LinkEntries) {
        $dest = $link.Dest
        $item = Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue -Force

        if ($item -and $item.LinkType -eq 'SymbolicLink') {
            if (Test-ManagedTarget -Target ([string]$item.Target) -SourceRoot $SourceRoot) {
                Remove-Item -LiteralPath $dest -Force
                Write-Host "  REMOVED $dest"
                $script:countRemoved++
            } else {
                Write-Host "  SKIP    $dest (管理対象外を指すリンク)"
                $script:countSkip++
            }
        } else {
            $script:countSkip++
        }
    }
}

if (-not $Yes) {
    Write-Host "以下のシンボリックリンクを削除します（dotfiles / dotfiles-private を指すもののみ）:"
    Show-ManagedLinks -SourceRoot $DOTFILES_DIR -LinkEntries $Links
    if (Test-Path -LiteralPath $PrivateLinksFile -PathType Leaf) {
        $allPrivateLinks = @($PrivateLinks) + @($InactivePrivateLinks)
        Show-ManagedLinks -SourceRoot $PRIVATE_DIR -LinkEntries $allPrivateLinks
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

Remove-LinkSet -SourceRoot $DOTFILES_DIR -LinkEntries $Links
if (Test-Path -LiteralPath $PrivateLinksFile -PathType Leaf) {
    $allPrivateLinks = @($PrivateLinks) + @($InactivePrivateLinks)
    Remove-LinkSet -SourceRoot $PRIVATE_DIR -LinkEntries $allPrivateLinks
}

Write-Host ""
Write-Host "完了: 削除=$countRemoved  スキップ=$countSkip"
