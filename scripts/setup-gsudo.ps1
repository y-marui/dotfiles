#!/usr/bin/env pwsh
# Configure gsudo for Windows remote administration.
# Run this once from an interactive desktop session so the UAC prompt is visible.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cacheDuration = '00:30:00'
$gsudo = Get-Command gsudo -CommandType Application -ErrorAction SilentlyContinue
if (-not $gsudo) {
    throw @'
gsudo が見つかりません。先に以下を実行し、新しい PowerShell を開いてください:
  winget install gerardog.gsudo
'@
}

& $gsudo.Source config CacheMode Auto
if ($LASTEXITCODE -ne 0) {
    throw "gsudo CacheMode の設定に失敗しました (exit code: $LASTEXITCODE)"
}

& $gsudo.Source config CacheDuration $cacheDuration
if ($LASTEXITCODE -ne 0) {
    throw "gsudo CacheDuration の設定に失敗しました (exit code: $LASTEXITCODE)"
}

Write-Host "  CONFIG  gsudo CacheMode=Auto CacheDuration=$cacheDuration"
Write-Host '最初の昇格は、UACを表示できるMRDなどの対話セッションで実行してください。'
