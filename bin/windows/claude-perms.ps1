#!/usr/bin/env pwsh
# claude-perms: .claude/settings.local.json の permissions を整理するヘルパー（Windows / PowerShell 版）
#
# bin/unix/claude-perms（bash + jq）の PowerShell への移植。サブコマンドの詳細・
# 正規化規則・「カバーされている」の判定ルールは bin/unix/claude-perms 冒頭のコメントを
# 正本とする（挙動は同じに保つ。差分を生む変更は両方に入れる）。
#
# 使い方:
#   claude-perms format [DIR...]       permissions.allow/deny/ask を正規化・ソート・重複削除し、
#                                       グローバル設定でカバー済みのallowを削除して書き戻す
#   claude-perms check [DIR...]        整理が必要かどうかだけ確認する（書き換えない）
#   claude-perms candidates [DIR...] [--json]
#                                       グローバルにもpathRuleにも無いローカルallowを一覧表示する
#   claude-perms format-global         ~/.claude/settings.json と claude-perms.json を整理する
#   claude-perms remove <pattern> [DIR...] [--glob] [--apply|-y]
#   claude-perms remove --json <FILE|-> [--apply|-y]
#   claude-perms remove-global <pattern> [--glob] [--apply|-y]
#   claude-perms merge [DIR...]        pathRulesに一致するallowを settings.local.json へ追記する
#   claude-perms apply [DIR...]        pathRulesに一致するallowで settings.local.json を置き換える
#
# オプション:
#   -h, --help      ヘルプを表示
#   -v, --verbose   settings.local.json が無い DIR をスキップした旨も表示する
#
# 設定: ~/.claude/claude-perms.json（forbiddenAllow・pathRules。Claude Code 本体は読まない）。
# pathGlob は bash の glob 相当（* ? [..]）を DIR の絶対パスに対して評価する。`~` は
# ホームディレクトリに展開し、区切りは `/` に揃え、大文字小文字は区別しない（Windows のため）。
#
# 終了コード: 0=成功（check は整理済み）, 1=失敗（check は未整理）。
# zsh の cd フック連携（claude-perms shell）は zsh 専用のため、この版にはない。

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# 出力がリダイレクトされる場合（パイプ・テスト）は UTF-8 に揃える。対話端末では既定のまま
if ([Console]::IsOutputRedirected) { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) }

function Show-Help {
    $lines = @(Get-Content -LiteralPath $PSCommandPath)
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line -eq '') { break }
        Write-Output ($line -replace '^#\s?', '')
    }
}

function Stop-WithError([string]$Message) {
    [Console]::Error.WriteLine("error: $Message")
    exit 1
}

# ---------- 引数解析 ----------
$script:Verbose = $false
$cliArgs = New-Object System.Collections.Generic.List[string]
foreach ($a in $args) {
    if ($a -eq '-v' -or $a -eq '--verbose') { $script:Verbose = $true } else { $cliArgs.Add([string]$a) }
}
if ($cliArgs.Count -gt 0 -and ($cliArgs[0] -eq '-h' -or $cliArgs[0] -eq '--help')) {
    Show-Help
    exit 0
}

# ---------- 小さなユーティリティ ----------
$script:OrdinalComparer = [System.StringComparer]::Ordinal
# エラーメッセージのためバッファ（Test-JsonFileValid が追加し、Invoke-OverDirs / 末尾で出力する）
$script:Diag = New-Object System.Collections.Generic.List[string]

# 順序付き（Ordinal）・重複なしの string[] を返す（jq の unique 相当）。
function Get-UniqueSorted([string[]]$Items) {
    $set = New-Object 'System.Collections.Generic.SortedSet[string]' -ArgumentList (, $script:OrdinalComparer)
    foreach ($i in @($Items)) { if ($null -ne $i) { [void]$set.Add($i) } }
    return , ([string[]]@($set))
}

# CLAUDE_PERMS_HOME はテスト用の上書き（unix 版の HOME 差し替えに相当。pwsh の $HOME は環境変数で変えられない）
function Get-HomeDir {
    if ($env:CLAUDE_PERMS_HOME) { return $env:CLAUDE_PERMS_HOME }
    return $HOME
}

