# Architecture

## Overview
macOS・Raspberry Pi・Windows の開発環境設定をシンボリックリンクで一元管理する dotfiles。`make install`（Unix）/ `mingw32-make install`（Windows）が `scripts/*.sh` または `scripts/*.ps1` を呼び分け、公開設定と `dotfiles-private/links.conf` の非公開設定を展開する。

## Entry Points
- `Makefile` — `install` / `links` / `check` / `uninstall` / `init` / `private-scaffold` / `private-validate` タスクの統一インターフェース（`$(OS)` で OS 別スクリプトへ分岐）
- `bin/unix/dots` / `bin/windows/dots.ps1` — 日常運用コマンド（`status` / `update` / `brew` / `claude` / `codex` / `gemini` / `check` 等のサブコマンド群）
- `bin/unix/ghq-status` — ghq 管理下の全リポジトリの git 状態・dev-charter 追従状況を一覧表示
- `bin/unix/claude-perms` — Claude Code の permissions（allow/deny/ask）整理、pathRule ベースの一括配布（`merge`＝追記／`apply`＝置き換え）、ローカル未カバーallowのJSON出力・一括削除（`candidates --json` / `remove --json`）

## Directory Structure
| ディレクトリ | 役割 |
|---|---|
| `bin/unix/` | カスタムコマンド（zsh/bash、拡張子なし） |
| `bin/windows/` | カスタムコマンド（`*.ps1` + bare コマンド名用 `*.cmd` シム） |
| `shell/` | zsh / bash / sh 設定ファイル |
| `git/` | gitconfig、gitignore_global、エイリアス |
| `terminal/` | Zellij、p10k、PowerShell 設定 |
| `karabiner/` | Karabiner-Elements 設定（macOS専用） |
| `ai/` | Claude Code / Codex / Copilot / Gemini CLI 向け設定・skill・MCP 宣言 |
| `macos/` | Brewfile、macOS defaults スクリプト |
| `windows/` | WingetPin（winget一時pin宣言） |
| `scripts/` | install / uninstall / check / init スクリプトおよび pre-commit フック |
| `templates/dotfiles-private/` | private repository の安全な `.example` 付き雛形 |
| `docs/` | 設計ドキュメント（本ファイルを含む） |

詳細は [AI_CONTEXT.md](../AI_CONTEXT.md) の「ディレクトリ構成と責務」を参照。

## Key Dependencies
| ツール | 用途 |
|---|---|
| zprezto | zsh フレームワーク（外部リポジトリとして管理、`scripts/setup-prezto.sh`） |
| Homebrew | macOS パッケージ管理（`macos/Brewfile`） |
| pre-commit + gitleaks | シークレット検知・コード品質チェック |
| ghq | リポジトリ一元管理（`ghq-status` / `ghq-update` が前提とする） |
| Zellij | ターミナルマルチプレクサ（全プラットフォーム共通） |
