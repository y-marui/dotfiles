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
  dots update
  dots winget {apply|diff|prune|cache}  # N/A: sync merge
  dots ghq    {apply|diff|sync|merge|prune}  # N/A: cache
  dots verbs
  dots help

Windowsでは status / update / winget / ghq を利用できます。
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

# ドメイン×動詞のテーブル。bin/unix/_dots-verbs.sh の _dots_domain_spec と同じ書式で、
# scripts/check-dots-verb-table.sh が両者の一致を検証する。
#   ok 実装済み / na 対象外（理由を $verbNaReasons に書く） / todo 未実装
$verbs = @('apply', 'diff', 'sync', 'merge', 'prune', 'cache')
$verbSpecs = @{
    'ghq'    = 'apply=ok diff=ok sync=ok merge=ok prune=ok cache=na'
    'winget' = 'apply=ok diff=ok sync=na merge=na prune=ok cache=ok'
}
$verbNaReasons = @{
    'ghq:cache'    = '実状態をGit configから直接読むためキャッシュ不要'
    'winget:sync'  = '宣言（windows/WingetPin）は理由コメント付きで人が編集する'
    'winget:merge' = '宣言（windows/WingetPin）は理由コメント付きで人が編集する'
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
        Show-DomainHelp -Domain $Domain
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
