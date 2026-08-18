#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptItem = Get-Item -LiteralPath $PSCommandPath -Force
while ($scriptItem.LinkType -eq 'SymbolicLink') {
    $target = [string]$scriptItem.Target
    if (-not [System.IO.Path]::IsPathRooted($target)) {
        $target = Join-Path $scriptItem.DirectoryName $target
    }
    $scriptItem = Get-Item -LiteralPath $target -Force
}
$dotfilesDir = Split-Path -Parent $scriptItem.DirectoryName
$privateDir = "$dotfilesDir-private"

function Show-Usage {
    @'
Usage:
  dots status [-NoFetch]
  dots update
  dots help

Windowsでは status / update を利用できます。
'@
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE"
    }
}

function Show-RepositoryStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [bool]$Fetch
    )

    $needsAttention = $false
    Write-Host $Name
    Write-Host "  path: $Path"

    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git') -PathType Container)) {
        Write-Host '  status: not found'
        Write-Host
        return $true
    }

    if ($Fetch) {
        & git -C $Path fetch --quiet --prune
        if ($LASTEXITCODE -ne 0) {
            Write-Host '  fetch: failed (cached remote state follows)'
            $needsAttention = $true
        }
    }

    $branch = (& git -C $Path branch --show-current 2>$null)
    if (-not $branch) {
        $branch = '(detached HEAD)'
    }
    Write-Host "  branch: $branch"

    $changes = @(& git -C $Path status --short)
    if ($LASTEXITCODE -ne 0) {
        throw "git status failed for $Path"
    }
    if ($changes.Count -gt 0) {
        Write-Host '  working tree:'
        $changes | ForEach-Object { Write-Host "    $_" }
        $needsAttention = $true
    } else {
        Write-Host '  working tree: clean'
    }

    $upstream = (& git -C $Path rev-parse --abbrev-ref '@{upstream}' 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $upstream) {
        Write-Host '  remote: no upstream'
        Write-Host
        return $true
    }

    $counts = ((& git -C $Path rev-list --left-right --count "HEAD...$upstream") -split '\s+')
    if ($LASTEXITCODE -ne 0 -or $counts.Count -ne 2) {
        throw "git rev-list failed for $Path"
    }
    $ahead = [int]$counts[0]
    $behind = [int]$counts[1]

    if ($ahead -eq 0 -and $behind -eq 0) {
        Write-Host "  remote: up to date ($upstream)"
    } elseif ($ahead -eq 0) {
        Write-Host "  remote: $behind commit(s) to pull ($upstream)"
        $needsAttention = $true
    } elseif ($behind -eq 0) {
        Write-Host "  remote: $ahead commit(s) to push ($upstream)"
        $needsAttention = $true
    } else {
        Write-Host "  remote: diverged; $ahead to push, $behind to pull ($upstream)"
        $needsAttention = $true
    }
    Write-Host

    return $needsAttention
}

$commandName = if ($args.Count -gt 0) { $args[0] } else { 'help' }
$commandArgs = if ($args.Count -gt 1) { @($args[1..($args.Count - 1)]) } else { @() }

switch ($commandName) {
    'status' {
        $fetch = $true
        foreach ($argument in $commandArgs) {
            switch ($argument) {
                '-NoFetch' { $fetch = $false }
                '--no-fetch' { $fetch = $false }
                default { throw "unknown status option: $argument" }
            }
        }

        $needsAttention = Show-RepositoryStatus -Name 'dotfiles' -Path $dotfilesDir -Fetch $fetch
        if (Show-RepositoryStatus -Name 'dotfiles-private' -Path $privateDir -Fetch $fetch) {
            $needsAttention = $true
        }
        if ($needsAttention) {
            exit 1
        }
    }
    'update' {
        if ($commandArgs.Count -gt 0) {
            throw "unexpected argument: $($commandArgs[0])"
        }
        Invoke-NativeCommand pwsh -NoLogo -NoProfile -File "$dotfilesDir\scripts\update-dotfiles.ps1"
        Invoke-NativeCommand gsudo pwsh -NoLogo -NonInteractive -File "$dotfilesDir\scripts\install.ps1"
        Invoke-NativeCommand pwsh -NoLogo -NoProfile -File "$dotfilesDir\scripts\setup-zellij.ps1"
        Invoke-NativeCommand gsudo pwsh -NoLogo -NonInteractive -File "$dotfilesDir\scripts\update-windows.ps1"
    }
    { $_ -in @('help', '-h', '--help') } {
        Show-Usage
    }
    default {
        throw "unknown command on Windows: $commandName"
    }
}
