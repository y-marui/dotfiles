#!/usr/bin/env pwsh
# Codex CLI が返す統合済みの MCP 実態と servers.json の差分を表示する（diff.sh の PowerShell 版）。
#
# 使い方:
#   pwsh ai/codex/mcp/diff.ps1            # 差分を詳細表示
#   pwsh ai/codex/mcp/diff.ps1 -Summary   # 1行サマリーのみ出力

param([switch]$Summary)

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

$serversFile = Join-Path $DotfilesDir 'ai\codex\mcp\servers.json'

$declared = @{}
foreach ($entry in @(Read-JsonFile -Path $serversFile)) { $declared[$entry['name']] = $entry }
$actual = @{}
foreach ($entry in @(Invoke-NativeCapture -Command 'codex' -Arguments @('mcp', 'list', '--json') | ConvertFrom-Json -AsHashtable)) {
    $actual[$entry['name']] = $entry
}
$pluginEntries = @(Get-Value (Invoke-NativeCapture -Command 'codex' -Arguments @('plugin', 'list', '--json') | ConvertFrom-Json -AsHashtable) 'installed' @())

$pluginOwned = @{}
foreach ($plugin in $pluginEntries) {
    if (-not (Get-Value $plugin 'installed' $true)) { continue }
    $sourcePath = Get-Value (Get-Value $plugin 'source' @{}) 'path' $null
    if (-not $sourcePath) { continue }
    try {
        $manifest = Read-JsonFile -Path (Join-Path $sourcePath '.mcp.json')
    } catch {
        continue
    }
    foreach ($name in (Get-Value $manifest 'mcpServers' @{}).Keys) {
        $pluginOwned[$name] = $plugin['pluginId']
    }
}

function Get-Transport {
    param($Entry)
    return (Get-Value $Entry 'transport' @{})
}

function Test-AppOwned {
    param($Entry)
    return ([string](Get-Value (Get-Transport $Entry) 'command' '')).StartsWith('/Applications/ChatGPT.app/')
}

function Test-Loopback {
    param($Entry)
    return Test-LoopbackUrl (Get-Value (Get-Transport $Entry) 'url' '')
}

$declaredNames = [string[]]@($declared.Keys)
$actualNames = [string[]]@($actual.Keys)
$extraNames = Get-SetDifference -A $actualNames -B $declaredNames
$pluginActual = @($extraNames | Where-Object { $pluginOwned.ContainsKey($_) })
$appActual = @($extraNames | Where-Object { -not $pluginOwned.ContainsKey($_) -and (Test-AppOwned $actual[$_]) })
$loopbackActual = @($extraNames | Where-Object {
        -not $pluginOwned.ContainsKey($_) -and $_ -notin $appActual -and (Test-Loopback $actual[$_])
    })
$onlyActual = @(Get-SetDifference -A $extraNames -B (@($pluginActual) + @($appActual) + @($loopbackActual)))
$onlyFiles = @(Get-SetDifference -A $declaredNames -B $actualNames)

function Test-ConfigMatches {
    param($Wanted, $Current)

    $transport = Get-Transport $Current
    if ($Wanted['type'] -eq 'stdio') {
        return ((Get-Value $transport 'type' $null) -eq 'stdio') -and
        ((Get-Value $transport 'command' $null) -ceq $Wanted['command']) -and
        (Test-SameList (Get-Value $transport 'args' @()) (Get-Value $Wanted 'args' @()))
    }
    $wantedNames = [string[]]@((Get-Value $Wanted 'headers' @{}).Keys)
    $currentNames = [string[]]@((Get-Value $transport 'http_headers' @{}).Keys)
    return ((Get-Value $transport 'type' $null) -in @('http', 'streamable_http')) -and
    ((Get-Value $transport 'url' $null) -ceq $Wanted['url']) -and
    (-not (Get-Value $transport 'bearer_token_env_var' $null)) -and
    (@(Get-SetDifference -A $wantedNames -B $currentNames).Count -eq 0)
}

$mismatched = @(Get-SetIntersection -A $declaredNames -B $actualNames |
        Where-Object { -not (Test-ConfigMatches -Wanted $declared[$_] -Current $actual[$_]) })

$found = ($onlyActual.Count -gt 0) -or ($onlyFiles.Count -gt 0) -or ($mismatched.Count -gt 0)

if ($Summary) {
    $parts = @()
    if ($onlyActual.Count -gt 0) { $parts += "+$($onlyActual.Count) actual のみ" }
    if ($onlyFiles.Count -gt 0) { $parts += "-$($onlyFiles.Count) files のみ" }
    if ($mismatched.Count -gt 0) { $parts += "~$($mismatched.Count) config 不一致" }
    if ($parts.Count -gt 0) { Write-Host ($parts -join ' / ') }
    Exit-Diff -Found ($parts.Count -gt 0)
}

if (-not $found) {
    Write-Host 'No diff: 実際の MCP 登録状態と servers.json は一致しています。'
} else {
    if ($onlyActual.Count -gt 0) {
        Write-Host '直接登録済みだが servers.json 未記載 (+actual のみ):'
        foreach ($name in $onlyActual) {
            $type = Get-Value (Get-Transport $actual[$name]) 'type' 'unknown'
            Write-Host "  [+actual]  $name ($type)"
        }
        Write-Host ''
    }
    if ($onlyFiles.Count -gt 0) {
        Write-Host 'servers.json にあるが未登録 (-files のみ):'
        foreach ($name in $onlyFiles) { Write-Host "  [-files]   $name" }
        Write-Host ''
    }
    if ($mismatched.Count -gt 0) {
        Write-Host '同名だが設定が不一致 (~config):'
        foreach ($name in $mismatched) { Write-Host "  [~config]  $name" }
        Write-Host ''
    }
}

if ($pluginActual.Count -gt 0) {
    Write-Host 'plugin が提供する MCP (plugin 管理):'
    foreach ($name in $pluginActual) { Write-Host "  [plugin]   $name <- $($pluginOwned[$name])" }
    Write-Host ''
}
if ($appActual.Count -gt 0) {
    Write-Host 'ChatGPT/Codex アプリが提供する内部 MCP (app 管理):'
    foreach ($name in $appActual) { Write-Host "  [app]      $name" }
    Write-Host ''
}
if ($loopbackActual.Count -gt 0) {
    Write-Host 'IDE/app が提供する loopback MCP (app 管理):'
    foreach ($name in $loopbackActual) { Write-Host "  [app]      $name" }
}

Exit-Diff -Found $found
