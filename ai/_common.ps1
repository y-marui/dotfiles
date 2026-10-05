# ai/_common.ps1
# ai/ 配下の *.ps1（claude・codex・copilot・skills の apply / diff / prune）が dot source する共通関数。
# bash 版は各スクリプトに python3 を埋め込んでいるため、対になる .sh は存在しない。
#
# 使い方: . (Join-Path $PSScriptRoot '..\..\_common.ps1')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# diff スクリプトの終了コード1は「差分あり」を意味する。想定外のエラーは 2 で終えて区別する。
trap {
    [Console]::Error.WriteLine($_.ToString())
    exit 2
}

# この共通ファイルの位置（<dotfiles>\ai）を基準にリポジトリルートを決める。
$DotfilesDir = if ($env:DOTFILES_DIR) { $env:DOTFILES_DIR } else { Split-Path -Parent $PSScriptRoot }

$script:BackupStamp = Get-Date -Format 'yyyyMMddHHmmss'

# ConvertFrom-Json -AsHashtable で読む。配列が最上位でも配列のまま返す。
function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)

    $text = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($text)) { return @{} }
    return ($text | ConvertFrom-Json -AsHashtable -NoEnumerate)
}

# JSON ファイルが無ければ空のテーブルを返す（Python の FileNotFoundError -> {} 相当）。
function Read-JsonFileOrEmpty {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @{} }
    return Read-JsonFile -Path $Path
}

# ハッシュテーブルから値を取る。キーが無い・テーブルでない場合は既定値。
function Get-Value {
    param($Table, [string]$Key, $Default = $null)

    if ($Table -is [System.Collections.IDictionary] -and $Table.Contains($Key)) {
        $value = $Table[$Key]
        if ($null -ne $value) { return $value }
    }
    return $Default
}

# 文字列の集合を ordinal 順に並べる（Python の sorted() と同じ順序）。
function Sort-Ordinal {
    param([string[]]$Items)

    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Items) { $list.Add($item) }
    $list.Sort([System.StringComparer]::Ordinal)
    return $list.ToArray()
}

# A - B（ordinal 順）。
function Get-SetDifference {
    param([string[]]$A, [string[]]$B)

    $other = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $B) { [void]$other.Add($item) }
    $result = foreach ($item in $A) { if (-not $other.Contains($item)) { $item } }
    return Sort-Ordinal -Items @($result | Select-Object -Unique)
}

# A ∩ B（ordinal 順）。
function Get-SetIntersection {
    param([string[]]$A, [string[]]$B)

    $other = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $B) { [void]$other.Add($item) }
    $result = foreach ($item in $A) { if ($other.Contains($item)) { $item } }
    return Sort-Ordinal -Items @($result | Select-Object -Unique)
}

# 2 つのリストが要素・順序とも等しいか。$null は空リスト扱い。
function Test-SameList {
    param($A, $B)

    $left = @($A | Where-Object { $null -ne $_ })
    $right = @($B | Where-Object { $null -ne $_ })
    if ($left.Count -ne $right.Count) { return $false }
    for ($i = 0; $i -lt $left.Count; $i++) {
        if ([string]$left[$i] -cne [string]$right[$i]) { return $false }
    }
    return $true
}

# 2 つのテーブルが同じキーと値を持つか。
function Test-SameTable {
    param($A, $B)

    $left = if ($A -is [System.Collections.IDictionary]) { $A } else { @{} }
    $right = if ($B -is [System.Collections.IDictionary]) { $B } else { @{} }
    if ($left.Count -ne $right.Count) { return $false }
    foreach ($key in $left.Keys) {
        if (-not $right.Contains($key)) { return $false }
        if ([string]$left[$key] -cne [string]$right[$key]) { return $false }
    }
    return $true
}

function Test-LoopbackUrl {
    param([string]$Url)

    if (-not $Url) { return $false }
    try {
        $hostName = ([uri]$Url).Host
    } catch {
        return $false
    }
    return $hostName -in @('127.0.0.1', 'localhost', '::1', '[::1]')
}

# 外部コマンドを実行して標準出力を文字列で返す。終了コードが 0 でなければ例外にする。
function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory)][string]$Command,
        [string[]]$Arguments = @()
    )

    $output = & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
    return (@($output) -join "`n")
}

