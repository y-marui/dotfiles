#!/usr/bin/env pwsh
# Codex app-server が返す local / remote plugin 実態を管理する（diff.sh の PowerShell 版）。
#
# 使い方:
#   pwsh ai/codex/plugin/diff.ps1             # 差分を詳細表示
#   pwsh ai/codex/plugin/diff.ps1 -Summary    # 1行サマリーのみ出力
#   pwsh ai/codex/plugin/diff.ps1 -Action apply   # 未導入の plugin を追加（apply.ps1 から呼ぶ）
#   pwsh ai/codex/plugin/diff.ps1 -Action prune   # 未宣言の plugin を削除（prune.ps1 から呼ぶ）

param(
    [ValidateSet('diff', 'apply', 'prune')]
    [string]$Action = 'diff',
    [switch]$Summary
)

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

$pluginsFile = Join-Path $DotfilesDir 'ai\codex\plugin\plugins.json'

# `codex app-server` と標準入出力で JSON-RPC（1行1メッセージ）をやり取りする。
class AppServer {
    [System.Diagnostics.Process]$Process
    [int]$NextId = 0

    AppServer() {
        $info = [System.Diagnostics.ProcessStartInfo]::new()
        # Windows の codex は npm の .cmd シムのことがあるため、解決済みのパスで起動する。
        $info.FileName = (Get-Command codex -CommandType Application | Select-Object -First 1).Source
        $info.ArgumentList.Add('app-server')
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
        $info.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $info.UseShellExecute = $false
        $this.Process = [System.Diagnostics.Process]::Start($info)
        $this.Request('initialize', @{
                clientInfo = @{
                    name = 'dots_plugin_manager'
                    title = 'dots plugin manager'
                    version = '1.0.0'
                }
                capabilities = @{ experimentalApi = $true }
            }) | Out-Null
        $this.Notify('initialized', @{})
    }

    [void] Send([hashtable]$Message) {
        $this.Process.StandardInput.WriteLine(($Message | ConvertTo-Json -Depth 20 -Compress))
        $this.Process.StandardInput.Flush()
    }

    [hashtable] Read() {
        $line = $this.Process.StandardOutput.ReadLine()
        if ($null -ne $line) {
            return ($line | ConvertFrom-Json -AsHashtable)
        }
        $stderr = $this.Process.StandardError.ReadToEnd().Trim()
        $detail = if ($stderr) { ": $stderr" } else { '' }
        throw "codex app-server が応答せず終了しました$detail"
    }

    [object] Request([string]$Method, [hashtable]$Params) {
        $requestId = $this.NextId
        $this.NextId++
        $this.Send(@{ method = $Method; id = $requestId; params = $Params })
        while ($true) {
            $message = $this.Read()
            if ($message.ContainsKey('id') -and $message['id'] -eq $requestId) {
                if ($message.ContainsKey('error')) {
                    throw "codex app-server $Method failed: $($message['error'] | ConvertTo-Json -Compress)"
                }
                return $message['result']
            }
            if ($message.ContainsKey('id') -and $message.ContainsKey('method')) {
                throw "codex app-server $Method requires interactive handling: $($message['method'])"
            }
        }
        return $null
    }

    [void] Notify([string]$Method, [hashtable]$Params) {
        $this.Send(@{ method = $Method; params = $Params })
    }

    [void] Close() {
        if ($this.Process.HasExited) { return }
        $this.Process.StandardInput.Close()
        if (-not $this.Process.WaitForExit(5000)) {
            $this.Process.Kill($true)
            $this.Process.WaitForExit()
        }
    }
}

function Get-AvailablePlugins {
    param([AppServer]$Server)

    $result = $Server.Request('plugin/list', @{ forceRefetch = $false })
    $errors = @(Get-Value $result 'marketplaceLoadErrors' @())
    if ($errors.Count -gt 0) {
        $details = ($errors | ForEach-Object { Get-Value $_ 'message' ([string]$_) }) -join '; '
        throw "plugin marketplace の読み込みに失敗しました: $details"
    }

    $plugins = @{}
    foreach ($marketplace in @(Get-Value $result 'marketplaces' @())) {
        foreach ($plugin in @(Get-Value $marketplace 'plugins' @())) {
            $plugins[$plugin['id']] = [pscustomobject]@{ Marketplace = $marketplace; Plugin = $plugin }
        }
    }
    return $plugins
}

