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
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $globalPython = (& python -c 'import os, sys; print(os.path.realpath(sys.executable))').Trim()
    } elseif (Get-Command py -ErrorAction SilentlyContinue) {
        $globalPython = (& py -3 -c 'import os, sys; print(os.path.realpath(sys.executable))').Trim()
    } else {
        throw 'pipx is installed, but no global Python command was found'
    }
    if ($LASTEXITCODE -ne 0 -or -not $globalPython) {
        throw 'failed to resolve the global Python executable'
    }

    $globalPythonVersion = (& $globalPython -c 'import platform; print(platform.python_version())').Trim()
    if ($LASTEXITCODE -ne 0 -or -not $globalPythonVersion) {
        throw 'failed to resolve the global Python version'
    }

    $pipxHome = (& pipx environment --value PIPX_HOME).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $pipxHome) {
        throw 'failed to resolve PIPX_HOME'
    }
    $pipxVenvsDir = Join-Path $pipxHome 'venvs'
    $reinstallAll = $false

    if (Test-Path -LiteralPath $pipxVenvsDir -PathType Container) {
        foreach ($venvDir in Get-ChildItem -LiteralPath $pipxVenvsDir -Directory) {
            $venvPython = Join-Path $venvDir.FullName 'Scripts\python.exe'
            if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
                $reinstallAll = $true
                break
            }

            $venvPythonInfo = @(& $venvPython -c 'import os, platform, sys; print(os.path.realpath(getattr(sys, "_base_executable", sys.executable))); print(platform.python_version())')
            if ($LASTEXITCODE -ne 0 -or $venvPythonInfo.Count -lt 2) {
                $reinstallAll = $true
                break
            }

            $venvBasePython = $venvPythonInfo[0].Trim()
            $venvPythonVersion = $venvPythonInfo[1].Trim()
            if ($venvBasePython -ne $globalPython -or $venvPythonVersion -ne $globalPythonVersion) {
                $reinstallAll = $true
                break
            }
        }
    }

    if ($reinstallAll) {
        Write-Host "  REINSTALL pipx environments with global Python $globalPythonVersion"
        Invoke-NativeCommand pipx reinstall-all --python $globalPython
    } else {
        Invoke-NativeCommand pipx upgrade-all
    }
} else {
    Write-Host '  SKIP    pipx (command not found)'
}

if (Get-Command ghq-update -ErrorAction SilentlyContinue) {
    Invoke-NativeCommand ghq-update --pull-all
} else {
    Write-Host '  SKIP    ghq-update (command not found)'
}

Write-Host "=== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Update completed ==="