function Get-LocalSettingsFile([string]$Dir) {
    if ([string]::IsNullOrEmpty($Dir)) { $Dir = '.' }
    return ($Dir.TrimEnd('/', '\') + '/.claude/settings.local.json')
}
function Get-GlobalSettingsFile { return (Join-Path (Get-HomeDir) '.claude/settings.json') }
function Get-ClaudePermsConfigFile { return (Join-Path (Get-HomeDir) '.claude/claude-perms.json') }

# シンボリックリンクなら実体パスを返す（書き戻しでリンクが実ファイルに置き換わらないように）。
function Resolve-WriteTarget([string]$File) {
    $item = Get-Item -LiteralPath $File -Force
    if ($item.LinkType) {
        $t = $item.ResolveLinkTarget($true)
        if ($t) { return $t.FullName }
    }
    return $item.FullName
}

# JSON ファイルを PSCustomObject として読む。壊れていれば $null を返し、理由を $script:JsonError に入れる。
function Read-JsonFile([string]$File) {
    $script:JsonError = $null
    try {
        $text = [System.IO.File]::ReadAllText($File)
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return ($text | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        $script:JsonError = $_.Exception.Message
        return $null
    }
}

# 検証。壊れていれば報告して $false。
function Test-JsonFileValid([string]$File) {
    $text = [System.IO.File]::ReadAllText($File)
    try {
        [void]($text | ConvertFrom-Json -ErrorAction Stop)
        return $true
    } catch {
        # 戻り値（bool）に混ざらないよう一旦ためる。DIR 単位の出力へは Invoke-OverDirs が合流させる
        # （unix 版は stderr を 2>&1 で DIR の出力に合流させるのと同じ見え方にする）
        $script:Diag.Add("error: 無効なJSON: $File")
        $script:Diag.Add("  $($_.Exception.Message)")
        return $false
    }
}

function Write-JsonFile([string]$File, $Object) {
    $target = Resolve-WriteTarget $File
    $json = ($Object | ConvertTo-Json -Depth 100)
    $tmp = "$target.$([System.IO.Path]::GetRandomFileName())"
    [System.IO.File]::WriteAllText($tmp, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $target -Force
}

# オブジェクトにプロパティを設定する（無ければ追加する）。
function Set-Prop($Object, [string]$Name, $Value) {
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}
function Test-HasProp($Object, [string]$Name) {
    return ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name])
}
function Get-StringArray($Object, [string]$Name) {
    if (-not (Test-HasProp $Object $Name) -or $null -eq $Object.$Name) { return , ([string[]]@()) }
    return , ([string[]]@($Object.$Name | ForEach-Object { [string]$_ }))
}
function Get-PermArray($Doc, [string]$Key) {
    if (-not (Test-HasProp $Doc 'permissions') -or $null -eq $Doc.permissions) { return , ([string[]]@()) }
    return , (Get-StringArray $Doc.permissions $Key)
}

# ---------- ルールの解釈 ----------
function Split-Rule([string]$Rule) {
    if ($Rule -match '^([A-Za-z_]+)\((.*)\)$') {
        return [pscustomobject]@{ Tool = $Matches[1]; Spec = $Matches[2] }
    }
    return [pscustomobject]@{ Tool = $Rule; Spec = '' }
}

# 末尾 wildcard を剥がす。剥がせなければ $null。
function Get-WildcardInfo([string]$Spec) {
    if ($Spec.EndsWith(':*', [StringComparison]::Ordinal)) {
        return [pscustomobject]@{ Prefix = $Spec.Substring(0, $Spec.Length - 2); WordBoundary = $true }
    }
    if ($Spec.EndsWith(' *', [StringComparison]::Ordinal)) {
        return [pscustomobject]@{ Prefix = $Spec.Substring(0, $Spec.Length - 2); WordBoundary = $true }
    }
    if ($Spec.EndsWith('*', [StringComparison]::Ordinal)) {
        return [pscustomobject]@{ Prefix = $Spec.Substring(0, $Spec.Length - 1); WordBoundary = $false }
    }
    return $null
}

function Test-CoversMatchCmd([string]$LCmd, [string]$GPrefix, [bool]$WordBoundary) {
    if ($WordBoundary) {
        return ($LCmd -ceq $GPrefix -or $LCmd.StartsWith("$GPrefix ", [StringComparison]::Ordinal))
    }
    return $LCmd.StartsWith($GPrefix, [StringComparison]::Ordinal)
}

function Test-CoversImpl([string]$GlobalRule, [string]$LocalRule, [bool]$Lenient) {
    if ($GlobalRule -ceq $LocalRule) { return $true }
    $g = Split-Rule $GlobalRule
    $l = Split-Rule $LocalRule
    if ($g.Tool -cne $l.Tool) { return $false }
    if ($g.Spec -eq '') { return $true }

    $gw = Get-WildcardInfo $g.Spec
    if ($null -eq $gw) { return $false }

    $lCmd = $l.Spec
    $lw = Get-WildcardInfo $l.Spec
    if ($null -ne $lw) { $lCmd = $lw.Prefix }

    if (Test-CoversMatchCmd $lCmd $gw.Prefix $gw.WordBoundary) { return $true }
    if ($Lenient -and $g.Tool -ceq 'Bash' -and $lCmd.StartsWith('run-quiet ', [StringComparison]::Ordinal)) {
        if (Test-CoversMatchCmd $lCmd.Substring('run-quiet '.Length) $gw.Prefix $gw.WordBoundary) { return $true }
    }
    return $false
}
function Test-Covers([string]$G, [string]$L) { return (Test-CoversImpl $G $L $false) }
function Test-CoversLenient([string]$G, [string]$L) { return (Test-CoversImpl $G $L $true) }

# "Tool(prefix *)" を "Tool(prefix:*)" へ。Bash/PowerShell 以外は触らない。
function ConvertTo-NormalizedRule([string]$Rule) {
    $r = Split-Rule $Rule
    if ($r.Tool -cne 'Bash' -and $r.Tool -cne 'PowerShell') { return $Rule }
    if ($r.Spec.EndsWith(' *', [StringComparison]::Ordinal)) {
        return ('{0}({1}:*)' -f $r.Tool, $r.Spec.Substring(0, $r.Spec.Length - 2))
    }
    return $Rule
}

function ConvertTo-NormalizedSet([string[]]$Entries) {
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($e in @($Entries)) {
        if (-not [string]::IsNullOrEmpty($e)) { $list.Add((ConvertTo-NormalizedRule $e)) }
    }
    return , (Get-UniqueSorted $list.ToArray())
}

function Get-RunQuietVariant([string]$Rule) {
    $r = Split-Rule $Rule
    if ($r.Tool -cne 'Bash') { return $null }
    $w = Get-WildcardInfo $r.Spec
    if ($null -eq $w -or -not $w.WordBoundary) { return $null }
    if ($w.Prefix -ceq 'run-quiet' -or $w.Prefix.StartsWith('run-quiet ', [StringComparison]::Ordinal)) { return $null }
    return ('Bash(run-quiet {0}:*)' -f $w.Prefix)
}

function Expand-RunQuiet([string[]]$Lines) {
    $result = New-Object System.Collections.Generic.List[string]
    $result.AddRange([string[]]@($Lines))
    foreach ($line in @($Lines)) {
        $v = Get-RunQuietVariant $line
        if ([string]::IsNullOrEmpty($v)) { continue }
        if (@($Lines) -ccontains $v) { continue }
        $result.Add($v)
    }
    return , ([string[]]$result.ToArray())
}

# 同じ集合内の他エントリに包含されるエントリを除く（unix 版 _dedupe_covered_within と同じ順序規則）。
function Remove-CoveredWithin([string[]]$Lines) {
    $arr = New-Object System.Collections.Generic.List[string]
    foreach ($l in @($Lines)) { if (-not [string]::IsNullOrEmpty($l)) { $arr.Add($l) } }
    for ($i = 0; $i -lt $arr.Count; $i++) {
        if ([string]::IsNullOrEmpty($arr[$i])) { continue }
        $covered = $false
        for ($j = 0; $j -lt $arr.Count; $j++) {
            if ($i -eq $j) { continue }
            if ([string]::IsNullOrEmpty($arr[$j])) { continue }
            if ($arr[$i] -cne $arr[$j] -and (Test-Covers $arr[$j] $arr[$i])) { $covered = $true; break }
        }
        if ($covered) { $arr[$i] = '' }
    }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($a in $arr) { if (-not [string]::IsNullOrEmpty($a)) { $out.Add($a) } }
    return , ([string[]]$out.ToArray())
}

# ---------- claude-perms.json ----------
# forbiddenAllow（正規化済み）を返す。壊れていれば $null（呼び出し側は中断する）。ファイルが無ければ空。
function Get-ForbiddenAllow {
    $config = Get-ClaudePermsConfigFile
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { return , ([string[]]@()) }
    if (-not (Test-JsonFileValid $config)) { return $null }
    $doc = Read-JsonFile $config
    if ($null -eq $doc) { return , ([string[]]@()) }
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($e in (Get-StringArray $doc 'forbiddenAllow')) {
        if (-not [string]::IsNullOrEmpty($e)) { $list.Add((ConvertTo-NormalizedRule $e)) }
    }
    return , ([string[]]$list.ToArray())
}

# ---------- format の計算 ----------
function Get-ClassifiedAllow([string]$LocalFile, [string]$GlobalFile) {
    $globalAllow = @()
    if (Test-Path -LiteralPath $GlobalFile -PathType Leaf) {
        $gd = Read-JsonFile $GlobalFile
        if ($null -ne $gd) { foreach ($x in (Get-PermArray $gd 'allow')) { if ($x) { $globalAllow += $x } } }
    }
    $ld = Read-JsonFile $LocalFile
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($entry in (Get-PermArray $ld 'allow')) {
        if ([string]::IsNullOrEmpty($entry)) { continue }
        $covering = $null
        foreach ($g in $globalAllow) {
            if (Test-Covers $g $entry) { $covering = $g; break }
        }
        if ($null -ne $covering) {
            $result.Add([pscustomobject]@{ Tag = 'REMOVED'; Entry = $entry; Covering = $covering })
        } else {
            $result.Add([pscustomobject]@{ Tag = 'KEEP'; Entry = $entry; Covering = '' })
        }
    }
    return , ($result.ToArray())
}

function Test-ArraysEqual([string[]]$A, [string[]]$B) {
    $a = @($A); $b = @($B)
    if ($a.Count -ne $b.Count) { return $false }
    for ($i = 0; $i -lt $a.Count; $i++) { if ($a[$i] -cne $b[$i]) { return $false } }
    return $true
}

# 整理結果を計算する。失敗（claude-perms.json 破損）は $null。
function Get-FormatResult([string]$File, [string]$GlobalFile) {
    $forbidden = Get-ForbiddenAllow
    if ($null -eq $forbidden) { return $null }
    $doc = Read-JsonFile $File

    $classified = @()
    $kept = New-Object System.Collections.Generic.List[string]
    $forbiddenRemoved = New-Object System.Collections.Generic.List[string]
    $candidatesIn = @()
    if (-not [string]::IsNullOrEmpty($GlobalFile)) {
        $classified = @(Get-ClassifiedAllow $File $GlobalFile | ForEach-Object { $_ })
        $candidatesIn = @($classified | Where-Object { $_.Tag -eq 'KEEP' } | ForEach-Object { $_.Entry })
    } else {
        $candidatesIn = @(Get-PermArray $doc 'allow' | ForEach-Object { $_ } | Where-Object { $_ })
    }
    foreach ($entry in $candidatesIn) {
        if (@($forbidden) -ccontains (ConvertTo-NormalizedRule $entry)) { $forbiddenRemoved.Add($entry) }
        else { $kept.Add($entry) }
    }

    $beforeExpand = [string[]]$kept.ToArray()
    $expanded = Expand-RunQuiet $beforeExpand
    $runQuietAdded = New-Object System.Collections.Generic.List[string]
    foreach ($l in $expanded) {
        if ([string]::IsNullOrEmpty($l)) { continue }
        if ($beforeExpand -ccontains $l) { continue }
        $runQuietAdded.Add($l)
    }

    $deduped = Remove-CoveredWithin $expanded
    $selfCovered = New-Object System.Collections.Generic.List[string]
    foreach ($l in $expanded) {
        if ([string]::IsNullOrEmpty($l)) { continue }
        if ($deduped -ccontains $l) { continue }
        $selfCovered.Add($l)
    }

    $newAllow = ConvertTo-NormalizedSet $deduped
    $newDeny = ConvertTo-NormalizedSet (Get-PermArray $doc 'deny')
    $newAsk = ConvertTo-NormalizedSet (Get-PermArray $doc 'ask')

    # 変更有無: 既に存在するキーだけ比較する（unix 版は存在するキーにだけ新配列を書き戻す）
    $changed = $false
    $hasPerm = (Test-HasProp $doc 'permissions') -and $null -ne $doc.permissions
    if ($hasPerm) {
        foreach ($pair in @(@('allow', $newAllow), @('deny', $newDeny), @('ask', $newAsk))) {
            if (Test-HasProp $doc.permissions $pair[0]) {
                if (-not (Test-ArraysEqual (Get-StringArray $doc.permissions $pair[0]) $pair[1])) { $changed = $true }
            }
        }
    }

    return [pscustomobject]@{
        Changed          = $changed
        NewAllow         = $newAllow
        NewDeny          = $newDeny
        NewAsk           = $newAsk
        Classified       = $classified
        ForbiddenRemoved = $forbiddenRemoved.ToArray()
        RunQuietAdded    = $runQuietAdded.ToArray()
        SelfCovered      = $selfCovered.ToArray()
    }
}

function Write-FormatResult([string]$File, $Result) {
    $doc = Read-JsonFile $File
    if (Test-HasProp $doc 'permissions') {
        if (Test-HasProp $doc.permissions 'allow') { $doc.permissions.allow = $Result.NewAllow }
        if (Test-HasProp $doc.permissions 'deny') { $doc.permissions.deny = $Result.NewDeny }
        if (Test-HasProp $doc.permissions 'ask') { $doc.permissions.ask = $Result.NewAsk }
    }
    Write-JsonFile $File $doc
}

function Test-EmptyPermissionsOnly([string]$File) {
    $doc = Read-JsonFile $File
    if ($null -eq $doc) { return $false }
    $keys = @($doc.PSObject.Properties.Name)
    if ($keys.Count -ne 1 -or $keys[0] -cne 'permissions') { return $false }
    $pk = @($doc.permissions.PSObject.Properties.Name)
    if ($pk.Count -ne 1 -or $pk[0] -cne 'allow') { return $false }
    return ((Get-StringArray $doc.permissions 'allow').Count -eq 0)
}

function Invoke-PruneIfEmpty([string]$File) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return }
    if (-not (Test-EmptyPermissionsOnly $File)) { return }
    Remove-Item -LiteralPath $File -Force
    Write-Output "空になったため削除: $File"
    $dir = Split-Path -Parent $File
    if ((Test-Path -LiteralPath $dir -PathType Container) -and -not (Get-ChildItem -LiteralPath $dir -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $dir -Force
        Write-Output "空になったため削除: $dir"
    }
}

# ---------- 複数 DIR の共通ランナー ----------
# 各 DIR の出力をまとめて、何か出力した DIR の間にだけ空行を挟む。1件でも失敗すれば $false。
function Invoke-OverDirs([scriptblock]$Fn, [string[]]$Dirs) {
    $dirs = @($Dirs)
    if ($dirs.Count -eq 0) { $dirs = @('.') }
    $failed = $false
    $printedAny = $false
    foreach ($d in $dirs) {
        $script:OneRc = 0
        $out = @(& $Fn $d)
        if ($script:Diag.Count -gt 0) {
            $out = @($script:Diag.ToArray()) + $out
            $script:Diag.Clear()
        }
        if ($script:OneRc -ne 0) { $failed = $true }
        if ($out.Count -gt 0) {
            if ($printedAny) { Write-Output '' }
            $out | ForEach-Object { Write-Output $_ }
            $printedAny = $true
        }
    }
    return (-not $failed)
}

# ---------- format ----------
function Invoke-FormatOne([string]$Dir) {
    if ([string]::IsNullOrEmpty($Dir)) { $Dir = '.' }
    $file = Get-LocalSettingsFile $Dir
    $globalFile = Get-GlobalSettingsFile
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        if ($script:Verbose) { Write-Output "skip（settings.local.json なし）: $file" }
        return
    }
    if (-not (Test-JsonFileValid $file)) { $script:OneRc = 1; return }
    $res = Get-FormatResult $file $globalFile
    if ($null -eq $res) { $script:OneRc = 1; return }

    if (-not $res.Changed) {
        Write-Output "変更なし: $file"
    } else {
        Write-FormatResult $file $res
        Write-Output "整理しました: $file"
        $removed = @($res.Classified | Where-Object { $_.Tag -eq 'REMOVED' } |
                ForEach-Object { "$($_.Entry)`t$($_.Covering)" } | Sort-Object -Unique -CaseSensitive)
        if ($removed.Count -gt 0) {
            Write-Output 'グローバル設定でカバー済みのため削除:'
            foreach ($r in $removed) {
                $p = $r -split "`t", 2
                Write-Output "  $($p[0])  ($($p[1]) でカバー)"
            }
        }
        if ($res.ForbiddenRemoved.Count -gt 0) {
            Write-Output '禁止エントリ（claude-perms.json）のため削除:'
            $res.ForbiddenRemoved | ForEach-Object { Write-Output "  $_" }
        }
        if ($res.RunQuietAdded.Count -gt 0) {
            Write-Output 'run-quiet修飾版を自動追加:'
            $res.RunQuietAdded | ForEach-Object { Write-Output "  $_" }
        }
        if ($res.SelfCovered.Count -gt 0) {
            Write-Output '同じファイル内の他のallowエントリでカバー済みのため削除:'
            $res.SelfCovered | ForEach-Object { Write-Output "  $_" }
        }
    }
    Invoke-PruneIfEmpty $file
}

