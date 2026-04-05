#!/usr/bin/env pwsh
# scripts/install.ps1
# Windows 用 dotfiles シンボリックリンク作成スクリプト。
# macOS/Linux の scripts/install.sh に相当。
#
# 使い方:
#   pwsh scripts/install.ps1
#
# 注意: シンボリックリンクの作成には以下のいずれかが必要:
#   - Windows Developer Mode が有効（設定 > システム > 開発者向け）
#   - 管理者権限で実行

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DOTFILES_DIR = Split-Path -Parent $PSScriptRoot

$backupDir = Join-Path $HOME ".dotfiles-backup" (Get-Date -Format 'yyyyMMddHHmmss')

# Windows で使う設定のリンク定義
$links = @(
    [pscustomobject]@{
        Src  = "terminal\powershell\profile.ps1"
        Dest = Join-Path $HOME ".config\powershell\Microsoft.PowerShell_profile.ps1"
    }
    [pscustomobject]@{
        Src  = "terminal\ohmyposh\p10k-lean.json"
        Dest = Join-Path $HOME ".config\oh-my-posh\p10k-lean.json"
    }
    [pscustomobject]@{
        Src  = "terminal\zellij\config.kdl"
        Dest = Join-Path $HOME ".config\zellij\config.kdl"
    }
    [pscustomobject]@{
        Src  = "git\gitconfig"
        Dest = Join-Path $HOME ".gitconfig"
    }
    [pscustomobject]@{
        Src  = "git\gitignore_global"
        Dest = Join-Path $HOME ".gitignore_global"
    }
    [pscustomobject]@{
        Src  = "git\gitconfig.d\aliases.gitconfig"
        Dest = Join-Path $HOME ".gitconfig.d\aliases.gitconfig"
    }
    [pscustomobject]@{
        Src  = "ai\claude\settings.json"
        Dest = Join-Path $HOME ".claude\settings.json"
    }
)

$countOk     = 0
$countSkip   = 0
$countBackup = 0

foreach ($link in $links) {
    $src  = Join-Path $DOTFILES_DIR $link.Src
    $dest = $link.Dest

    # ソースファイルが存在しない場合はスキップ
    if (-not (Test-Path $src)) {
        Write-Host "  SKIP    $src (ファイルが存在しません)"
        $countSkip++
        continue
    }

    # リンク先のディレクトリを作成
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # リンク先がシンボリックリンクの場合: 上書き
    $item = Get-Item $dest -ErrorAction SilentlyContinue -Force
    if ($item -and $item.LinkType -eq 'SymbolicLink') {
        Remove-Item $dest -Force
        New-Item -ItemType SymbolicLink -Path $dest -Target $src | Out-Null
        Write-Host "  LINK    $dest -> $src"
        $countOk++

    # リンク先が実ファイルの場合: バックアップして置換
    } elseif (Test-Path $dest) {
        if (-not (Test-Path $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }
        Move-Item $dest $backupDir
        New-Item -ItemType SymbolicLink -Path $dest -Target $src | Out-Null
        Write-Host "  BACKUP  $dest -> $backupDir\$(Split-Path $dest -Leaf)"
        Write-Host "  LINK    $dest -> $src"
        $countBackup++
        $countOk++

    # リンク先が存在しない場合: 新規作成
    } else {
        New-Item -ItemType SymbolicLink -Path $dest -Target $src | Out-Null
        Write-Host "  LINK    $dest -> $src"
        $countOk++
    }
}

Write-Host ""
Write-Host "完了: リンク=$countOk  スキップ=$countSkip  バックアップ=$countBackup"
if ($countBackup -gt 0) {
    Write-Host "バックアップ先: $backupDir"
}
