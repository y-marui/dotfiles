#!/usr/bin/env pwsh
# doc-lint: 作業ツリーの Markdown のサイズ・frontmatter を検査して表示する（Windows / PowerShell 版）
#
# bin/unix/doc-lint の PowerShell への移植。挙動は同じに保つ。
#
# 使い方:
#   doc-lint            カレントのリポジトリの全 Markdown を検査する
#
# オプション:
#   -h, --help          ヘルプを表示

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($args.Count -gt 0 -and $args[0] -in @('-h', '--help')) {
    Get-Content -LiteralPath $PSCommandPath | Select-Object -Skip 1 -First 11 | ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

# $PSScriptRoot がディレクトリシンボリックリンクの場合は実体を解決する（dots.ps1 と同じ）
$scriptDirItem = Get-Item -LiteralPath $PSScriptRoot -Force
if ($scriptDirItem.LinkType -eq 'SymbolicLink') {
    $target = [string]$scriptDirItem.Target
    if (-not [System.IO.Path]::IsPathRooted($target)) {
        $target = Join-Path (Split-Path $scriptDirItem.FullName -Parent) $target
    }
    $realScriptDir = $target
} else {
    $realScriptDir = $scriptDirItem.FullName
}
$dotfilesDir = Split-Path -Parent (Split-Path -Parent $realScriptDir)
$tool = Join-Path $dotfilesDir 'scripts/doc-lint.py'

foreach ($py in @('python3', 'python', 'py')) {
    if (-not (Get-Command $py -ErrorAction SilentlyContinue)) { continue }
    & $py -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>$null
    if ($LASTEXITCODE -eq 0) {
        & $py $tool --all
        exit $LASTEXITCODE
    }
}
[Console]::Error.WriteLine('エラー: Python 3.11 以上が必要です。')
exit 1
