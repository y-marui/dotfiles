#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $PSScriptRoot（通常 ~\.local\bin\dotfiles）自体がディレクトリシンボリックリンク
# （bin\windows へのリンク）の場合はその実体を解決する。dots.ps1 個別のファイル
# リンクではなく親ディレクトリ全体をリンクする方式のため、ファイル単位の
# LinkType チェックではなくディレクトリ単位でチェックする必要がある。
$scriptDirItem = Get-Item -LiteralPath $PSScriptRoot -Force
if ($scriptDirItem.LinkType -eq 'SymbolicLink') {
    $target = [string]$scriptDirItem.Target
    if (-not [System.IO.Path]::IsPathRooted($target)) {
        $target = Join-Path (Split-Path $scriptDirItem.FullName -Parent) $target
    }
    $realScriptDir = $target
} else {
    $realScriptDir = $scriptDirItem.FullName
}
# realScriptDir は <dotfiles>\bin\windows なので、リポジトリルートへは二階層上がる
$dotfilesDir = Split-Path -Parent (Split-Path -Parent $realScriptDir)
$privateDir = "$dotfilesDir-private"

function Show-Usage {
    @'
Usage:
  dots status [-NoFetch]
  dots check [--verbose]
  dots update
  dots winget {apply|diff|prune|cache}  # N/A: sync merge
  dots ghq    {apply|diff|sync|merge|prune}  # N/A: cache
  dots ai     {apply|diff|prune}  # N/A: sync merge cache（Claude Code・Codex を一括）
  dots claude {apply|diff|prune}  # N/A: sync merge cache
  dots codex  {apply|diff|prune}  # N/A: sync merge cache
  dots copilot {apply|diff|prune}  # N/A: sync merge cache（MCP のみ）
  dots verbs
  dots help

Windowsでは status / check / update / winget / ghq / ai / claude / codex / copilot を利用できます。
check は警告を1行ずつ要約し（--verbose で詳細）、結果を ~/.cache/dots/check-summary 等へ書きます。
brew / npm / pipx / dock / shortcuts / sudo Touch ID などmacOS固有の項目、定期実行・通知は対象外です。
動詞（apply / diff / sync / merge / prune / cache）の意味は docs/specification.md、
実装状況は README.md の動詞表を参照してください。
`dots <domain> help` でそのドメインの実装状況を表示します。
「N/A」は意図的に存在しない動詞（終了コード0）、「未実装」は実装予定の動詞（エラー）です。

Options:
  --no-prune          apply で削除（prune）を行わず、追加・更新のみ行う
  --dry-run           何も変更せず、実行した場合の変更予定だけを表示する
  --yes               宣言側の項目を削除する sync に必要（ghq。削除がなければ不要）
  --summary           diff の差分の件数を1行で示す
  --exit-code         diff で差分があれば終了コード1を返す（既定は差分があっても0）
  --mcp-only | --plugin-only | --skill-only
                      ai / claude / codex で対象を MCP・plugin・skill のどれか1つに絞る
'@
}

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

# ai / claude / codex / copilot の各スクリプト（ai/ 配下の *.ps1）を子プロセスで実行し、終了コードを返す。
function Invoke-AiScript {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [string[]]$ScriptArgs = @()
    )

    & pwsh -NoLogo -NoProfile -File (Join-Path $dotfilesDir $RelativePath) @ScriptArgs | Out-Host
    return $LASTEXITCODE
}