function Test-RemotePlugin {
    param($Plugin)
    return (Get-Value (Get-Value $Plugin 'source' @{}) 'type' $null) -eq 'remote'
}

function Install-Plugin {
    param([AppServer]$Server, [string]$PluginId, $Entry)

    if (Test-RemotePlugin $Entry.Plugin) {
        $Server.Request('plugin/install', @{
                pluginName = $Entry.Plugin['name']
                remoteMarketplaceName = $Entry.Marketplace['name']
            }) | Out-Null
        return
    }
    Invoke-NativeVisible -Command 'codex' -Arguments @('plugin', 'add', $PluginId)
}

function Uninstall-Plugin {
    param([AppServer]$Server, [string]$PluginId, $Entry)

    if (Test-RemotePlugin $Entry.Plugin) {
        $Server.Request('plugin/uninstall', @{ pluginId = $PluginId }) | Out-Null
        return
    }
    Invoke-NativeVisible -Command 'codex' -Arguments @('plugin', 'remove', $PluginId)
}

# Codex 自身が既定で入れる remote plugin は宣言の対象外にする。
function Test-CodexManaged {
    param($Plugin)

    $source = Get-Value $Plugin 'source' @{}
    $sourceType = Get-Value $source 'type' (Get-Value $source 'source' $null)
    return $sourceType -eq 'remote' -and (Get-Value $Plugin 'installPolicy' $null) -eq 'INSTALLED_BY_DEFAULT'
}

$declared = [string[]]@(Get-Value (Read-JsonFile -Path $pluginsFile) 'plugins' @())

$server = [AppServer]::new()
try {
    $available = Get-AvailablePlugins -Server $server
    $codexManaged = [string[]]@($available.Keys | Where-Object { Test-CodexManaged $available[$_].Plugin })
    $declared = [string[]]@(Get-SetDifference -A $declared -B $codexManaged)
    $actual = [string[]]@($available.Keys | Where-Object {
            (Get-Value $available[$_].Plugin 'installed' $false) -and $_ -notin $codexManaged
        })
    $onlyActual = @(Get-SetDifference -A $actual -B $declared)
    $onlyFiles = @(Get-SetDifference -A $declared -B $actual)

    if ($Action -eq 'apply') {
        if ($onlyFiles.Count -eq 0) {
            Write-Host '  (already up to date)'
            exit 0
        }
        foreach ($pluginId in $onlyFiles) {
            if (-not $available.ContainsKey($pluginId)) {
                throw "plugin '$pluginId' は利用可能な marketplace にありません"
            }
            Write-Host "  install  $pluginId"
            Install-Plugin -Server $server -PluginId $pluginId -Entry $available[$pluginId]
        }
        exit 0
    }

    if ($Action -eq 'prune') {
        if ($onlyActual.Count -eq 0) {
            Write-Host '  (nothing to prune)'
            exit 0
        }
        foreach ($pluginId in $onlyActual) {
            Write-Host "  remove  $pluginId"
            Uninstall-Plugin -Server $server -PluginId $pluginId -Entry $available[$pluginId]
        }
        exit 0
    }

    $found = ($onlyActual.Count -gt 0) -or ($onlyFiles.Count -gt 0)

    if ($Summary) {
        $parts = @()
        if ($onlyActual.Count -gt 0) { $parts += "+$($onlyActual.Count) actual のみ" }
        if ($onlyFiles.Count -gt 0) { $parts += "-$($onlyFiles.Count) files のみ" }
        if ($parts.Count -gt 0) { Write-Host ($parts -join ' / ') }
        Exit-Diff -Found $found
    }

    if (-not $found) {
        Write-Host 'No diff: 実際の plugin インストール状態と plugins.json は一致しています。'
        exit 0
    }

    if ($onlyActual.Count -gt 0) {
        Write-Host 'インストール済みだが plugins.json 未記載 (+actual のみ。local/remote source を含む):'
        foreach ($name in $onlyActual) { Write-Host "  [+actual]  $name" }
        Write-Host ''
    }
    if ($onlyFiles.Count -gt 0) {
        Write-Host 'plugins.json にあるが未インストール (-files のみ):'
        foreach ($name in $onlyFiles) { Write-Host "  [-files]   $name" }
    }
    exit 1
} finally {
    $server.Close()
}