# 外部コマンドを実行する（標準出力は捨てる）。終了コードが 0 でなければ例外にする。
function Invoke-NativeQuiet {
    param(
        [Parameter(Mandatory)][string]$Command,
        [string[]]$Arguments = @()
    )

    & $Command @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "$Command $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

# 外部コマンドを実行する（標準出力はそのまま表示する）。
function Invoke-NativeVisible {
    param(
        [Parameter(Mandatory)][string]$Command,
        [string[]]$Arguments = @()
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

# servers.json の headers（{名前: {cmd: [...], prefix: "..."}}）を、実行結果の値に解決する。
# 値は呼び出し側がコマンドラインに渡すだけで、表示しない。
function Resolve-HeaderValues {
    param($Headers)

    $resolved = [ordered]@{}
    if ($Headers -isnot [System.Collections.IDictionary]) { return $resolved }
    foreach ($headerName in $Headers.Keys) {
        $spec = $Headers[$headerName]
        $cmd = @($spec['cmd'])
        $value = (Invoke-NativeCapture -Command $cmd[0] -Arguments @($cmd | Select-Object -Skip 1)).Trim()
        if (-not $value) {
            throw "Credential command returned an empty value: $headerName"
        }
        $resolved[$headerName] = (Get-Value $spec 'prefix' '') + $value
    }
    return $resolved
}

# ~/.dotfiles-backup/<時刻>/<サブパス> を返す。ディレクトリは作らない。
function Get-BackupPath {
    param([Parameter(Mandatory)][string]$Child)

    return Join-Path (Join-Path (Join-Path $HOME '.dotfiles-backup') $script:BackupStamp) $Child
}

function Copy-ToBackup {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Child)

    $destination = Get-BackupPath -Child $Child
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $destination -Force
    return $destination
}

function Get-CodexHome {
    if ($env:CODEX_HOME) { return $env:CODEX_HOME }
    return Join-Path $HOME '.codex'
}

# diff スクリプトの共通終了処理。差分ありは 1、なしは 0。
function Exit-Diff {
    param([bool]$Found)

    if ($Found) { exit 1 }
    exit 0
}

# ── skill 共通 ────────────────────────────────────────────────────────────────

# agent ごとの個人 skill 配置先。
function Get-SkillHome {
    param([Parameter(Mandatory)][string]$Agent)

    switch ($Agent) {
        'claude' { return Join-Path $HOME '.claude\skills' }
        'codex' { return Join-Path $HOME '.agents\skills' }
        default { throw "usage: {claude|codex} (got: $Agent)" }
    }
}

# 外部 skill の取得キャッシュ。Claude Code / Codex から同じ実体を参照する。
function Get-SkillCacheHome {
    $dataHome = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $HOME '.local\share' }
    return Join-Path (Join-Path $dataHome 'dotfiles') 'skills'
}

# external.json の skill のうち、agent を対象にするもの（-All なら全 agent）。
function Get-ExternalSkills {
    param([string]$Agent, [switch]$All)

    $file = Join-Path $DotfilesDir 'ai\skills\external.json'
    $entries = @(Get-Value (Read-JsonFile -Path $file) 'skills' @())
    return @($entries | Where-Object { $All -or ($Agent -in @(Get-Value $_ 'targets' @('claude', 'codex'))) })
}

# 共通 skill と agent 専用 skill（SKILL.md を持つディレクトリ）。
function Get-LocalSkillSources {
    param([Parameter(Mandatory)][string]$Agent)

    $sources = [System.Collections.Generic.List[object]]::new()
    foreach ($sourceHome in @((Join-Path $DotfilesDir 'ai\skills'), (Join-Path $DotfilesDir "ai\$Agent\skills"))) {
        if (-not (Test-Path -LiteralPath $sourceHome -PathType Container)) { continue }
        foreach ($dir in (Get-ChildItem -LiteralPath $sourceHome -Directory)) {
            if (Test-Path -LiteralPath (Join-Path $dir.FullName 'SKILL.md') -PathType Leaf) {
                $sources.Add([pscustomobject]@{ Name = $dir.Name; Dir = $dir.FullName })
            }
        }
    }
    return $sources.ToArray()
}

# 名前の重複を返す（ordinal 順）。
function Get-DuplicateNames {
    param($Sources)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $duplicates = foreach ($source in @($Sources)) {
        if (-not $seen.Add($source.Name)) { $source.Name }
    }
    return Sort-Ordinal -Items @($duplicates | Select-Object -Unique)
}

function Test-PathOrLink {
    param([Parameter(Mandatory)][string]$Path)

    return $null -ne (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
}

# シンボリックリンクのリンク先（絶対パス）。リンクでなければ $null。
function Get-LinkTarget {
    param([Parameter(Mandatory)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item -or $item.LinkType -ne 'SymbolicLink') { return $null }
    $target = [string]($item.Target | Select-Object -First 1)
    if (-not [System.IO.Path]::IsPathRooted($target)) {
        $target = Join-Path (Split-Path -Parent $Path) $target
    }
    return [System.IO.Path]::GetFullPath($target).TrimEnd('\', '/')
}

function Test-SamePath {
    param([string]$A, [string]$B)

    if (-not $A -or -not $B) { return $false }
    $left = [System.IO.Path]::GetFullPath($A).TrimEnd('\', '/')
    $right = [System.IO.Path]::GetFullPath($B).TrimEnd('\', '/')
    return $left.Equals($right, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-UnderPath {
    param([string]$Path, [string]$Root)

    if (-not $Path -or -not $Root) { return $false }
    $prefix = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + '\'
    return [System.IO.Path]::GetFullPath($Path).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

# ファイル・ディレクトリ・シンボリックリンク自体を退避先へ移す（リンクは辿らない）。
function Move-ToBackup {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Destination)

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) {
        [System.IO.Directory]::Move($item.FullName, $Destination)
    } else {
        [System.IO.File]::Move($item.FullName, $Destination)
    }
}
