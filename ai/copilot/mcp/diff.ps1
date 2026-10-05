#!/usr/bin/env pwsh
# Copilot CLI の user scope MCP と servers.json の差分を表示する（diff.sh の PowerShell 版）。
#
# 使い方:
#   pwsh ai/copilot/mcp/diff.ps1            # 差分を詳細表示
#   pwsh ai/copilot/mcp/diff.ps1 -Summary   # 1行サマリーのみ出力

param([switch]$Summary)

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

$serversFile = Join-Path $DotfilesDir 'ai\copilot\mcp\servers.json'

if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) { exit 1 }

$declared = @{}
foreach ($entry in @(Read-JsonFile -Path $serversFile)) { $declared[$entry['name']] = $entry }
$allActual = Get-Value (Invoke-NativeCapture -Command 'copilot' -Arguments @('mcp', 'list', '--json') | ConvertFrom-Json -AsHashtable) 'mcpServers' @{}

$actual = @{}
$otherSources = [System.Collections.Generic.List[object]]::new()
foreach ($name in (Sort-Ordinal -Items ([string[]]@($allActual.Keys)))) {
    $entry = $allActual[$name]
    if ((Get-Value $entry 'source' $null) -eq 'user') {
        $actual[$name] = $entry
    } else {
        $otherSources.Add([pscustomobject]@{ Name = $name; Source = (Get-Value $entry 'source' 'unknown') })
    }
}

function Test-ConfigMatches {
    param($Wanted, $Current)

    return ((Get-Value $Current 'type' $null) -ceq $Wanted['type']) -and
    ((Get-Value $Current 'command' $null) -ceq (Get-Value $Wanted 'command' $null)) -and
    (Test-SameList (Get-Value $Current 'args' @()) (Get-Value $Wanted 'args' @())) -and
    (Test-SameList (Get-Value $Current 'tools' @('*')) (Get-Value $Wanted 'tools' @('*')))
}

$declaredNames = [string[]]@($declared.Keys)
$actualNames = [string[]]@($actual.Keys)
$onlyActual = @(Get-SetDifference -A $actualNames -B $declaredNames)
$onlyFiles = @(Get-SetDifference -A $declaredNames -B $actualNames)
$mismatched = @(Get-SetIntersection -A $declaredNames -B $actualNames |
        Where-Object { -not (Test-ConfigMatches -Wanted $declared[$_] -Current $actual[$_]) })
$found = ($onlyActual.Count -gt 0) -or ($onlyFiles.Count -gt 0) -or ($mismatched.Count -gt 0)

if ($Summary) {
    $parts = @()
    if ($onlyActual.Count -gt 0) { $parts += "+$($onlyActual.Count) actual のみ" }
    if ($onlyFiles.Count -gt 0) { $parts += "-$($onlyFiles.Count) files のみ" }
    if ($mismatched.Count -gt 0) { $parts += "~$($mismatched.Count) config 不一致" }
    if ($parts.Count -gt 0) { Write-Host ($parts -join ' / ') }
    Exit-Diff -Found $found
}

if (-not $found) {
    Write-Host 'No diff: Copilot CLI の user scope MCP と servers.json は一致しています。'
} else {
    if ($onlyActual.Count -gt 0) {
        Write-Host 'user scope に直接登録済みだが servers.json 未記載 (+actual のみ):'
        foreach ($name in $onlyActual) { Write-Host "  [+actual]  $name" }
        Write-Host ''
    }
    if ($onlyFiles.Count -gt 0) {
        Write-Host 'servers.json にあるが user scope 未登録 (-files のみ):'
        foreach ($name in $onlyFiles) { Write-Host "  [-files]   $name" }
        Write-Host ''
    }
    if ($mismatched.Count -gt 0) {
        Write-Host '同名だが設定が不一致 (~config):'
        foreach ($name in $mismatched) { Write-Host "  [~config]  $name" }
        Write-Host ''
    }
}

if ($otherSources.Count -gt 0) {
    Write-Host 'workspace / plugin / builtin MCP (Copilot CLI 管理):'
    foreach ($item in $otherSources) { Write-Host "  [$($item.Source)]  $($item.Name)" }
}

Exit-Diff -Found $found
