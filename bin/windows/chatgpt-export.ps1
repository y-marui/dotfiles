#!/usr/bin/env pwsh
# chatgpt-export: chrome-chatgpt-exporter/cli の起動ラッパー
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$exporterRoot = $env:CHATGPT_EXPORTER_ROOT
if (-not $exporterRoot) {
    $scriptDirectory = (Get-Item -LiteralPath $PSScriptRoot).ResolveLinkTarget($true)
    $resolvedDirectory = if ($scriptDirectory) { $scriptDirectory.FullName } else { $PSScriptRoot }
    $exporterRoot = Join-Path $resolvedDirectory '../../../chrome-chatgpt-exporter'
}
$entryPoint = Join-Path $exporterRoot 'cli/index.js'
if (-not (Test-Path -LiteralPath $entryPoint -PathType Leaf)) {
    [Console]::Error.WriteLine('error: chrome-chatgpt-exporter/cli が見つかりません。CHATGPT_EXPORTER_ROOTを指定してください。')
    exit 3
}
& node $entryPoint @args
exit $LASTEXITCODE
