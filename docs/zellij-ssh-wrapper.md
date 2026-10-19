---
description: Zellij の自動アタッチ、ssh ラッパー、claude-rc の使い方
---

# Zellij Auto-Attach & SSH Wrapper

## Zellij Auto-Attach

以下の条件で起動時に自動的にZellijセッション（セッション名: ホスト名）にアタッチする。

- iTerm2から起動した場合
- SSHでリモートログインした場合（`$SSH_CONNECTION` が設定されている場合）

`NO_ZELLIJ=1` を設定するか、`ZELLIJ` が設定済みの場合はスキップされる。

WindowsではWindows TerminalまたはSSHからの最初の接続でホスト名セッションを作成し、
切断後もZellijサーバーを維持するため、同じセッションへ再接続できる。
詳細は [Windowsセットアップ](setup-windows.md) を参照。
Zellijなしで作業する場合は、Windows Terminalの `PowerShell (No Zellij)` を選ぶ。

## ssh Command Wrapper (Active Only Inside iTerm2 + Zellij)

Zellij内で `ssh` を実行するとZellijが二重になるため、iTerm2の別ペイン/タブで開くラッパーを提供している。
接続先でもZellijが自動起動する。

| コマンド | 動作 | 接続先の Zellij |
|---------|------|----------------|
| `ssh user@host` | 新規タブで接続（デフォルト） | 自動起動 |
| `ssh --same user@host` | 現在のタブを縦分割して右ペインで接続 | 自動起動 |
| `ssh --no-zellij user@host` | 新規タブで接続 | 起動しない |
| `ssh --same --no-zellij user@host` | 現在のタブを縦分割して右ペインで接続 | 起動しない |

> `--same` と `--no-zellij` は独立したフラグなので併用できる。

## claude-rc — Launching Remote Claude Remote-Control

デスクトップの ghq リポジトリを fzf で選択し、リモートの zellij 新タブで `claude remote-control` を起動する。

| コマンド | spawn モード | 説明 |
|---------|------------|------|
| `claude-rc <host>` | same-dir（デフォルト） | CWD で複数セッション共存 |
| `claude-rc <host> -w` / `--worktree` | worktree | セッションごとに git worktree を分離 |
| `claude-rc <host> -s` / `--session` | session | 1セッションのみ（終了で退出） |

- `<host>` は `~/.ssh/config` の Host エントリをタブ補完できる
- リモートの zellij セッションが起動済みである必要がある（自動アタッチで通常は起動済み）
