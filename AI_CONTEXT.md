# dotfiles — AI Context

## このリポジトリの目的

macOS・Raspberry Pi・Windows の開発環境設定（シェル・Git・エディタ・ターミナル）を一元管理し、
シンボリックリンクを通じて設定を共有するための dotfiles リポジトリ。

## 環境

- OS: macOS（メイン）、Raspberry Pi OS（Linux / サブ）、Windows（サブ）
- Shell: zsh（zprezto + Powerlevel10k）— macOS / Raspberry Pi
- Shell: bash — macOS / Raspberry Pi（副）
- Shell: PowerShell（Oh My Posh）— **Windows のみ**（Windows で zsh は使わない）
- Terminal: iTerm2（macOS）、Windows Terminal（Windows）
- Terminal multiplexer: Zellij（全プラットフォーム共通）
- Mac: 複数台（ホスト名で差分管理）
- Version managers: pyenv, rbenv, nodebrew
- Editor: Vim, VSCode
- AI: Claude Code（メイン）、GitHub Copilot、Gemini CLI

## プラットフォーム別セットアップ

| プラットフォーム | インストール方法 |
|---|---|
| macOS / Linux | `make install`（bash スクリプト） |
| Windows | `pwsh scripts/install.ps1` |

## Zellij 自動アタッチ条件

| プラットフォーム | シェル | 起動条件 |
|---|---|---|
| macOS | zsh / bash | `$TERM_PROGRAM == "iTerm.app"` または `$SSH_CONNECTION` |
| Raspberry Pi | zsh / bash | `$SSH_CONNECTION`（SSH 経由のみで使用） |
| Windows | pwsh | `$env:WT_SESSION`（Windows Terminal）または `$env:SSH_CONNECTION` |

- `NO_ZELLIJ=1` でどの環境でもスキップ可
- `$ZELLIJ` が設定済みの場合は既にセッション内なのでスキップ
- エディタ等のサブプロセスでシェルが起動した場合は上記条件に合わないためスキップ

## SSH ラッパー（zsh / bash / pwsh 共通）

Zellij セッション内で `ssh` を実行すると、新しいペインを作成して SSH を起動する。
接続先ではデフォルトで zellij auto-attach（`NO_ZELLIJ=''` を渡す）。

| フラグ | 動作 |
|---|---|
| （なし） / `--new` | 新規タブで SSH（デフォルト） |
| `--same` | 現在のタブに縦分割ペインで SSH |
| `--no-zellij` | 接続先の zellij auto-attach を無効化（`NO_ZELLIJ=1` を渡す） |

## ディレクトリ構成と責務

```
dotfiles/
├── shell/          # zsh / bash / sh 設定ファイル
├── git/            # gitconfig、gitignore_global、エイリアス
│   └── gitconfig.d/
├── terminal/       # tmux.conf、p10k.zsh
├── ai/
│   ├── claude/     # ~/.claude/ にリンクされる Claude Code 設定
│   ├── copilot/    # GitHub Copilot 設定ドキュメント
│   └── gemini/     # ~/.gemini/ にリンクされる Gemini CLI 設定
├── macos/          # Brewfile、macOS defaults スクリプト
├── host/           # マシン固有設定（コミット対象外）
├── scripts/        # install / uninstall / check / init スクリプト
├── docs/           # 設計ドキュメント
└── .github/        # GitHub / Copilot 設定
```

## シェルファイルの責務分離ルール

| ファイル | 書くもの | 書かないもの |
|---------|---------|------------|
| `shell/profile` | PATH、全シェル共通の環境変数 | zsh/bash 固有の構文（`[[` 等） |
| `shell/zshenv` | ZDOTDIR 等、全 zsh セッションで必要なもの | 対話的な設定、エイリアス |
| `shell/zshrc` | zprezto source、エイリアス、関数、補完、ツール初期化 | ログイン時のみ必要なもの |
| `shell/zprofile` | zsh login で必要な環境変数（Homebrew PATH 等） | 対話設定 |
| `shell/zlogin` | ログイン後の処理（通常は最小限） | 対話設定 |
| `shell/zlogout` | ログアウト時の後処理 | — |
| `shell/zpreztorc` | zprezto のモジュール・テーマ設定 | zprezto 以外の設定 |
| `shell/bashrc` | bash 対話設定、`source ~/.profile` | zsh 固有構文 |
| `shell/bash_profile` | `source ~/.bashrc` のみ | それ以外 |

## シークレット管理ルール

- シークレットは絶対にコミットしない
- ローカル専用設定は `~/.zshrc.local` または `host/<hostname>.zsh` に書く
- Git の user 情報等は Private Gist で管理（`~/.gitconfig.d/` にシンボリックリンク）
- `make private` で Gist から取得・リンクを自動設定

## よく使うコマンド

- `make install`  : dotfiles をホームに展開（シンボリックリンク作成）
- `make check`    : リンク整合性確認
- `make init`     : ホスト固有設定テンプレートを生成
- `make update`   : git pull + 再インストール
- `make brew`     : Homebrew パッケージインストール
- `make macos`    : macOS デフォルト設定を適用

## zprezto について

`~/.zprezto` 本体はこのリポジトリで管理しない。
`shell/zpreztorc` のみリンク対象。

## 変更時の注意

- シェルスクリプトは ShellCheck を通す（`shellcheck scripts/*.sh`）
- シェルスクリプトの先頭に `set -euo pipefail` を書く
- 既存ファイルを変更する前に `make check` を実行する
- 不明な設定はユーザーに確認してから進める
- `host/` 配下はコミットしない（`.gitignore` 対象）
- `scripts/.env` はコミットしない
- `shell/profile` は sh 互換構文のみ（`[[` 不可）
- `~/.gitconfig.local` の内容をリポジトリ内ファイルにコピーしない
