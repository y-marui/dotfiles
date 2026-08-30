# Claude Code と Codex local のmemory候補を一覧化する。各行は TSV:
#   scope<TAB>type<TAB>name<TAB>description<TAB>path
# Claudeのscope は "global" または "project:<project-dir-name>"、Codexは
# "codex:local" または "codex:rollout"。frontmatterがないファイルは
# name/type/description を空欄で出力する。

$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$GlobalMemoryDir = Join-Path $ClaudeDir 'memory'
$ProjectsDir = Join-Path $ClaudeDir 'projects'
$CodexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$CodexMemoryDir = Join-Path $CodexDir 'memories'

function Get-Frontmatter {
    param([string]$Path)

    $name = ''
    $description = ''
    $type = ''
    $delim = 0

    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^---$') {
            $delim++
            if ($delim -ge 2) { break }
            continue
        }
        if ($delim -eq 1) {
            if ($line -match '^name: *(.*)$') { $name = $Matches[1] }
            elseif ($line -match '^description: *(.*)$') { $description = $Matches[1] }
            elseif ($line -match '^[ \t]*type: *(.*)$') { $type = $Matches[1] }
        }
    }

    [PSCustomObject]@{
        Type        = $type
        Name        = $name
        Description = $description
    }
}

function Write-MemoryDir {
    param([string]$Scope, [string]$Dir)

    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return }

    Get-ChildItem -LiteralPath $Dir -Filter '*.md' -File | ForEach-Object {
        $fields = Get-Frontmatter -Path $_.FullName
        "$Scope`t$($fields.Type)`t$($fields.Name)`t$($fields.Description)`t$($_.FullName)"
    }
}

Write-MemoryDir -Scope 'global' -Dir $GlobalMemoryDir

if (Test-Path -LiteralPath $ProjectsDir -PathType Container) {
    Get-ChildItem -LiteralPath $ProjectsDir -Directory | ForEach-Object {
        $memDir = Join-Path $_.FullName 'memory'
        if (Test-Path -LiteralPath $memDir -PathType Container) {
            Write-MemoryDir -Scope "project:$($_.Name)" -Dir $memDir
        }
    }
}

Write-MemoryDir -Scope 'codex:local' -Dir $CodexMemoryDir
Write-MemoryDir -Scope 'codex:rollout' -Dir (Join-Path $CodexMemoryDir 'rollout_summaries')
