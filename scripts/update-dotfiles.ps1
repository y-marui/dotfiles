#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dotfilesDir = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path -LiteralPath (Join-Path $dotfilesDir '.git') -PathType Container)) {
    throw "$dotfilesDir is not a Git repository"
}

$status = & git -C $dotfilesDir status --short
if ($LASTEXITCODE -ne 0) {
    throw "git status failed with exit code $LASTEXITCODE"
}

if ($status) {
    Write-Host '  SKIP    dotfiles pull (working tree has local changes)'
    exit 0
}

& git -C $dotfilesDir rev-parse --verify '@{upstream}' *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host '  SKIP    dotfiles pull (upstream is not configured)'
    exit 0
}

& git -C $dotfilesDir pull --ff-only
if ($LASTEXITCODE -ne 0) {
    throw "git pull --ff-only failed with exit code $LASTEXITCODE"
}

Write-Host "  UPDATE  dotfiles ($dotfilesDir)"
