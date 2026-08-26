#Requires -Version 7.0
param(
    [string]$PrivateDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DotfilesDir = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PrivateDir)) {
    $PrivateDir = "$DotfilesDir-private"
}
$TemplateDir = Join-Path $DotfilesDir 'templates\dotfiles-private'
$ContractFile = Join-Path $DotfilesDir 'templates\dotfiles-private.contract'
$Errors = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $PrivateDir -PathType Container)) {
    Write-Output "dotfiles-private が隣接していないため構造検証をスキップします: $PrivateDir"
    exit 0
}
git -C $PrivateDir rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Output "dotfiles-private が隣接していないため構造検証をスキップします: $PrivateDir"
    exit 0
}

Get-ChildItem -LiteralPath $TemplateDir -Recurse -File -Filter '*.example' | ForEach-Object {
    $relativePath = $_.FullName.Substring($TemplateDir.Length + 1)
    $privateExample = Join-Path $PrivateDir $relativePath
    if (-not (Test-Path -LiteralPath $privateExample -PathType Leaf)) {
        $Errors.Add("dotfiles-private に雛形ファイルがありません: $relativePath")
    } elseif ((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $privateExample -Algorithm SHA256).Hash) {
        $Errors.Add("dotfiles-private の雛形が公開側と一致しません: $relativePath")
    }
}

Get-ChildItem -LiteralPath $PrivateDir -Recurse -File | Where-Object {
    $_.Extension -in @('.sh', '.ps1')
} | ForEach-Object {
    $relativePath = $_.FullName.Substring($PrivateDir.Length + 1).Replace('\', '/')
    if (-not $relativePath.StartsWith('docs/dev-charter/')) {
        $Errors.Add("private 側に実行ロジックを置けません: $relativePath")
    }
}

if (Test-Path -LiteralPath (Join-Path $PrivateDir 'Makefile')) {
    $Errors.Add('private 側に Makefile を置けません。実行ロジックは public 側へ置いてください。')
}

$ScaffoldMarker = Join-Path $PrivateDir '.dotfiles-private-scaffold'
if (Test-Path -LiteralPath $ScaffoldMarker -PathType Leaf) {
    if (Test-Path -LiteralPath (Join-Path $PrivateDir 'links.conf')) {
        $Errors.Add('scaffold モードでは links.conf を有効化できません。設定完了後にマーカーを削除してください。')
    }
    if ($Errors.Count -gt 0) {
        $Errors | ForEach-Object { Write-Error $_ }
        exit 1
    }
    Write-Output "dotfiles-private は未有効化の scaffold として有効です: $PrivateDir"
    exit 0
}

foreach ($line in Get-Content -LiteralPath $ContractFile) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }

    $parts = $line.Split('|')
    if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[1])) {
        $Errors.Add("公開側の private 構造契約が不正です: templates/dotfiles-private.contract")
        continue
    }
    $kind = $parts[0].Trim()
    $relativePath = $parts[1].Trim()
    if ($relativePath -match '^[\\/~]' -or $relativePath -match '(^|/)\.\.?(/|$)') {
        $Errors.Add("公開側の private 構造契約に不正なパスがあります: $relativePath")
        continue
    }

    switch ($kind) {
        'file' {
            $path = Join-Path $PrivateDir $relativePath
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                $Errors.Add("dotfiles-private に必須ファイルがありません: $relativePath")
            }
        }
        'glob' {
            $path = Join-Path $PrivateDir $relativePath
            if (-not (Get-ChildItem -Path $path -File -ErrorAction SilentlyContinue)) {
                $Errors.Add("dotfiles-private に一致する設定がありません: $relativePath")
            }
        }
        default { $Errors.Add("公開側の private 構造契約に未対応 kind があります: $kind") }
    }
}

$LinksFile = Join-Path $PrivateDir 'links.conf'
$LinksExample = Join-Path $TemplateDir 'links.conf.example'
if ((Test-Path -LiteralPath $LinksFile -PathType Leaf) -and
    (Get-FileHash -LiteralPath $LinksFile -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $LinksExample -Algorithm SHA256).Hash) {
    $Errors.Add('links.conf が公開側の links.conf.example と一致しません。対応表を両方更新してください。')
}

if ($Errors.Count -gt 0) {
    $Errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "dotfiles-private の構造契約は有効です: $PrivateDir"
