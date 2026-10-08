#!/usr/bin/env pwsh
# obsidian-project-home: Git repositoryに対応するObsidian Project Homeを一意に解決する
#
# Usage:
#   obsidian-project-home [--repo DIR] [--vault DIR]
#   obsidian-project-home check [--vault DIR]
#
# The command compares the current repository's origin with the `repositories`
# frontmatter list in normal-vault `projects/**/*.md` files. GitHub HTTPS, SSH,
# and github-public:/github-private: origin forms normalize to
# https://github.com/owner/repository. It never searches note bodies or private/
# paths. Exit status: 0 unique (or check passed), 3 no mapping, 4 duplicates,
# 5 invalid configuration or frontmatter.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Stderr([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

function Show-Help {
    $lines = @(Get-Content -LiteralPath $PSCommandPath)
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line -eq '') { break }
        Write-Output ($line -replace '^#\s?', '')
    }
}

function Fail([string]$Message, [int]$Code = 5) {
    Write-Stderr "error: $Message"
    exit $Code
}

function Resolve-NormalizedRepository([string]$Value) {
    $value = $Value.Trim().TrimEnd('/')
    if ($value.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
        $value = $value.Substring(0, $value.Length - 4)
    }

    $patterns = @(
        '^https?://github\.com/(?<path>.+)$',
        '^ssh://git@github\.com/(?<path>.+)$',
        '^git@github\.com:(?<path>.+)$',
        '^github-(?:public|private):(?<path>.+)$'
    )
    $path = $null
    foreach ($pattern in $patterns) {
        if ($value -match $pattern) {
            $path = $Matches['path'].TrimEnd('/')
            break
        }
    }
    if (-not $path) { return $null }

    $parts = @($path -split '/')
    if ($parts.Count -ne 2 -or $parts[0] -notmatch '^[A-Za-z0-9_.-]+$' -or $parts[1] -notmatch '^[A-Za-z0-9_.-]+$') {
        return $null
    }
    return "https://github.com/$($parts[0].ToLowerInvariant())/$($parts[1].ToLowerInvariant())"
}

function Get-ProjectRepositories([string]$Path) {
    $lines = @(Get-Content -LiteralPath $Path)
    if ($lines.Count -eq 0 -or $lines[0] -ne '---') { return @() }

    $repositories = [System.Collections.Generic.List[string]]::new()
    $found = $false
    $collecting = $false
    for ($index = 1; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($line -eq '---') {
            $collecting = $false
            break
        }

        if ($collecting) {
            if ($line -match '^\s*-\s+(.+)$') {
                $value = $Matches[1].Trim()
                if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
                $normalized = Resolve-NormalizedRepository $value
                if (-not $normalized) { throw "invalid repositories frontmatter: $Path" }
                $repositories.Add($normalized)
                continue
            }
            if ($line -match '^\s*(#.*)?$') { continue }
            if ($line -notmatch '^[^\s][^:]*:') { throw "invalid repositories frontmatter: $Path" }
            $collecting = $false
        }

        if ($line -match '^repositories:\s*$') {
            if ($found) { throw "invalid repositories frontmatter: $Path" }
            $found = $true
            $collecting = $true
        } elseif ($line -match '^repositories:\s*\[\]\s*$') {
            if ($found) { throw "invalid repositories frontmatter: $Path" }
            $found = $true
        } elseif ($line -match '^repositories:') {
            throw "invalid repositories frontmatter: $Path"
        }
    }
    if ($collecting) { throw "invalid repositories frontmatter: $Path" }
    return @($repositories)
}

function Get-ConfiguredVault([string]$Override) {
    if ($Override) { return $Override }
    if ($env:OBSIDIAN_VAULT_ROOT) { return $env:OBSIDIAN_VAULT_ROOT }

    $dotfilesDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $config = Join-Path ($dotfilesDir + '-private') 'obsidian/project-home-resolver.conf'
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { Fail "resolver config is missing: $config" }

    $configured = $null
    foreach ($rawLine in @(Get-Content -LiteralPath $config)) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^([^=]+)=(.+)$') { Fail "invalid resolver config: $config" }
        if ($Matches[1].Trim() -ne 'vault_root' -or $configured) { Fail "invalid resolver config: $config" }
        $configured = $Matches[2].Trim()
    }
    if (-not $configured) { Fail "resolver config has no vault_root: $config" }
    if ([System.IO.Path]::IsPathRooted($configured)) { return $configured }
    return (Join-Path $HOME $configured)
}

$mode = 'resolve'
$repoDir = (Get-Location).Path
$vaultOverride = $null
for ($index = 0; $index -lt $args.Count; $index++) {
    switch ($args[$index]) {
        'check' {
            if ($mode -ne 'resolve') { Fail 'check may be specified once' 1 }
            $mode = 'check'
        }
        '--repo' {
            $index++
            if ($index -ge $args.Count) { Fail '--repo requires a directory' 1 }
            $repoDir = $args[$index]
        }
        '--vault' {
            $index++
            if ($index -ge $args.Count) { Fail '--vault requires a directory' 1 }
            $vaultOverride = $args[$index]
        }
        '-h' { Show-Help; exit 0 }
        '--help' { Show-Help; exit 0 }
        default { Fail "unknown argument: $($args[$index])" 1 }
    }
}

try {
    $vaultDir = (Get-ConfiguredVault $vaultOverride)
    $projectsDir = Join-Path $vaultDir 'projects'
    if (-not (Test-Path -LiteralPath $projectsDir -PathType Container)) { Fail "vault projects directory is unavailable: $projectsDir" }
    $vaultDir = (Resolve-Path -LiteralPath $vaultDir).Path

    $mappings = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $projectsDir -File -Filter '*.md' -Recurse | Sort-Object FullName)) {
        foreach ($repository in @(Get-ProjectRepositories $file.FullName)) {
            $mappings.Add([PSCustomObject]@{ Repository = $repository; Path = $file.FullName })
        }
    }
} catch {
    Fail $_.Exception.Message 5
}

$duplicates = @($mappings | Group-Object Repository | Where-Object { $_.Count -gt 1 })
if ($mode -eq 'check') {
    if ($duplicates.Count -gt 0) {
        Write-Stderr 'error: duplicate Project Home mappings:'
        foreach ($group in $duplicates | Sort-Object Name) {
            Write-Stderr $group.Name
            foreach ($entry in $group.Group | Sort-Object Path) { Write-Stderr "  $($entry.Path)" }
        }
        exit 4
    }
    Write-Output 'OK: Obsidian Project Home mappings are unique.'
    exit 0
}

try {
    $origin = (& git -C $repoDir config --get remote.origin.url 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $origin) { Fail "origin remote is unavailable: $repoDir" }
    $normalizedOrigin = Resolve-NormalizedRepository $origin
    if (-not $normalizedOrigin) { Fail "unsupported origin remote: $origin" }
} catch {
    Fail $_.Exception.Message 5
}

$matches = @($mappings | Where-Object { $_.Repository -eq $normalizedOrigin } | Sort-Object Path)
if ($matches.Count -eq 0) { exit 3 }
if ($matches.Count -eq 1) {
    Write-Output $matches[0].Path
    exit 0
}

Write-Stderr "error: multiple Project Homes map to ${normalizedOrigin}:"
foreach ($entry in $matches) { Write-Stderr "  $($entry.Path)" }
exit 4