function Invoke-Format([string[]]$Dirs) {
    return (Invoke-OverDirs { param($d) Invoke-FormatOne $d } $Dirs)
}

# ---------- check ----------
function Invoke-CheckOne([string]$Dir) {
    if ([string]::IsNullOrEmpty($Dir)) { $Dir = '.' }
    $file = Get-LocalSettingsFile $Dir
    $globalFile = Get-GlobalSettingsFile
    if (-not (Test-Path -LiteralPath ($Dir.TrimEnd('/', '\') + '/.claude') -PathType Container)) {
        Write-Output ".claude/ が見つかりません: $Dir"
        $script:OneRc = 1
        return
    }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Write-Output '[.claude] found（settings.local.json なし）'
        return
    }
    if (-not (Test-JsonFileValid $file)) { $script:OneRc = 1; return }
    $res = Get-FormatResult $file $globalFile
    if ($null -eq $res) { $script:OneRc = 1; return }
    if ($res.Changed) {
        Write-Output '[.claude] found — permissions が未整理です（claude-perms format で整理）'
        $script:OneRc = 1
        return
    }
    if (Test-EmptyPermissionsOnly $file) {
        Write-Output '[.claude] found — permissions が空です（claude-perms format で削除）'
        $script:OneRc = 1
        return
    }
    Write-Output '[.claude] found — permissions は整理済みです'
}

function Invoke-Check([string[]]$Dirs) {
    return (Invoke-OverDirs { param($d) Invoke-CheckOne $d } $Dirs)
}

# ---------- pathRules ----------
function Get-AbsolutePath([string]$Dir) {
    $p = (Resolve-Path -LiteralPath $Dir).ProviderPath
    $item = Get-Item -LiteralPath $p -Force
    if ($item.LinkType) {
        $t = $item.ResolveLinkTarget($true)
        if ($t) { return $t.FullName }
    }
    return $p
}

# bash の glob（* ? [..]）を正規表現へ。`*` は `/` も含めて任意の文字列に一致する（bash の [[ == ]] と同じ）。
function ConvertTo-GlobRegex([string]$Glob) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('^')
    $i = 0
    while ($i -lt $Glob.Length) {
        $c = $Glob[$i]
        switch ($c) {
            '*' { [void]$sb.Append('.*') }
            '?' { [void]$sb.Append('.') }
            '[' {
                $end = $Glob.IndexOf(']', $i + 1)
                if ($end -gt $i + 1) {
                    $body = $Glob.Substring($i + 1, $end - $i - 1)
                    if ($body.StartsWith('!')) { $body = '^' + $body.Substring(1) }
                    [void]$sb.Append('[').Append($body.Replace('\', '\\')).Append(']')
                    $i = $end
                } else {
                    [void]$sb.Append('\[')
                }
            }
            default { [void]$sb.Append([regex]::Escape([string]$c)) }
        }
        $i++
    }
    [void]$sb.Append('$')
    return $sb.ToString()
}

# pathRules を ({Glob; Allow[]}) の配列で返す。壊れていれば $null。ファイルが無ければ空。
function Get-PathRules {
    $config = Get-ClaudePermsConfigFile
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { return , @() }
    if (-not (Test-JsonFileValid $config)) { return $null }
    $doc = Read-JsonFile $config
    $out = New-Object System.Collections.Generic.List[object]
    if ($null -eq $doc -or -not (Test-HasProp $doc 'pathRules') -or $null -eq $doc.pathRules) { return , @() }
    foreach ($r in @($doc.pathRules)) {
        $globs = @()
        if (Test-HasProp $r 'pathGlob') { $globs = @($r.pathGlob | ForEach-Object { [string]$_ }) }
        $allow = Get-StringArray $r 'allow'
        foreach ($g in $globs) { $out.Add([pscustomobject]@{ Glob = $g; Allow = $allow }) }
    }
    return , ($out.ToArray())
}

# abs_dir に一致する pathRule の allow（生文字列・重複あり）。壊れていれば $null。
function Get-MatchedPathRuleAllow([string]$AbsDir) {
    $rules = Get-PathRules
    if ($null -eq $rules) { return $null }
    $homeDir = (Get-HomeDir).Replace('\', '/')
    $dir = $AbsDir.Replace('\', '/')
    $matched = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($rules)) {
        if ([string]::IsNullOrEmpty($r.Glob)) { continue }
        $glob = $r.Glob.Replace('\', '/')
        if ($glob.StartsWith('~')) { $glob = $homeDir + $glob.Substring(1) }
        if ($dir -match (ConvertTo-GlobRegex $glob)) {
            foreach ($a in $r.Allow) { if (-not [string]::IsNullOrEmpty($a)) { $matched.Add($a) } }
        }
    }
    return , ([string[]]$matched.ToArray())
}

# 戻り値: 0=カバー済み / 1=未カバー / 2=判定失敗
function Get-CoveredByPathRule([string]$Entry, [string]$AbsDir) {
    $allow = Get-MatchedPathRuleAllow $AbsDir
    if ($null -eq $allow) { return 2 }
    foreach ($pr in @($allow)) {
        if ([string]::IsNullOrEmpty($pr)) { continue }
        if (Test-CoversLenient $pr $Entry) { return 0 }
    }
    return 1
}

# ---------- candidates ----------
# 戻り値: $null=失敗, それ以外は Skip/LocalFile/GlobalFile/LocalCount/GlobalCount/Entries を持つオブジェクト
function Get-Candidates([string]$Dir) {
    if ([string]::IsNullOrEmpty($Dir)) { $Dir = '.' }
    $localFile = Get-LocalSettingsFile $Dir
    $globalFile = Get-GlobalSettingsFile
    if (-not (Test-Path -LiteralPath $localFile -PathType Leaf)) {
        return [pscustomobject]@{ Skip = $true; LocalFile = $localFile; GlobalFile = $globalFile; LocalCount = 0; GlobalCount = $null; Entries = @() }
    }
    if (-not (Test-JsonFileValid $localFile)) { return $null }
    $absDir = Get-AbsolutePath $Dir
    $classified = @(Get-ClassifiedAllow $localFile $globalFile | ForEach-Object { $_ })
    $raw = New-Object System.Collections.Generic.List[string]
    foreach ($c in $classified) {
        if ($c.Tag -ne 'KEEP') { continue }
        $rc = Get-CoveredByPathRule $c.Entry $absDir
        if ($rc -eq 2) { return $null }
        if ($rc -eq 0) { continue }
        $raw.Add($c.Entry)
    }
    $entries = Get-UniqueSorted $raw.ToArray()
    $ld = Read-JsonFile $localFile
    $localCount = (Get-UniqueSorted (Get-PermArray $ld 'allow')).Count
    $globalCount = $null
    if (Test-Path -LiteralPath $globalFile -PathType Leaf) {
        $gd = Read-JsonFile $globalFile
        $globalCount = (Get-UniqueSorted (Get-PermArray $gd 'allow')).Count
    }
    return [pscustomobject]@{ Skip = $false; LocalFile = $localFile; GlobalFile = $globalFile; LocalCount = $localCount; GlobalCount = $globalCount; Entries = @($entries) }
}

function Invoke-CandidatesOne([string]$Dir) {
    $c = Get-Candidates $Dir
    if ($null -eq $c) { $script:OneRc = 1; return }
    if ($c.Skip) {
        if ($script:Verbose) { Write-Output "skip（settings.local.json なし）: $($c.LocalFile)" }
        return
    }
    $count = @($c.Entries).Count
    if ($count -eq 0 -and -not $script:Verbose) { return }

    Write-Output "ローカル: $($c.LocalFile) (allow: $($c.LocalCount)件)"
    if ($null -ne $c.GlobalCount) { Write-Output "グローバル: $($c.GlobalFile) (allow: $($c.GlobalCount)件)" }
    else { Write-Output "グローバル: $($c.GlobalFile) (未作成)" }

    if ($count -eq 0) {
        Write-Output '移管候補はありません（ローカルのallowは空、またはすべてグローバルのルール・DIRに一致するpathRuleでカバー済みです）'
        return
    }
    Write-Output "移管候補 (${count}件, グローバルのルール・pathRuleいずれでも未カバー):"
    $c.Entries | ForEach-Object { Write-Output "  $_" }
    Write-Output ''
    Write-Output "$($c.GlobalFile) へ手動で追記・整理してください（このコマンドは一覧表示のみで自動追加はしません）"
}

function Invoke-Candidates([string[]]$CmdArgs) {
    $json = $false
    $rest = New-Object System.Collections.Generic.List[string]
    foreach ($a in $CmdArgs) { if ($a -eq '--json') { $json = $true } else { $rest.Add($a) } }

    if (-not $json) { return (Invoke-OverDirs { param($d) Invoke-CandidatesOne $d } $rest.ToArray()) }

    $dirs = $rest.ToArray()
    if ($dirs.Count -eq 0) { $dirs = @('.') }
    $objs = New-Object System.Collections.Generic.List[object]
    $failed = $false
    foreach ($d in $dirs) {
        $c = Get-Candidates $d
        if ($null -eq $c) { $failed = $true; continue }
        if ($c.Skip -or @($c.Entries).Count -eq 0) { continue }
        $objs.Add([ordered]@{ target = $d; allow = [string[]]@($c.Entries) })
    }
    if ($objs.Count -eq 0) { Write-Output '[]' }
    else { Write-Output (ConvertTo-Json -InputObject @($objs.ToArray()) -Depth 10) }
    return (-not $failed)
}

# ---------- claude-perms.json の整理 ----------
function Invoke-FormatClaudePermsConfig {
    $config = Get-ClaudePermsConfigFile
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { return $true }
    if (-not (Test-JsonFileValid $config)) { return $false }
    $doc = Read-JsonFile $config

    $before = [ordered]@{
        forbiddenAllow = (Get-StringArray $doc 'forbiddenAllow')
        pathRules      = @(if (Test-HasProp $doc 'pathRules') { $doc.pathRules })
    } | ConvertTo-Json -Depth 100 -Compress

    $newForbidden = ConvertTo-NormalizedSet (Get-StringArray $doc 'forbiddenAllow')
    $newRules = New-Object System.Collections.Generic.List[object]
    if (Test-HasProp $doc 'pathRules') {
        foreach ($r in @($doc.pathRules)) {
            $allow = Remove-CoveredWithin (Get-StringArray $r 'allow')
            $newAllow = ConvertTo-NormalizedSet $allow
            $newRules.Add([pscustomobject][ordered]@{ pathGlob = $r.pathGlob; allow = $newAllow })
        }
    }
    # 配列 pathGlob は先頭要素をソートキーにする（安定ソート）
    $indexed = 0..([Math]::Max($newRules.Count, 1) - 1) | Where-Object { $_ -lt $newRules.Count } | ForEach-Object {
        $g = $newRules[$_].pathGlob
        $key = if ($g -is [System.Array]) { [string]$g[0] } else { [string]$g }
        [pscustomobject]@{ Index = $_; Key = $key }
    }
    $sorted = @($indexed | Sort-Object -Property @{ Expression = { $_.Key }; Ascending = $true }, Index | ForEach-Object { $newRules[$_.Index] })

    Set-Prop $doc 'forbiddenAllow' $newForbidden
    Set-Prop $doc 'pathRules' $sorted

    $after = [ordered]@{
        forbiddenAllow = @($doc.forbiddenAllow)
        pathRules      = @($doc.pathRules)
    } | ConvertTo-Json -Depth 100 -Compress

    if ($before -ceq $after) {
        Write-Output "変更なし: $config"
        return $true
    }
    Write-JsonFile $config $doc
    Write-Output "整理しました: $config"
    return $true
}

function Invoke-FormatGlobal([string[]]$CmdArgs) {
    if (@($CmdArgs).Count -ne 0) { Stop-WithError 'format-global はDIR引数を取りません' }
    $file = Get-GlobalSettingsFile
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Write-Output "error: not found: $file"
        return $false
    }
    if (-not (Test-JsonFileValid $file)) { return $false }
    $res = Get-FormatResult $file ''
    if ($null -eq $res) { return $false }
    if (-not $res.Changed) {
        Write-Output "変更なし: $file"
    } else {
        Write-FormatResult $file $res
        Write-Output "整理しました: $file"
        if ($res.ForbiddenRemoved.Count -gt 0) {
            Write-Output '禁止エントリ（claude-perms.json）のため削除:'
            $res.ForbiddenRemoved | ForEach-Object { Write-Output "  $_" }
        }
        if ($res.RunQuietAdded.Count -gt 0) {
            Write-Output 'run-quiet修飾版を自動追加:'
            $res.RunQuietAdded | ForEach-Object { Write-Output "  $_" }
        }
        if ($res.SelfCovered.Count -gt 0) {
            Write-Output '同じファイル内の他のallowエントリでカバー済みのため削除:'
            $res.SelfCovered | ForEach-Object { Write-Output "  $_" }
        }
    }
    return (Invoke-FormatClaudePermsConfig)
}

# ---------- remove ----------
function Test-PatternMatch([string]$Entry, [string]$Pattern, [bool]$Glob) {
    if ($Glob) {
        if ($Entry -cmatch (ConvertTo-GlobRegex $Pattern)) { return $true }
        return ((ConvertTo-NormalizedRule $Entry) -cmatch (ConvertTo-GlobRegex (ConvertTo-NormalizedRule $Pattern)))
    }
    return ((ConvertTo-NormalizedRule $Entry) -ceq (ConvertTo-NormalizedRule $Pattern))
}

# $MatchFn: 引数1つ（エントリ）を取り一致で $true を返すスクリプトブロック。
function Invoke-RemoveFromFile([string]$File, [scriptblock]$MatchFn, [bool]$Apply) {
    $doc = Read-JsonFile $File
    $report = New-Object System.Collections.Generic.List[string]
    $kept = @{}
    foreach ($key in @('allow', 'deny', 'ask')) {
        $k = New-Object System.Collections.Generic.List[string]
        foreach ($e in (Get-PermArray $doc $key)) {
            if ([string]::IsNullOrEmpty($e)) { continue }
            if (& $MatchFn $e) { $report.Add("  [$key] $e") } else { $k.Add($e) }
        }
        $kept[$key] = [string[]]$k.ToArray()
    }
    if ($report.Count -eq 0) {
        Write-Output "一致なし: $File"
        return
    }
    if (-not $Apply) {
        Write-Output "[dry-run] 一致（--apply で削除）: $File"
        $report | ForEach-Object { Write-Output $_ }
        return
    }
    if (Test-HasProp $doc 'permissions') {
        foreach ($key in @('allow', 'deny', 'ask')) {
            if (Test-HasProp $doc.permissions $key) { $doc.permissions.$key = $kept[$key] }
        }
    }
    Write-JsonFile $File $doc
    Write-Output "削除しました: $File"
    $report | ForEach-Object { Write-Output $_ }
}

function Invoke-RemoveOne([string]$Dir, [scriptblock]$MatchFn, [bool]$Apply) {
    if ([string]::IsNullOrEmpty($Dir)) { $Dir = '.' }
    $file = Get-LocalSettingsFile $Dir
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        if ($script:Verbose) { Write-Output "skip（settings.local.json なし）: $file" }
        return
    }
    if (-not (Test-JsonFileValid $file)) { $script:OneRc = 1; return }
    Invoke-RemoveFromFile $file $MatchFn $Apply
    if ($Apply) { Invoke-PruneIfEmpty $file }
}

function Invoke-RemoveJson([string[]]$CmdArgs, [bool]$Apply) {
    $rest = @($CmdArgs)
    if ($rest.Count -eq 0) { Stop-WithError 'usage: claude-perms remove --json <FILE|-> [--apply]' }
    if ($rest.Count -ne 1) { Stop-WithError 'remove --json はFILE以外の引数（DIR等）を取りません' }
    $src = $rest[0]
    if ($src -eq '-') { $content = [Console]::In.ReadToEnd() }
    else {
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { Stop-WithError "JSONファイルが見つかりません: $src" }
        $content = [System.IO.File]::ReadAllText($src)
    }
    try { $items = @($content | ConvertFrom-Json -ErrorAction Stop) }
    catch {
        Write-Output "error: 無効なJSON: $src"
        Write-Output "  $($_.Exception.Message)"
        return $false
    }

    $failed = $false
    $printedAny = $false
    foreach ($item in $items) {
        $script:OneRc = 0
        $target = $null
        if (Test-HasProp $item 'target') { $target = $item.target }
        $out = @(& {
                if ([string]::IsNullOrEmpty($target)) {
                    Write-Output "error: JSON[$([array]::IndexOf($items, $item))].target が指定されていません"
                    $script:OneRc = 1
                    return
                }
                $script:RmJsonSet = @(Get-StringArray $item 'allow' | ForEach-Object { $_ } | ForEach-Object { ConvertTo-NormalizedRule $_ })
                Invoke-RemoveOne $target { param($e) @($script:RmJsonSet) -ccontains (ConvertTo-NormalizedRule $e) } $Apply
            })
        if ($script:OneRc -ne 0) { $failed = $true }
        if ($out.Count -gt 0) {
            if ($printedAny) { Write-Output '' }
            $out | ForEach-Object { Write-Output $_ }
            $printedAny = $true
        }
    }
    return (-not $failed)
}

function Invoke-Remove([string[]]$CmdArgs) {
    $glob = $false; $apply = $false; $json = $false
    $rest = New-Object System.Collections.Generic.List[string]
    foreach ($a in $CmdArgs) {
        switch ($a) {
            '--glob' { $glob = $true }
            { $_ -eq '--apply' -or $_ -eq '-y' } { $apply = $true }
            '--json' { $json = $true }
            default { $rest.Add($a) }
        }
    }
    if ($json) {
        if ($glob) { Stop-WithError '--json と --glob は同時に指定できません' }
        return (Invoke-RemoveJson $rest.ToArray() $apply)
    }
    if ($rest.Count -eq 0) { Stop-WithError 'usage: claude-perms remove <pattern> [DIR...] [--glob] [--apply]' }
    $pattern = $rest[0]
    $dirs = @()
    if ($rest.Count -gt 1) { $dirs = $rest.GetRange(1, $rest.Count - 1).ToArray() }
    # クロージャ（GetNewClosure）はスクリプトスコープの関数を呼べないため、状態は $script: 変数で渡す
    $script:RmPattern = $pattern
    $script:RmGlob = $glob
    $script:RmApply = $apply
    return (Invoke-OverDirs { param($d) Invoke-RemoveOne $d { param($e) Test-PatternMatch $e $script:RmPattern $script:RmGlob } $script:RmApply } $dirs)
}

function Invoke-RemoveGlobal([string[]]$CmdArgs) {
    $glob = $false; $apply = $false
    $rest = New-Object System.Collections.Generic.List[string]
    foreach ($a in $CmdArgs) {
        switch ($a) {
            '--glob' { $glob = $true }
            { $_ -eq '--apply' -or $_ -eq '-y' } { $apply = $true }
            default { $rest.Add($a) }
        }
    }
    if ($rest.Count -eq 0) { Stop-WithError 'usage: claude-perms remove-global <pattern> [--glob] [--apply]' }
    if ($rest.Count -ne 1) { Stop-WithError 'remove-global はpattern以外の引数（DIR等）を取りません' }
    $pattern = $rest[0]
    $file = Get-GlobalSettingsFile
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Write-Output "error: not found: $file"
        return $false
    }
    if (-not (Test-JsonFileValid $file)) { return $false }
    $script:RmPattern = $pattern
    $script:RmGlob = $glob
    Invoke-RemoveFromFile $file { param($e) Test-PatternMatch $e $script:RmPattern $script:RmGlob } $apply
    return $true
}

# ---------- merge / apply ----------
function Invoke-PathRuleOne([string]$Dir, [bool]$Replace) {
    if ([string]::IsNullOrEmpty($Dir)) { $Dir = '.' }
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { Stop-WithError "ディレクトリが見つかりません: $Dir" }
    $absDir = Get-AbsolutePath $Dir
    $matched = Get-MatchedPathRuleAllow $absDir
    if ($null -eq $matched) { $script:OneRc = 1; return }
    $matched = @($matched)
    if ($matched.Count -eq 0) {
        if ($script:Verbose) { Write-Output "skip（一致するpathRuleなし）: $absDir" }
        return
    }

    $file = Get-LocalSettingsFile $Dir
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
        [System.IO.File]::WriteAllText($file, '{"permissions": {"allow": []}}' + "`n", (New-Object System.Text.UTF8Encoding($false)))
    } elseif (-not (Test-JsonFileValid $file)) {
        $script:OneRc = 1
        return
    }

    $doc = Read-JsonFile $file
    if ($null -eq $doc) { $doc = [pscustomobject]@{} }
    if (-not (Test-HasProp $doc 'permissions') -or $null -eq $doc.permissions) { Set-Prop $doc 'permissions' ([pscustomobject]@{}) }
    if ($Replace) { $newAllow = Get-UniqueSorted $matched }
    else { $newAllow = Get-UniqueSorted ((Get-StringArray $doc.permissions 'allow') + $matched) }
    Set-Prop $doc.permissions 'allow' $newAllow
    Write-JsonFile $file $doc

    if ($Replace) { Write-Output "pathRuleで置き換え: $file" } else { Write-Output "pathRuleを反映: $file" }
    foreach ($m in (Get-UniqueSorted $matched)) { Write-Output "  $m" }

    Invoke-FormatOne $Dir
}

