#!/usr/bin/env pwsh
# Install the dotfiles-approved native Windows Zellij release.

[CmdletBinding()]
param(
    [string]$InstallDirectory = (Join-Path $HOME '.local\bin'),
    [switch]$SkipUserPathUpdate,
    [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$zellijVersion = '0.44.3'
$target = 'x86_64-pc-windows-msvc'
$archiveName = "zellij-$target.zip"
$checksumName = "zellij-$target.sha256sum"
$releaseBaseUrl = "https://github.com/zellij-org/zellij/releases/download/v$zellijVersion"
$installPath = Join-Path $InstallDirectory 'zellij.exe'

if (-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows)) {
    throw 'このスクリプトはWindows専用です。'
}
if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne
    [System.Runtime.InteropServices.Architecture]::X64) {
    throw 'Zellijの公式Windowsバイナリは現在x86_64のみ対応しています。'
}

function Add-UserPathEntry {
    param([Parameter(Mandatory)][string]$Path)

    $normalizedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $processEntries = @($env:PATH -split ';' | Where-Object { $_ })
    if (-not ($processEntries | Where-Object { $_.TrimEnd('\') -ieq $normalizedPath })) {
        $env:PATH = "$normalizedPath;$env:PATH"
    }

    if ($SkipUserPathUpdate) {
        return
    }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $userEntries = @($userPath -split ';' | Where-Object { $_ })
    if (-not ($userEntries | Where-Object { $_.TrimEnd('\') -ieq $normalizedPath })) {
        $updatedPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
            $normalizedPath
        } else {
            "$userPath;$normalizedPath"
        }
        [Environment]::SetEnvironmentVariable('Path', $updatedPath, 'User')
        Write-Host "  PATH    $normalizedPath"
    }
}

$installedVersion = ''
if (Test-Path -LiteralPath $installPath -PathType Leaf) {
    try {
        $installedVersion = ((& $installPath --version 2>$null) -split '\s+')[-1]
    } catch {
        $installedVersion = ''
    }
}

if (-not $VerifyOnly -and $installedVersion -eq $zellijVersion) {
    Add-UserPathEntry -Path $InstallDirectory
    Write-Host "  SKIP    zellij $zellijVersion ($installPath)"
    exit 0
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "dotfiles-zellij-$([Guid]::NewGuid().ToString('N'))"
)
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $archivePath = Join-Path $tempRoot $archiveName
    $checksumPath = Join-Path $tempRoot $checksumName
    $extractPath = Join-Path $tempRoot 'extracted'

    Write-Host "==> Installing Zellij $zellijVersion ($target)..."
    $previousProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri "$releaseBaseUrl/$archiveName" -OutFile $archivePath
        Invoke-WebRequest -Uri "$releaseBaseUrl/$checksumName" -OutFile $checksumPath
    } finally {
        $ProgressPreference = $previousProgressPreference
    }

    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath
    $candidates = @(Get-ChildItem -LiteralPath $extractPath -Recurse -File -Filter 'zellij.exe')
    if ($candidates.Count -ne 1) {
        throw "アーカイブ内のzellij.exeが一意ではありません (count: $($candidates.Count))"
    }
    $downloadedBinary = $candidates[0].FullName

    # The official checksum is for the extracted executable, not the ZIP file.
    $expectedChecksum = ((Get-Content -LiteralPath $checksumPath -Raw).Trim() -split '\s+')[0]
    $actualChecksum = (Get-FileHash -LiteralPath $downloadedBinary -Algorithm SHA256).Hash
    if ($actualChecksum -ine $expectedChecksum) {
        throw "Zellij checksum verification failed: expected=$expectedChecksum actual=$actualChecksum"
    }
    Write-Host '  VERIFY  checksum'

    $downloadedVersion = ((& $downloadedBinary --version) -split '\s+')[-1]
    if ($downloadedVersion -ne $zellijVersion) {
        throw "Unexpected Zellij version: expected=$zellijVersion actual=$downloadedVersion"
    }

    if ($VerifyOnly) {
        Write-Host "  VERIFY  zellij $zellijVersion release artifact"
        return
    }

    New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
    Copy-Item -LiteralPath $downloadedBinary -Destination $installPath -Force
    Add-UserPathEntry -Path $InstallDirectory

    if ($installedVersion) {
        Write-Host "  CHANGE  zellij $installedVersion -> $zellijVersion ($installPath)"
    } else {
        Write-Host "  INSTALL zellij $zellijVersion ($installPath)"
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
