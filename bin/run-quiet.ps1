#!/usr/bin/env pwsh
# run-quiet: エラーがなければ1行サマリーを出力するラッパー
# 使い方: run-quiet <command> [args...]

Set-StrictMode -Version Latest

if ($args.Count -eq 0) {
    Write-Host "usage: run-quiet <command> [args...]"
    exit 1
}

$display = $args -join ' '
$cmd = $args[0]
$cmdArgs = @($args | Select-Object -Skip 1)

$LASTEXITCODE = $null
$output = & $cmd @cmdArgs 2>&1 | Out-String
$exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } elseif ($?) { 0 } else { 1 }

if ($exitCode -eq 0) {
    Write-Host "✓ $display succeeded"
    $warnings = ($output -split "`r?`n") | Where-Object { $_ -match '(?i)(warning|warn|deprecated|deprecation|note):' }
    if ($warnings) {
        $warnings | ForEach-Object { Write-Host $_ }
    }
} else {
    Write-Host "✗ $display failed (exit ${exitCode}):"
    Write-Host $output
    exit $exitCode
}
