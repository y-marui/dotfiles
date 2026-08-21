#!/usr/bin/env pwsh
# winget pinの実際の状態をWingetPin.cacheへ記録する。

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cacheFile = Join-Path $PSScriptRoot 'WingetPin.cache'

$output = @(& winget pin list)
if ($LASTEXITCODE -ne 0) {
    throw "winget pin list failed with exit code $LASTEXITCODE"
}

# ロケールによってヘッダー文言（列名）が変わり、かつCJK文字は表示幅と文字数が
# 一致しないため固定桁での列抽出は使えない。区切り線（ハイフンのみの行）で
# データ行の開始位置を特定し、各データ行は空白区切りでトークン化したうえで
# 右側（Version, Source, PinType は空白を含まない技術的な値）から数えてIDを
# 取り出す（列: Name..., ID, Version, Source, PinType。Nameだけが空白を含みうる）。
$separatorIndex = -1
for ($i = 0; $i -lt $output.Count; $i++) {
    if ($output[$i] -match '^-+$') {
        $separatorIndex = $i
        break
    }
}

$ids = [System.Collections.Generic.List[string]]::new()
if ($separatorIndex -ge 0) {
    for ($i = $separatorIndex + 1; $i -lt $output.Count; $i++) {
        $line = $output[$i].Trim()
        if ($line -eq '') { continue }
        $tokens = $line -split '\s+'
        if ($tokens.Count -ge 4) {
            $ids.Add($tokens[$tokens.Count - 4])
        }
    }
}

$sorted = @($ids | Sort-Object -Unique)
Set-Content -LiteralPath $cacheFile -Value $sorted -Encoding utf8NoBOM
Write-Host 'WingetPin.cache updated.'
