#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DotfilesDir = Split-Path -Parent $PSScriptRoot
$TemplateDir = Join-Path $DotfilesDir 'templates\dotfiles-private'
$Destination = if ($args.Count -gt 0) { $args[0] } else { "$DotfilesDir-private" }

if (Test-Path -LiteralPath $Destination) {
    throw "生成先が既に存在します: $Destination`n既存リポジトリを上書きしません。別の PRIVATE_SCAFFOLD_DIR を指定してください。"
}

New-Item -ItemType Directory -Path $Destination | Out-Null
Get-ChildItem -LiteralPath $TemplateDir -Force | Copy-Item -Destination $Destination -Recurse -Force
git init -b main $Destination | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "git init に失敗しました。途中まで生成したディレクトリは保持しています: $Destination"
}

Write-Output "dotfiles-private の安全な雛形を生成しました: $Destination"
Write-Output 'README.md に従って .example から実設定を作成してください。'
Write-Output '設定完了後に .dotfiles-private-scaffold を削除し、make private-validate を実行してください。'