# 1つの agent の MCP・plugin・skill に対して動詞を実行する。diff で差分があれば $true を返す。
function Invoke-AiAgent {
    param(
        [Parameter(Mandatory)][string]$Agent,
        [Parameter(Mandatory)][string]$Action,
        [string[]]$Options = @()
    )

    $allowedKinds = if ($Agent -eq 'copilot') { @('mcp') } else { @('mcp', 'plugin', 'skill') }
    $only = @()
    $noPrune = $false
    foreach ($option in $Options) {
        switch ($option) {
            '--mcp-only' { $only += 'mcp' }
            '--plugin-only' { if ($Agent -eq 'copilot') { throw "unknown $Agent option: $option" }; $only += 'plugin' }
            '--skill-only' { if ($Agent -eq 'copilot') { throw "unknown $Agent option: $option" }; $only += 'skill' }
            '--no-prune' { $noPrune = $true }
            default { throw "unknown $Agent option: $option" }
        }
    }
    if ($only.Count -gt 1) {
        throw '--mcp-only / --plugin-only / --skill-only は同時指定できない'
    }
    $kinds = if ($only.Count -eq 1) { $only } else { $allowedKinds }

    $diffFound = $false
    foreach ($kind in $kinds) {
        Write-Host "--- $kind ---"
        if ($kind -eq 'skill') {
            $dir = 'ai\skills'
            $scriptArgs = @('-Agent', $Agent)
        } else {
            $dir = "ai\$Agent\$kind"
            $scriptArgs = @()
        }
        switch ($Action) {
            'diff' {
                $code = Invoke-AiScript -RelativePath "$dir\diff.ps1" -ScriptArgs $scriptArgs
                # 終了コード1は「差分あり」。2以上はスクリプトのエラー。
                if ($code -eq 1) { $diffFound = $true } elseif ($code -ne 0) { throw "$Agent $kind diff failed with exit code $code" }
            }
            'apply' {
                $code = Invoke-AiScript -RelativePath "$dir\apply.ps1" -ScriptArgs $scriptArgs
                if ($code -ne 0) { throw "$Agent $kind apply failed with exit code $code" }
                if (-not $noPrune) {
                    $code = Invoke-AiScript -RelativePath "$dir\prune.ps1" -ScriptArgs $scriptArgs
                    if ($code -ne 0) { throw "$Agent $kind prune failed with exit code $code" }
                }
            }
            'prune' {
                $code = Invoke-AiScript -RelativePath "$dir\prune.ps1" -ScriptArgs $scriptArgs
                if ($code -ne 0) { throw "$Agent $kind prune failed with exit code $code" }
            }
        }
    }
    return $diffFound
}

function Show-RepositoryStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [bool]$Fetch
    )

    $needsAttention = $false
    Write-Host $Name
    Write-Host "  path: $Path"

    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git') -PathType Container)) {
        Write-Host '  status: not found'
        Write-Host
        return $true
    }

    if ($Fetch) {
        & git -C $Path fetch --quiet --prune
        if ($LASTEXITCODE -ne 0) {
            Write-Host '  fetch: failed (cached remote state follows)'
            $needsAttention = $true
        }
    }

    $branch = (& git -C $Path branch --show-current 2>$null)
    if (-not $branch) {
        $branch = '(detached HEAD)'
    }
    Write-Host "  branch: $branch"

    $changes = @(& git -C $Path status --short)
    if ($LASTEXITCODE -ne 0) {
        throw "git status failed for $Path"
    }
    if ($changes.Count -gt 0) {
        Write-Host '  working tree:'
        $changes | ForEach-Object { Write-Host "    $_" }
        $needsAttention = $true
    } else {
        Write-Host '  working tree: clean'
    }

    $upstream = (& git -C $Path rev-parse --abbrev-ref '@{upstream}' 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $upstream) {
        Write-Host '  remote: no upstream'
        Write-Host
        return $true
    }

    $counts = ((& git -C $Path rev-list --left-right --count "HEAD...$upstream") -split '\s+')
    if ($LASTEXITCODE -ne 0 -or $counts.Count -ne 2) {
        throw "git rev-list failed for $Path"
    }
    $ahead = [int]$counts[0]
    $behind = [int]$counts[1]

    if ($ahead -eq 0 -and $behind -eq 0) {
        Write-Host "  remote: up to date ($upstream)"
    } elseif ($ahead -eq 0) {
        Write-Host "  remote: $behind commit(s) to pull ($upstream)"
        $needsAttention = $true
    } elseif ($behind -eq 0) {
        Write-Host "  remote: $ahead commit(s) to push ($upstream)"
        $needsAttention = $true
    } else {
        Write-Host "  remote: diverged; $ahead to push, $behind to pull ($upstream)"
        $needsAttention = $true
    }
    Write-Host

    return $needsAttention
}

