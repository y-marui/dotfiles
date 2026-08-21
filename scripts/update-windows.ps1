Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

Write-Host "=== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Update started ==="

$dotfilesDir = Split-Path -Parent $PSScriptRoot

# WingetPinの宣言に実際のpin状態を合わせる（未宣言のpinは解除、宣言済みは追加）。
# 既知の不具合（誤検知等）で全体更新が停止するのを防ぐため、winget upgradeの前に実行する。
Invoke-NativeCommand pwsh -NoLogo -NoProfile -File "$dotfilesDir\windows\apply_wingetpin.ps1"

Invoke-NativeCommand winget upgrade --all --silent --accept-source-agreements --include-unknown

# Enable-WURemoting
Get-WindowsUpdate -Verbose
# -AcceptAllはEULA同意のみを自動化し、再起動確認は別扱いのため、
# -NonInteractive下では応答できず内部でnull参照例外になる。-IgnoreRebootで
# 再起動確認自体をスキップする（自動再起動はしない。手動で再起動すること）。
Install-WindowsUpdate -AcceptAll -IgnoreReboot -Verbose

if (Get-Command npm -ErrorAction SilentlyContinue) {
    Invoke-NativeCommand npm update --global
} else {
    Write-Host '  SKIP    npm (command not found)'
}

if (Get-Command pipx -ErrorAction SilentlyContinue) {
    Invoke-NativeCommand pipx upgrade-all
} else {
    Write-Host '  SKIP    pipx (command not found)'
}

if (Get-Command ghq-update -ErrorAction SilentlyContinue) {
    Invoke-NativeCommand ghq-update --pull-all
} else {
    Write-Host '  SKIP    ghq-update (command not found)'
}

Write-Host "=== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Update completed ==="
