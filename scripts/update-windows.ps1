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

# make update is itself running from this WinLibs installation. Keep it out of
# winget upgrade --all; otherwise winget cannot remove mingw64 while
# mingw32-make.exe is still executing from that directory.
$winLibsPackageId = 'BrechtSanders.WinLibs.POSIX.UCRT'
$winLibsPins = & winget pin list --id $winLibsPackageId --exact 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "winget pin list failed with exit code $LASTEXITCODE"
}
if ($winLibsPins -notmatch [regex]::Escape($winLibsPackageId)) {
    Invoke-NativeCommand winget pin add --id $winLibsPackageId --exact
}

Invoke-NativeCommand winget upgrade --all --silent --accept-source-agreements --include-unknown

Write-Warning @"
WinLibs was skipped because mingw32-make is using it during make update.
After this command finishes, update it from PowerShell with:
  winget upgrade --id $winLibsPackageId --exact
"@

# Enable-WURemoting
Get-WindowsUpdate -Verbose
Install-WindowsUpdate -AcceptAll -Verbose

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