# ── dots check ────────────────────────────────────────────────────────────────
# Unix版（bin/unix/dots の _check_summary / _check_verbose / _check_write_cache）に揃えた実装。
# 既定は警告を1行ずつ出す要約（差分がなければ何も出さない）で、結果を
# ~/.cache/dots/{check-summary,check-state,check-digest} へ書く。シェル起動時の表示は
# terminal/powershell/profile.ps1 がこのキャッシュを読む。macOSのLaunchAgentによる定期実行・通知は
# Windowsには移植していない（dots check を手動で実行したときにキャッシュを更新する）。
$checkCacheDir = if ($env:DOTS_CHECK_CACHE_DIR) { $env:DOTS_CHECK_CACHE_DIR } else { Join-Path $HOME '.cache\dots' }

function Get-CheckRepoSummary {
    param([string]$Label, [string]$Path)

    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git'))) { return }
    $parts = @()
    & git -C $Path diff --quiet 2>$null
    $dirty = $LASTEXITCODE -ne 0
    & git -C $Path diff --cached --quiet 2>$null
    if ($dirty -or $LASTEXITCODE -ne 0) { $parts += 'uncommitted changes' }
    $unpushed = @(& git -C $Path log '@{u}..' --oneline 2>$null)
    if ($LASTEXITCODE -eq 0 -and $unpushed.Count -gt 0) { $parts += "$($unpushed.Count) commits unpushed" }
    if ($parts.Count -gt 0) {
        "⚠ ${Label}: $($parts -join ' / ') (dots status で確認)"
    }
}

function Get-CheckLinksSummary {
    $output = & pwsh -NoLogo -NoProfile -File "$dotfilesDir\scripts\check.ps1" 2>&1 | Out-String
    $broken = if ($output -match 'BROKEN=(\d+)') { [int]$Matches[1] } else { 0 }
    $missing = if ($output -match 'NOT LINKED=(\d+)') { [int]$Matches[1] } else { 0 }
    if ($broken -gt 0 -or $missing -gt 0) {
        "⚠ links: $broken broken / $missing not linked (make check で確認)"
    }
}

# scripts/install.ps1 が make install / dots update のたびに、リンク化できない既存ファイルを
# ~/.dotfiles-backup/<timestamp>/ へ退避する。溜まっている件数を知らせる（削除はユーザーが行う）。
function Get-CheckBackupSummary {
    $backupDir = Join-Path $HOME '.dotfiles-backup'
    if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) { return }
    $count = @(Get-ChildItem -LiteralPath $backupDir -Directory -Force).Count
    if ($count -gt 0) {
        "⚠ backup: ${count}件が $backupDir に蓄積（中身を確認し、不要なら Remove-Item -Recurse で削除）"
    }
}

# 子プロセスの --summary / -Summary 出力が空でなければ警告行にする（Unix版の _check_script_summary）。
function Get-CheckScriptSummary {
    param([string]$Label, [string]$Hint, [string[]]$PwshArgs)

    $output = (& pwsh -NoLogo -NoProfile -File @PwshArgs 2>$null | Out-String).Trim()
    if ($output) { "⚠ ${Label}: $output ($Hint)" }
}