# ---------- ディスパッチ ----------
if ($cliArgs.Count -eq 0) {
    Stop-WithError 'usage: claude-perms {format|format-global|check|candidates|remove|remove-global|merge|apply} [DIR...]'
}
$command = $cliArgs[0]
$rest = @()
if ($cliArgs.Count -gt 1) { $rest = $cliArgs.GetRange(1, $cliArgs.Count - 1).ToArray() }

# 各サブコマンドは「出力行（文字列）… 最後に成否（bool）」を返す。最後の bool を終了コードにする。
$all = @(switch ($command) {
        'format'        { Invoke-Format $rest }
        'format-global' { Invoke-FormatGlobal $rest }
        'check'         { Invoke-Check $rest }
        'candidates'    { Invoke-Candidates $rest }
        'remove'        { Invoke-Remove $rest }
        'remove-global' { Invoke-RemoveGlobal $rest }
        'merge'         { Invoke-OverDirs { param($d) Invoke-PathRuleOne $d $false } $rest }
        'apply'         { Invoke-OverDirs { param($d) Invoke-PathRuleOne $d $true } $rest }
        default         { Stop-WithError "unknown command: $command (format/format-global/check/candidates/remove/remove-global/merge/apply が使えます)" }
    })
$ok = $true
if ($all.Count -gt 0 -and $all[-1] -is [bool]) {
    $ok = $all[-1]
    $all = if ($all.Count -gt 1) { $all[0..($all.Count - 2)] } else { @() }
}
foreach ($d in $script:Diag) { [Console]::Error.WriteLine($d) }
foreach ($line in $all) { Write-Output $line }
exit $(if ($ok) { 0 } else { 1 })
