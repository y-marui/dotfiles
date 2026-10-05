#!/usr/bin/env pwsh
# 共通・agent 専用の skill を Claude Code / Codex の個人 skill 配置へ個別リンクする（apply.sh の PowerShell 版）。
#
# シンボリックリンクの作成には、開発者モードの有効化か管理者権限（gsudo）が必要。

param(
    [Parameter(Mandatory)]
    [ValidateSet('claude', 'codex')]
    [string]$Agent
)

. (Join-Path $PSScriptRoot '..\_common.ps1')

$skillHome = Get-SkillHome -Agent $Agent
$cacheHome = Get-SkillCacheHome
$stateHome = Join-Path $cacheHome '.sources'
$backupDir = Get-BackupPath -Child "ai-skills\$Agent"
$changed = $false

New-Item -ItemType Directory -Force -Path $skillHome | Out-Null

$sources = [System.Collections.Generic.List[object]]::new()

# 外部 skill は公式 skill-installer で dotfiles 専用キャッシュへ取得し、
# Claude Code / Codex から同じ実体を参照する。
foreach ($entry in (Get-ExternalSkills -Agent $Agent)) {
    $name = $entry['name']
    $skillPath = [string]$entry['path']
    if ($name -ne ($skillPath.TrimEnd('/') -split '/')[-1]) {
        throw "external skill name must match path basename: $name"
    }
    $repo = [string]$entry['repo']
    $ref = [string](Get-Value $entry 'ref' 'main')
    $sourceDir = Join-Path $cacheHome $name
    $stateFile = Join-Path $stateHome $name
    $wantedState = "$repo`t$ref`t$skillPath"
    $currentState = ''
    if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
        $currentState = (Get-Content -LiteralPath $stateFile -Raw).TrimEnd("`r", "`n")
    }

    if (-not (Test-Path -LiteralPath (Join-Path $sourceDir 'SKILL.md') -PathType Leaf) -or $currentState -ne $wantedState) {
        $installer = Join-Path (Get-CodexHome) 'skills\.system\skill-installer\scripts\install-skill-from-github.py'
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
            throw "skill-installer が見つかりません: $installer"
        }
        $python = Get-Command python3, python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $python) { throw 'python3 / python が見つかりません' }
        if (Test-PathOrLink -Path $sourceDir) {
            $backupPath = Join-Path $backupDir "external\$name"
            Move-ToBackup -Path $sourceDir -Destination $backupPath
            Write-Host "  BACKUP  $sourceDir -> $backupPath"
        }
        New-Item -ItemType Directory -Force -Path $cacheHome, $stateHome | Out-Null
        Write-Host "  INSTALL $name ($repo@${ref}:$skillPath)"
        Invoke-NativeVisible -Command $python.Source -Arguments @($installer, '--repo', $repo, '--ref', $ref, '--path', $skillPath, '--dest', $cacheHome)
        [System.IO.File]::WriteAllText($stateFile, "$wantedState`n", [System.Text.UTF8Encoding]::new($false))
        $changed = $true
    }
    $sources.Add([pscustomobject]@{ Name = $name; Dir = $sourceDir })
}

foreach ($source in (Get-LocalSkillSources -Agent $Agent)) { $sources.Add($source) }

$duplicateNames = @(Get-DuplicateNames -Sources $sources)
if ($duplicateNames.Count -gt 0) {
    [Console]::Error.WriteLine("共通 skill と $Agent 専用 skill で名前が重複しています:")
    [Console]::Error.WriteLine(($duplicateNames -join "`n"))
    exit 1
}

foreach ($source in ($sources | Sort-Object { $_.Name } -CaseSensitive)) {
    $destination = Join-Path $skillHome $source.Name

    if (Test-SamePath (Get-LinkTarget -Path $destination) $source.Dir) { continue }

    if (Test-PathOrLink -Path $destination) {
        $scope = "$(Split-Path -Leaf (Split-Path -Parent $skillHome))-$(Split-Path -Leaf $skillHome)"
        $backupPath = Join-Path $backupDir "$scope\$($source.Name)"
        Move-ToBackup -Path $destination -Destination $backupPath
        Write-Host "  BACKUP  $destination -> $backupPath"
    }

    try {
        New-Item -ItemType SymbolicLink -Path $destination -Target $source.Dir | Out-Null
    } catch {
        # 権限不足なら gsudo で昇格して、スクリプト全体をやり直す（処理は冪等）。
        # 昇格済みなのに失敗した場合や gsudo がない場合は、そのままエラーにする。
        if (-not (Test-Elevated) -and (Get-Command gsudo -ErrorAction SilentlyContinue)) {
            Write-Host '  シンボリックリンクの作成に権限が必要なため、gsudo で昇格して再実行します'
            & gsudo pwsh -NoLogo -NoProfile -File $PSCommandPath -Agent $Agent
            exit $LASTEXITCODE
        }
        throw "シンボリックリンクを作成できません: $destination（開発者モードを有効にするか、gsudo で実行してください）: $($_.Exception.Message)"
    }
    Write-Host "  LINK    $destination -> $($source.Dir)"
    $changed = $true
}

if (-not $changed) {
    Write-Host '  (already up to date)'
}