function Get-CheckSummary {
    Get-CheckLinksSummary
    Get-CheckBackupSummary
    Get-CheckRepoSummary -Label 'dotfiles' -Path $dotfilesDir
    Get-CheckRepoSummary -Label 'dotfiles-private' -Path $privateDir

    Get-CheckScriptSummary -Label 'winget' -Hint 'dots winget diff で確認' `
        -PwshArgs @("$dotfilesDir\windows\diff_wingetpin.ps1", '-Summary')
    Get-CheckScriptSummary -Label 'ghq keep-up-to-date' -Hint 'dots ghq diff で確認' `
        -PwshArgs @("$dotfilesDir\ghq\keep-up-to-date.ps1", 'diff', '--summary')

    foreach ($agent in @('claude', 'codex')) {
        if ($agent -eq 'codex' -and -not (Get-Command codex -ErrorAction SilentlyContinue)) { continue }
        if (Test-Path -LiteralPath "$dotfilesDir\ai\$agent\mcp\servers.json") {
            Get-CheckScriptSummary -Label "$agent mcp" -Hint "dots $agent diff --mcp-only で確認" `
                -PwshArgs @("$dotfilesDir\ai\$agent\mcp\diff.ps1", '-Summary')
        }
        if (Test-Path -LiteralPath "$dotfilesDir\ai\$agent\plugin\plugins.json") {
            Get-CheckScriptSummary -Label "$agent plugin" -Hint "dots $agent diff --plugin-only で確認" `
                -PwshArgs @("$dotfilesDir\ai\$agent\plugin\diff.ps1", '-Summary')
        }
        if (Test-Path -LiteralPath "$dotfilesDir\ai\skills\external.json") {
            Get-CheckScriptSummary -Label "$agent skill" -Hint "dots $agent diff --skill-only で確認" `
                -PwshArgs @("$dotfilesDir\ai\skills\diff.ps1", '-Agent', $agent, '-Summary')
        }
    }

    if ((Get-Command copilot -ErrorAction SilentlyContinue) -and
        (Test-Path -LiteralPath "$dotfilesDir\ai\copilot\mcp\servers.json")) {
        Get-CheckScriptSummary -Label 'copilot mcp' -Hint 'dots copilot diff で確認' `
            -PwshArgs @("$dotfilesDir\ai\copilot\mcp\diff.ps1", '-Summary')
    }
}

# dots check（非verbose）の結果を check-summary / check-state / check-digest へ原子的に書く。
function Write-CheckCache {
    param([string[]]$Lines = @())

    $state = if ($Lines.Count -eq 0) { 'clean' } else { 'warning' }
    $summary = $Lines -join "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$state`n$summary")
    $digest = ([System.Security.Cryptography.SHA256]::HashData($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
    $utf8 = [System.Text.UTF8Encoding]::new($false)

    New-Item -ItemType Directory -Force -Path $checkCacheDir | Out-Null
    $summaryFile = Join-Path $checkCacheDir 'check-summary'
    $temporary = "$summaryFile.$([guid]::NewGuid().ToString('N')).tmp"
    [System.IO.File]::WriteAllText($temporary, $(if ($summary) { "$summary`n" } else { '' }), $utf8)
    Move-Item -LiteralPath $temporary -Destination $summaryFile -Force
    [System.IO.File]::WriteAllText((Join-Path $checkCacheDir 'check-state'), "$state`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $checkCacheDir 'check-digest'), "$digest`n", $utf8)
}

function Write-CheckHeader {
    param([string]$Title)

    Write-Host '=========================================='
    Write-Host " $Title"
    Write-Host '=========================================='
}

# dots check --verbose: 各項目の詳細を順に表示する（Unix版の _check_verbose）。
function Invoke-CheckVerbose {
    Write-CheckHeader 'Checking symlinks (make check) ...'
    & pwsh -NoLogo -NoProfile -File "$dotfilesDir\scripts\check.ps1" | Out-Host
    Write-Host ''

    Write-CheckHeader 'Checking dotfiles / dotfiles-private status ...'
    Show-RepositoryStatus -Name 'dotfiles' -Path $dotfilesDir -Fetch $false | Out-Null
    Show-RepositoryStatus -Name 'dotfiles-private' -Path $privateDir -Fetch $false | Out-Null

    Write-CheckHeader 'Checking ~/.dotfiles-backup accumulation ...'
    Get-CheckBackupSummary | ForEach-Object { Write-Host $_ }
    Write-Host ''

    Write-CheckHeader 'Checking winget / ghq ...'
    & pwsh -NoLogo -NoProfile -File "$dotfilesDir\windows\diff_wingetpin.ps1" | Out-Host
    & pwsh -NoLogo -NoProfile -File "$dotfilesDir\ghq\keep-up-to-date.ps1" diff | Out-Host
    Write-Host ''

    foreach ($agent in @('claude', 'codex', 'copilot')) {
        Write-CheckHeader "Checking $agent ..."
        if ($agent -eq 'claude' -or (Get-Command $agent -ErrorAction SilentlyContinue)) {
            Invoke-AiAgent -Agent $agent -Action 'diff' | Out-Null
        } else {
            Write-Host "$agent is not installed."
        }
        Write-Host ''
    }
}

# ドメイン×動詞のテーブル。bin/unix/_dots-verbs.sh の _dots_domain_spec と同じ書式で、
# scripts/check-dots-verb-table.sh が両者の一致を検証する。
#   ok 実装済み / na 対象外（理由を $verbNaReasons に書く） / todo 未実装
$verbs = @('apply', 'diff', 'sync', 'merge', 'prune', 'cache')
$verbSpecs = @{
    'ghq'    = 'apply=ok diff=ok sync=ok merge=ok prune=ok cache=na'
    'ai'      = 'apply=ok diff=ok sync=na merge=na prune=ok cache=na'
    'claude'  = 'apply=ok diff=ok sync=na merge=na prune=ok cache=na'
    'codex'   = 'apply=ok diff=ok sync=na merge=na prune=ok cache=na'
    'copilot' = 'apply=ok diff=ok sync=na merge=na prune=ok cache=na'
    'winget' = 'apply=ok diff=ok sync=na merge=na prune=ok cache=ok'
}
$verbNaReasons = @{
    'ghq:cache'    = '実状態をGit configから直接読むためキャッシュ不要'
    'winget:sync'  = '宣言（windows/WingetPin）は理由コメント付きで人が編集する'
    'winget:merge' = '宣言（windows/WingetPin）は理由コメント付きで人が編集する'
    'ai:sync'      = '宣言（ai/配下）は人が編集する。実状態から自動生成しない'
    'ai:merge'     = '宣言（ai/配下）は人が編集する。実状態から自動生成しない'
    'ai:cache'     = 'キャッシュ不要。実状態を直接読む'
    'claude:sync'  = '宣言（ai/配下）は人が編集する。実状態から自動生成しない'
    'claude:merge' = '宣言（ai/配下）は人が編集する。実状態から自動生成しない'
    'claude:cache' = 'キャッシュ不要。実状態を直接読む'
    'codex:sync'   = '宣言（ai/配下）は人が編集する。実状態から自動生成しない'
    'codex:merge'  = '宣言（ai/配下）は人が編集する。実状態から自動生成しない'
    'codex:cache'  = 'キャッシュ不要。実状態を直接読む'
    'copilot:sync'  = '宣言（ai/配下）は人が編集する。実状態から自動生成しない'
    'copilot:merge' = '宣言（ai/配下）は人が編集する。実状態から自動生成しない'
    'copilot:cache' = 'キャッシュ不要。実状態を直接読む'
}
# 動詞ごとに受け付ける共通オプション（Unix側の _dots_verb_options に相当。
# scripts/check-dots-verb-table.sh が同じ書式で一致を検証する）。
$verbOptions = @{
    'ghq:apply'    = '--dry-run --no-prune'
    'ghq:prune'    = '--dry-run'
    'ghq:sync'     = '--dry-run --yes'
    'ghq:merge'    = '--dry-run'
    'ghq:diff'     = '--exit-code --summary'
    'winget:apply' = '--dry-run --no-prune'
    'winget:prune' = '--dry-run'
    'winget:diff'  = '--exit-code --summary'
    'ai:apply'      = '--no-prune'
    'ai:diff'       = '--exit-code'
    'claude:apply'  = '--no-prune'
    'claude:diff'   = '--exit-code'
    'codex:apply'   = '--no-prune'
    'codex:diff'    = '--exit-code'
    'copilot:apply' = '--no-prune'
    'copilot:diff'  = '--exit-code'
}
$commonOptions = @('--dry-run', '--yes', '--no-prune', '--backup-dir', '--exit-code', '--summary')

function Get-VerbState {
    param([string]$Domain, [string]$Verb)

    foreach ($entry in ($verbSpecs[$Domain] -split ' ')) {
        $name, $state = $entry -split '=', 2
        if ($name -eq $Verb) { return $state }
    }
    return $null
}

function Get-OkVerbs {
    param([string]$Domain)

    (@($verbs | Where-Object { (Get-VerbState -Domain $Domain -Verb $_) -eq 'ok' })) -join '|'
}

function Show-DomainHelp {
    param([string]$Domain)

    'Usage:'
    "  dots $Domain {$(Get-OkVerbs -Domain $Domain)}"
    foreach ($verb in $verbs) {
        switch (Get-VerbState -Domain $Domain -Verb $verb) {
            'na' { "    ${verb}: N/A（$($verbNaReasons["${Domain}:${verb}"])）" }
            'todo' { "    ${verb}: 未実装" }
        }
    }
}

# 動詞ゲート。実行してよければ $true、N/A・helpを表示済みなら $false を返す。
# 未実装・未知の動詞・受け付けないオプションは例外にする。
function Test-VerbGate {
    param([string]$Domain, [string[]]$VerbArgs)

    if ($VerbArgs.Count -eq 0) {
        throw "usage: dots $Domain {$(Get-OkVerbs -Domain $Domain)}"
    }
    $verb = $VerbArgs[0]
    if ($verb -in @('help', '-h', '--help')) {
        # 出力が戻り値（真偽値）に混ざらないよう Out-Host で直接表示する
        Show-DomainHelp -Domain $Domain | Out-Host
        return $false
    }
    $state = Get-VerbState -Domain $Domain -Verb $verb
    if (-not $state) {
        throw "unknown $Domain action: $verb"
    }
    if ($state -eq 'na') {
        [Console]::Error.WriteLine("N/A: dots $Domain $verb — $($verbNaReasons["${Domain}:${verb}"])")
        return $false
    }
    if ($state -eq 'todo') {
        throw "dots $Domain $verb は未実装です"
    }
    $allowed = @()
    if ($verbOptions.ContainsKey("${Domain}:${verb}")) {
        $allowed = @($verbOptions["${Domain}:${verb}"] -split ' ')
    }
    foreach ($argument in @($VerbArgs | Select-Object -Skip 1)) {
        if (($argument -in $commonOptions) -and ($argument -notin $allowed)) {
            throw "dots $Domain $verb は $argument を受け付けません"
        }
    }
    return $true
}

$commandName = if ($args.Count -gt 0) { $args[0] } else { 'help' }
# 空配列を if 式の出力として代入すると PowerShell のパイプライン展開で $null に潰れる
# （Set-StrictMode 下で $null.Count がエラーになる）ため、@() でパイプ全体を包んで防ぐ。
$commandArgs = @($args | Select-Object -Skip 1)

if ($verbSpecs.ContainsKey($commandName)) {
    if (-not (Test-VerbGate -Domain $commandName -VerbArgs $commandArgs)) {
        exit 0
    }
}

switch ($commandName) {
    'status' {
        $fetch = $true
        foreach ($argument in $commandArgs) {
            switch ($argument) {
                '-NoFetch' { $fetch = $false }
                '--no-fetch' { $fetch = $false }
                default { throw "unknown status option: $argument" }
            }
        }

        $needsAttention = Show-RepositoryStatus -Name 'dotfiles' -Path $dotfilesDir -Fetch $fetch
        if (Show-RepositoryStatus -Name 'dotfiles-private' -Path $privateDir -Fetch $fetch) {
            $needsAttention = $true
        }
        if ($needsAttention) {
            exit 1
        }
    }
    'check' {
        $checkVerbose = $false
        foreach ($argument in $commandArgs) {
            switch ($argument) {
                '--verbose' { $checkVerbose = $true }
                { $_ -in @('-h', '--help') } { 'Usage: dots check [--verbose]'; exit 0 }
                default { throw "unknown check option: $argument" }
            }
        }

        if ($checkVerbose) {
            Invoke-CheckVerbose
        } else {
            $checkLines = @(Get-CheckSummary)
            Write-CheckCache -Lines $checkLines
            if ($checkLines.Count -gt 0) {
                $checkLines | ForEach-Object { Write-Host $_ }
                exit 1
            }
        }
    }
    'update' {
        if ($commandArgs.Count -gt 0) {
            throw "unexpected argument: $($commandArgs[0])"
        }
        Invoke-NativeCommand pwsh -NoLogo -NoProfile -File "$dotfilesDir\scripts\update-dotfiles.ps1"
        Invoke-NativeCommand pwsh -NoLogo -NoProfile -File "$dotfilesDir\scripts\setup-jq.ps1"
        Invoke-NativeCommand gsudo pwsh -NoLogo -NonInteractive -File "$dotfilesDir\scripts\install.ps1"
        Invoke-NativeCommand pwsh -NoLogo -NoProfile -File "$dotfilesDir\scripts\setup-zellij.ps1"
        Invoke-NativeCommand gsudo pwsh -NoLogo -NonInteractive -File "$dotfilesDir\scripts\update-windows.ps1"
    }
    'winget' {
        $wingetDir = "$dotfilesDir\windows"
        $wingetAction = if ($commandArgs.Count -gt 0) { $commandArgs[0] } else { $null }
        $wingetArgs = @($commandArgs | Select-Object -Skip 1)

        switch ($wingetAction) {
            'apply' {
                # 共通オプションは動詞ゲートが検証済み。スクリプトのスイッチへ読み替える。
                $applyArgs = @()
                foreach ($argument in $wingetArgs) {
                    switch ($argument) {
                        '--no-prune' { $applyArgs += '-NoPrune' }
                        '--dry-run' { $applyArgs += '-DryRun' }
                        default { throw "unknown winget apply option: $argument" }
                    }
                }
                Invoke-NativeCommand pwsh -NoLogo -NoProfile -File "$wingetDir\apply_wingetpin.ps1" @applyArgs
            }
            'prune' {
                $pruneArgs = @('-PruneOnly')
                foreach ($argument in $wingetArgs) {
                    switch ($argument) {
                        '--dry-run' { $pruneArgs += '-DryRun' }
                        default { throw "unknown winget prune option: $argument" }
                    }
                }
                Invoke-NativeCommand pwsh -NoLogo -NoProfile -File "$wingetDir\apply_wingetpin.ps1" @pruneArgs
            }
            'diff' {
                $summary = $false
                $exitCodeRequested = $false
                foreach ($argument in $wingetArgs) {
                    switch ($argument) {
                        '--summary' { $summary = $true }
                        '--exit-code' { $exitCodeRequested = $true }
                        default { throw "unknown winget diff option: $argument" }
                    }
                }
                if ($summary) {
                    & pwsh -NoLogo -NoProfile -File "$wingetDir\diff_wingetpin.ps1" -Summary
                } else {
                    & pwsh -NoLogo -NoProfile -File "$wingetDir\diff_wingetpin.ps1"
                }
                # diff_wingetpin.ps1 の終了コード1は「差分あり」。既定では正常終了として扱い、
                # --exit-code のときだけ1を返す（2 以上はエラー）。
                if ($LASTEXITCODE -gt 1) { exit $LASTEXITCODE }
                if ($exitCodeRequested -and $LASTEXITCODE -eq 1) { exit 1 }
            }
            'cache' {
                if ($wingetArgs.Count -gt 0) {
                    throw "unexpected argument: $($wingetArgs[0])"
                }
                Invoke-NativeCommand pwsh -NoLogo -NoProfile -File "$wingetDir\update_wingetpin_cache.ps1"
            }
            default {
                throw "usage: dots winget {apply|diff|cache}"
            }
        }
    }
    'ghq' {
        $ghqAction = if ($commandArgs.Count -gt 0) { $commandArgs[0] } else { $null }
        if ($ghqAction -notin @('apply', 'diff', 'sync', 'merge', 'prune')) {
            throw "usage: dots ghq {apply|diff|sync|merge|prune}"
        }
        # 共通オプションは動詞ゲートが検証済み。--exit-code だけは dots 側で扱い、残りをスクリプトへ渡す。
        $ghqExitCodeRequested = $false
        $ghqPass = @()
        foreach ($argument in @($commandArgs | Select-Object -Skip 1)) {
            if ($argument -eq '--exit-code') {
                $ghqExitCodeRequested = $true
            } else {
                $ghqPass += $argument
            }
        }
        & pwsh -NoLogo -NoProfile -File "$dotfilesDir\ghq\keep-up-to-date.ps1" $ghqAction @ghqPass
        # diff の終了コード1は「差分あり」で、dots としては正常終了として扱う（2 以上はエラー）。
        # --exit-code のときだけ、差分ありを終了コード1で返す。
        if ($ghqAction -eq 'diff') {
            if ($LASTEXITCODE -gt 1) { exit $LASTEXITCODE }
            if ($ghqExitCodeRequested -and $LASTEXITCODE -eq 1) { exit 1 }
        } elseif ($LASTEXITCODE -gt 0) {
            exit $LASTEXITCODE
        }
    }
    { $_ -in @('ai', 'claude', 'codex', 'copilot') } {
        # 動詞ゲートが動詞・共通オプションを検証済み。--exit-code だけは dots 側で扱う。
        $aiAction = $commandArgs[0]
        $aiExitCodeRequested = $false
        $aiOptions = @()
        foreach ($argument in @($commandArgs | Select-Object -Skip 1)) {
            if ($argument -eq '--exit-code') {
                $aiExitCodeRequested = $true
            } else {
                $aiOptions += $argument
            }
        }

        $aiDiffFound = $false
        if ($commandName -eq 'ai') {
            foreach ($aiAgent in @('claude', 'codex')) {
                Write-Host "=== $aiAgent ==="
                if (Invoke-AiAgent -Agent $aiAgent -Action $aiAction -Options $aiOptions) { $aiDiffFound = $true }
                Write-Host
            }
        } elseif (Invoke-AiAgent -Agent $commandName -Action $aiAction -Options $aiOptions) {
            $aiDiffFound = $true
        }
        # diff の既定は差分があっても0。--exit-code のときだけ差分ありを終了コード1で返す。
        if ($aiExitCodeRequested -and $aiDiffFound) { exit 1 }
    }
    'verbs' {
        if ($commandArgs.Count -gt 0) {
            throw "unexpected argument: $($commandArgs[0])"
        }
        foreach ($domain in ($verbSpecs.Keys | Sort-Object)) {
            foreach ($verb in $verbs) {
                $state = Get-VerbState -Domain $domain -Verb $verb
                $reason = if ($state -eq 'na') { $verbNaReasons["${domain}:${verb}"] } else { '' }
                "$domain`t$verb`t$state`t$reason"
            }
        }
    }
    { $_ -in @('help', '-h', '--help') } {
        Show-Usage
    }
    default {
        throw "unknown command on Windows: $commandName"
    }
}
