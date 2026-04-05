# PowerShell Profile
# zsh + Powerlevel10k lean スタイルに合わせた設定
# 対象環境: Windows（Windows Terminal）、macOS/Linux（pwsh）

# ─── Zellij 自動アタッチ ─────────────────────────────────────────────────────
# Windows Terminal または SSH 接続時のみ起動。NO_ZELLIJ=1 でスキップ。
if ((Get-Command zellij -ErrorAction SilentlyContinue) -and
    -not $env:ZELLIJ -and
    -not $env:NO_ZELLIJ -and
    ($env:WT_SESSION -or $env:SSH_CONNECTION)) {
    $sessionName = ($env:COMPUTERNAME -split '\.')[0].ToLower()
    zellij attach -c $sessionName
    exit
}

# ─── Oh My Posh ──────────────────────────────────────────────────────────────
# インストール: winget install JanDeDobbeleer.OhMyPosh (Windows)
#              brew install oh-my-posh (macOS)
$_omp_config = "$HOME/.config/oh-my-posh/p10k-lean.json"
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config $_omp_config | Invoke-Expression
}

# ─── PSReadLine ───────────────────────────────────────────────────────────────
# zsh の Emacs キーバインド・履歴検索に合わせた設定
if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
    Set-PSReadLineKeyHandler -Chord Ctrl+r  -Function ReverseSearchHistory
}

# ─── SSH ラッパー（Zellij 内のみ有効）────────────────────────────────────────
# Zellij 内で ssh を実行すると新しいペイン/タブを作成して SSH を起動する。
# 接続先ではデフォルトで zellij auto-attach（NO_ZELLIJ='' を渡す）。
# 使い方: ssh [--new] [--no-zellij] <ssh args...>
#   --new       : 新規タブで開く（デフォルトは縦分割ペイン）
#   --no-zellij : 接続先の zellij auto-attach を無効化
if ($env:ZELLIJ) {
    function Invoke-Ssh {
        [CmdletBinding()]
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

        $newTab   = $false
        $noZellij = $false
        $sshArgs  = @()

        foreach ($arg in $Arguments) {
            switch ($arg) {
                '--new'       { $newTab   = $true }
                '--no-zellij' { $noZellij = $true }
                default       { $sshArgs += $arg }
            }
        }

        $noZellijEnv = "NO_ZELLIJ=''"
        if ($noZellij) { $noZellijEnv = 'NO_ZELLIJ=1' }

        $remoteHost = $sshArgs[-1]
        $sshCmd     = "env $noZellijEnv ssh $($sshArgs -join ' ')"

        if ($newTab) {
            zellij action new-pane --new-tab --name "ssh:$remoteHost" --close-on-exit -- sh -c $sshCmd
        } else {
            zellij run --name "ssh:$remoteHost" --close-on-exit -- sh -c $sshCmd
        }
    }
    Set-Alias -Name ssh -Value Invoke-Ssh -Force
}
