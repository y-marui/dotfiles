#!/usr/bin/env pwsh
# diff.ps1
# ~/.claude.json と既知 project の .mcp.json にある MCP 実態を検査する（diff.sh の PowerShell 版）。
#
# 動作:
#   [+actual] name  → user scope に登録済みだが servers.json 未記載
#   [+local] name   → local scope に登録済み（~/.claude.json の projects 配下）
#   [+project] name → project scope に登録済み（.mcp.json）
#   [-files]  name  → servers.json にあるがシステム未登録（dots claude apply --mcp-only で追加できる）
#
# 使い方:
#   pwsh ai/claude/mcp/diff.ps1            # 差分を詳細表示
#   pwsh ai/claude/mcp/diff.ps1 -Summary   # 1行サマリーのみ出力
#
# ~/.claude.json または servers.json が見つからない場合は終了コード 1 で何も出力しない
# （ファイルの権限チェック ~permission は Windows に chmod 相当がないため行わない）。

param([switch]$Summary)

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

$serversFile = Join-Path $DotfilesDir 'ai\claude\mcp\servers.json'
$claudeJson = Join-Path $HOME '.claude.json'

if (-not (Test-Path -LiteralPath $claudeJson) -or -not (Test-Path -LiteralPath $serversFile)) {
    exit 1
}

$declared = @{}
foreach ($entry in @(Read-JsonFile -Path $serversFile)) { $declared[$entry['name']] = $entry }
$claudeConfig = Read-JsonFile -Path $claudeJson
$actualConfig = Get-Value $claudeConfig 'mcpServers' @{}
$actual = [string[]]@($actualConfig.Keys)
$declaredNames = [string[]]@($declared.Keys)

function Get-TransportName {
    param($Config)

    if ((Get-Value $Config 'type' $null) -in @('http', 'sse', 'ws') -or $Config.Contains('url')) {
        return (Get-Value $Config 'type' 'http')
    }
    return 'stdio'
}

$scopedActual = [System.Collections.Generic.List[object]]::new()
$projects = Get-Value $claudeConfig 'projects' @{}
foreach ($projectPath in $projects.Keys) {
    $localServers = Get-Value $projects[$projectPath] 'mcpServers' @{}
    foreach ($name in $localServers.Keys) {
        $scopedActual.Add([pscustomobject]@{
                Scope = 'local'; Path = $projectPath; Name = $name
                Transport = (Get-TransportName -Config $localServers[$name])
            })
    }

    try {
        $projectMcp = Read-JsonFile -Path (Join-Path $projectPath '.mcp.json')
    } catch {
        continue
    }
    $projectServers = Get-Value $projectMcp 'mcpServers' @{}
    foreach ($name in $projectServers.Keys) {
        $scopedActual.Add([pscustomobject]@{
                Scope = 'project'; Path = $projectPath; Name = $name
                Transport = (Get-TransportName -Config $projectServers[$name])
            })
    }
}

$extraActual = Get-SetDifference -A $actual -B $declaredNames
$appActual = @($extraActual | Where-Object { Test-LoopbackUrl (Get-Value $actualConfig[$_] 'url' '') })
$onlyInActual = @(Get-SetDifference -A $extraActual -B $appActual)
$onlyInFiles = @(Get-SetDifference -A $declaredNames -B $actual)

function Test-ConfigMatches {
    param($Wanted, $Current)

    if ($Wanted['type'] -eq 'stdio') {
        return ((Get-Value $Current 'type' 'stdio') -eq 'stdio') -and
        ((Get-Value $Current 'command' $null) -ceq $Wanted['command']) -and
        (Test-SameList (Get-Value $Current 'args' @()) (Get-Value $Wanted 'args' @()))
    }
    $wantedHeaderNames = [string[]]@((Get-Value $Wanted 'headers' @{}).Keys)
    $currentHeaderNames = [string[]]@((Get-Value $Current 'headers' @{}).Keys)
    return ((Get-Value $Current 'type' $null) -in @('http', 'sse')) -and
    ((Get-Value $Current 'url' $null) -ceq $Wanted['url']) -and
    (@(Get-SetDifference -A $wantedHeaderNames -B $currentHeaderNames).Count -eq 0) -and
    (@(Get-SetDifference -A $currentHeaderNames -B $wantedHeaderNames).Count -eq 0)
}

$mismatched = @(Get-SetIntersection -A $declaredNames -B $actual |
        Where-Object { -not (Test-ConfigMatches -Wanted $declared[$_] -Current $actualConfig[$_]) })

$found = ($onlyInActual.Count -gt 0) -or ($onlyInFiles.Count -gt 0) -or ($mismatched.Count -gt 0)

if ($Summary) {
    $parts = @()
    if ($onlyInActual.Count -gt 0) { $parts += "+$($onlyInActual.Count) actual のみ" }
    if ($onlyInFiles.Count -gt 0) { $parts += "-$($onlyInFiles.Count) files のみ" }
    if ($mismatched.Count -gt 0) { $parts += "~$($mismatched.Count) config 不一致" }
    if ($parts.Count -gt 0) { Write-Host ($parts -join ' / ') }
    exit 0
}

if (-not $found) {
    Write-Host 'No diff: 実際の登録状態と servers.json は一致しています。'
} else {
    if ($onlyInActual.Count -gt 0) {
        Write-Host 'user scope に直接登録済みだが servers.json 未記載 (+actual のみ):'
        foreach ($name in $onlyInActual) { Write-Host "  [+actual]  $name" }
        Write-Host ''
    }
    if ($onlyInFiles.Count -gt 0) {
        Write-Host 'servers.json にあるがシステム未登録 (-files のみ):'
        foreach ($name in $onlyInFiles) { Write-Host "  [-files]  $name" }
        Write-Host ''
    }
    if ($mismatched.Count -gt 0) {
        Write-Host '同名だが設定が不一致 (~config):'
        foreach ($name in $mismatched) { Write-Host "  [~config]  $name" }
        Write-Host ''
    }
}

if ($appActual.Count -gt 0) {
    Write-Host 'IDE/app が提供する loopback MCP (app 管理):'
    foreach ($name in $appActual) { Write-Host "  [app]      $name" }
    Write-Host ''
}
$localActual = @($scopedActual | Where-Object { $_.Scope -eq 'local' } | Sort-Object Path, Name)
$projectActual = @($scopedActual | Where-Object { $_.Scope -eq 'project' } | Sort-Object Path, Name)
if ($localActual.Count -gt 0) {
    Write-Host 'Claude Code local scope の MCP (端末・リポジトリ別、dotfiles 管理外):'
    foreach ($item in $localActual) { Write-Host "  [+local]  $($item.Name) ($($item.Transport)) @ $($item.Path)" }
    Write-Host ''
}
if ($projectActual.Count -gt 0) {
    Write-Host 'Claude Code project scope の MCP (.mcp.json、リポジトリ管理):'
    foreach ($item in $projectActual) { Write-Host "  [+project]  $($item.Name) ($($item.Transport)) @ $($item.Path)" }
    Write-Host ''
}

Exit-Diff -Found $found
