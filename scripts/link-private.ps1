#!/usr/bin/env pwsh
# scripts/link-private.ps1
# dotfiles-private が存在する場合のみ setup.ps1 を実行してシンボリックリンクを作成する。
# Makefile の install-macos/install-rpi 内にある
# `bash $(PRIVATE_DIR)/setup.sh` 呼び出しに相当する Windows 版。
# dotfiles-private の取得自体（clone/pull）は scripts/setup-private.sh（make private）が担う。

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dotfilesDir = Split-Path -Parent $PSScriptRoot
$privateDir = "$dotfilesDir-private"
$setupScript = Join-Path $privateDir "setup.ps1"

if (Test-Path -LiteralPath $setupScript) {
    & $setupScript
} else {
    Write-Host "  SKIP    dotfiles-private (make private でセットアップしてください)"
}
