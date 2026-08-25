# Architecture

## Overview
macOS・Raspberry Pi・Windows の開発環境設定をシンボリックリンクで一元管理する dotfiles。`make install`（Unix）/ `mingw32-make install`（Windows）が `scripts/*.sh` または `scripts/*.ps1` を呼び分けてリンクを展開する。

## Entry Points
- `Makefile` — `install` / `links` / `check` / `uninstall` / `init` タスクの統一インターフェース（`$(OS)` で OS 別スクリプトへ分岐）
- `bin/unix/dots` / `bin/windows/dots.ps1` — 日常運用コマンド（`status` / `update` / `brew` / `claude` / `codex` / `gemini` / `check` 等のサブコマンド群）
- `bin/unix/ghq-status` — ghq 管理下の全リポジトリの git 状態・dev-charter 追従状況を一覧表示

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
