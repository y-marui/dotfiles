#!/usr/bin/env pwsh
# diff.ps1
# ~/.claude/plugins/{installed_plugins,known_marketplaces}.json（システム実態）と
# plugins.json（管理ファイル）の差分を表示する（diff.sh の PowerShell 版）。
#
# `claude plugin list --json` は CLI 起動に時間がかかるため、実体である JSON ファイルを
# 直接読む。これらは非公開の内部ファイルなので、Claude Code のバージョンアップで形式が
# 変わる可能性がある点は留意する。
#
# 使い方:
#   pwsh ai/claude/plugin/diff.ps1            # 差分を詳細表示
#   pwsh ai/claude/plugin/diff.ps1 -Summary   # 1行サマリーのみ出力
#
# 実体ファイルまたは plugins.json が見つからない場合は終了コード 1 で何も出力しない

param([switch]$Summary)

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

$pluginsFile = Join-Path $DotfilesDir 'ai\claude\plugin\plugins.json'
$installedJson = Join-Path $HOME '.claude\plugins\installed_plugins.json'
$marketplacesJson = Join-Path $HOME '.claude\plugins\known_marketplaces.json'

foreach ($path in @($pluginsFile, $installedJson, $marketplacesJson)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { exit 1 }
}

$declared = Read-JsonFile -Path $pluginsFile
$installed = Read-JsonFile -Path $installedJson
$marketplaces = Read-JsonFile -Path $marketplacesJson

$declaredMkt = [string[]]@(@(Get-Value $declared 'marketplaces' @()) | ForEach-Object { $_['name'] })
$actualMkt = [string[]]@($marketplaces.Keys)
$declaredPlugins = [string[]]@(Get-Value $declared 'plugins' @())
$actualPlugins = [string[]]@((Get-Value $installed 'plugins' @{}).Keys)

$onlyInActual = @(Get-SetDifference -A $actualMkt -B $declaredMkt) + @(Get-SetDifference -A $actualPlugins -B $declaredPlugins)
$onlyInFiles = @(Get-SetDifference -A $declaredMkt -B $actualMkt) + @(Get-SetDifference -A $declaredPlugins -B $actualPlugins)

if ($Summary) {
    $parts = @()
    if ($onlyInActual.Count -gt 0) { $parts += "+$($onlyInActual.Count) actual のみ" }
    if ($onlyInFiles.Count -gt 0) { $parts += "-$($onlyInFiles.Count) files のみ" }
    if ($parts.Count -gt 0) { Write-Host ($parts -join ' / ') }
    exit 0
}

if ($onlyInActual.Count -eq 0 -and $onlyInFiles.Count -eq 0) {
    Write-Host 'No diff: 実際のインストール状態と plugins.json は一致しています。'
    exit 0
}

if ($onlyInActual.Count -gt 0) {
    Write-Host 'インストール済みだが plugins.json 未記載 (+actual のみ):'
    foreach ($name in $onlyInActual) { Write-Host "  [+actual]  $name" }
    Write-Host ''
}
if ($onlyInFiles.Count -gt 0) {
    Write-Host 'plugins.json にあるが未インストール (-files のみ):'
    foreach ($name in $onlyInFiles) { Write-Host "  [-files]  $name" }
}

exit 1
