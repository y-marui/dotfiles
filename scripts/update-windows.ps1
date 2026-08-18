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

# 旧make updateが実行中のmingw32-make.exeを保護するために作成したpinを解除する。
# dots updateはPowerShellで動作するため、WinLibsも一括更新できる。
$winLibsPackageId = 'BrechtSanders.WinLibs.POSIX.UCRT'
$winLibsPins = & winget pin list --id $winLibsPackageId --exact 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "winget pin list failed with exit code $LASTEXITCODE"
}
if ($winLibsPins -match [regex]::Escape($winLibsPackageId)) {
    Invoke-NativeCommand winget pin remove --id $winLibsPackageId --exact
}

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
    Invoke-NativeCommand ghq-update --all
} else {
    Write-Host '  SKIP    ghq-update (command not found)'
}

Write-Host "=== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Update completed ==="
