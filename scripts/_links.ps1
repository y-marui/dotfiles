# scripts/_links.ps1
# install.ps1 / check.ps1 / uninstall.ps1 から dot source される。
# macOS/Raspberry Pi の scripts/_links.sh に相当する Windows 版のリンク定義。
#
# 使い方: . "$PSScriptRoot\_links.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DOTFILES_DIR = Split-Path -Parent $PSScriptRoot

$Links = @(
    [pscustomobject]@{
        Src  = "bin\dots.ps1"
        Dest = Join-Path $HOME ".local\bin\dots.ps1"
    }
    [pscustomobject]@{
        Src  = "bin\dots.cmd"
        Dest = Join-Path $HOME ".local\bin\dots.cmd"
    }
    [pscustomobject]@{
        Src  = "terminal\powershell\profile.ps1"
        # OneDrive の「ドキュメント」リダイレクトを含む、pwsh が実際に読むパス。
        Dest = $PROFILE.CurrentUserCurrentHost
    }
    [pscustomobject]@{
        Src  = "terminal\windows-terminal\dotfiles.json"
        # 自動attachを迂回できる「PowerShell (No Zellij)」プロファイル。
        Dest = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\dotfiles\profiles.json"
    }
    [pscustomobject]@{
        Src  = "terminal\ohmyposh\p10k-lean.json"
        Dest = Join-Path $HOME ".config\oh-my-posh\p10k-lean.json"
    }
    [pscustomobject]@{
        Src  = "terminal\zellij\windows\config.kdl"
        Dest = Join-Path $HOME ".config\zellij\config.kdl"
    }
    [pscustomobject]@{
        Src  = "git\gitconfig"
        Dest = Join-Path $HOME ".gitconfig"
    }
    [pscustomobject]@{
        Src  = "git\gitignore_global"
        Dest = Join-Path $HOME ".gitignore_global"
    }
    [pscustomobject]@{
        Src  = "git\hooks"
        Dest = Join-Path $HOME ".config\git\hooks"
    }
    [pscustomobject]@{
        Src  = "git\gitconfig.d\aliases.gitconfig"
        Dest = Join-Path $HOME ".gitconfig.d\aliases.gitconfig"
    }
    [pscustomobject]@{
        # Windows 純正 OpenSSH に core.sshCommand を向け、ssh-agent サービス経由の
        # 認証にする（Git バンドルの usr/bin/ssh.exe は毎回パスフレーズを要求する）。
        Src  = "git\gitconfig.d\windows.gitconfig"
        Dest = Join-Path $HOME ".gitconfig.d\os"
    }
    [pscustomobject]@{
        Src  = "ai\AI_CONTEXT.md"
        Dest = Join-Path $HOME ".ai\AI_CONTEXT.md"
    }
    [pscustomobject]@{
        Src  = "ai\AI_CONTEXT_CLI.md"
        Dest = Join-Path $HOME ".ai\AI_CONTEXT_CLI.md"
    }
    [pscustomobject]@{
        Src  = "ai\AI_CONTEXT.md"
        Dest = Join-Path $HOME ".codex\AGENTS.md"
    }
    [pscustomobject]@{
        Src  = "ai\claude\settings.json"
        Dest = Join-Path $HOME ".claude\settings.json"
    }
    [pscustomobject]@{
        Src  = "ai\claude\CLAUDE.md"
        Dest = Join-Path $HOME ".claude\CLAUDE.md"
    }
    [pscustomobject]@{
        Src  = "ai\claude\hooks\status.sh"
        Dest = Join-Path $HOME ".claude\hooks\status.sh"
    }
    [pscustomobject]@{
        Src  = "ai\copilot\instructions.md"
        Dest = Join-Path $HOME ".copilot\copilot-instructions.md"
    }
    [pscustomobject]@{
        Src  = "ai\gemini\GEMINI.md"
        Dest = Join-Path $HOME ".gemini\GEMINI.md"
    }
)

# 共通 skill と agent 専用 skill はディレクトリ全体ではなく、SKILL.md を持つものだけを
# 個別リンクする。scripts/_links.sh の同名ロジックと揃える。
foreach ($agent in @("codex", "claude")) {
    $skillHome = if ($agent -eq "codex") { Join-Path $HOME ".agents\skills" } else { Join-Path $HOME ".claude\skills" }

    $seenSkillNames = @{}
    foreach ($sourceHome in @((Join-Path $DOTFILES_DIR "ai\skills"), (Join-Path $DOTFILES_DIR "ai\$agent\skills"))) {
        if (-not (Test-Path $sourceHome)) { continue }

        Get-ChildItem -LiteralPath $sourceHome -Directory | ForEach-Object {
            $skillFile = Join-Path $_.FullName "SKILL.md"
            if (-not (Test-Path $skillFile)) { return }

            $skillName = $_.Name
            if ($seenSkillNames.ContainsKey($skillName)) {
                throw "共通 skill と ${agent} 専用 skill で名前が重複しています: ${skillName}"
            }
            $seenSkillNames[$skillName] = $true

            $skillSource = $_.FullName.Substring($DOTFILES_DIR.Length + 1)
            $Links += [pscustomobject]@{
                Src  = $skillSource
                Dest = Join-Path $skillHome $skillName
            }
        }
    }
}
