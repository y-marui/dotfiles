# dotfiles

macOS を中心に、Raspberry Pi・Windowsでも共有する個人開発環境設定。
zsh (zprezto + Powerlevel10k) / Vim / Zellij / Codex + Claude Code + GitHub Copilot。

## Setup (New Machine)

詳細な手順は **[macOS](docs/setup-mac.md)** / **[Windows](docs/setup-windows.md)** を参照。

Raspberry PiのOS更新・Homebridge公式コンテナ・復旧手順は
[Raspberry Pi Platform](docs/raspberry-pi-platform.md)、SSH切断後のエージェントは
[SSH Agent and Zellij](docs/ssh-agent-zellij.md)を参照。
コンテナ用ホストの再構築には `bash rpi/bootstrap-platform.sh` を使う。
`make install-rpi` はHomebridgeを導入しない（コンテナ構成は上記ドキュメントの手順で管理する）。

概要:

1. Homebrew をインストール（Apple Silicon は PATH の追加設定が必要）
2. SSH キーを生成して GitHub に登録
3. `brew install ghq` → `ghq get https://github.com/y-marui/dotfiles.git`
4. `scripts/setup-prezto.sh` で zprezto をインストール（`make install-macos` でも自動実行）
5. `make init` → ホスト固有設定を編集（`DOTFILES_DIR` の設定が必要）
6. `brew install gh && gh auth login` → `make private` でプライベート設定を取得
7. `make install-macos` → dotfiles 一括適用
8. iTerm2 の Shell Integration をインストール

## Documentation

| 内容 | 参照先 |
|------|--------|
| `make` / `dots` / カスタムコマンドの一覧、`dots` の動詞表 | [docs/commands.md](docs/commands.md) |
| `dots` の動作定義 | [docs/specification.md](docs/specification.md) |
| Claude Code・Codex・Copilot CLI の設定と `dots check` | [docs/ai-configuration.md](docs/ai-configuration.md) |
| Zellij の自動アタッチ・`ssh` ラッパー・`claude-rc` | [docs/zellij-ssh-wrapper.md](docs/zellij-ssh-wrapper.md) |
| private 設定、マシン固有設定、`Brewfile.local`、環境変数 | [docs/local-settings.md](docs/local-settings.md) |
| pre-commit フック（gitleaks）と誤検知への対処 | [docs/security-hooks.md](docs/security-hooks.md) |
| Obsidian の会話 Record と skill の責務 | [docs/obsidian-workflow.md](docs/obsidian-workflow.md) |
| 構造・ファイル対応・開発規約 | [architecture](docs/architecture.md) / [file-map](docs/file-map.md) / [DEVELOPING.md](DEVELOPING.md) |

## Daily Use

初回セットアップ後は、カレントディレクトリに依存しない `dots`（`dots status` / `dots check` /
`dots update` など）を使う。`make install` は OS 別のフルセットアップ、`make links` はリンクの再適用。

## File Structure

| パス | 説明 |
|-----|------|
| `shell/` | zsh / bash 設定 |
| `git/` | Git 設定（公開分のみ） |
| `terminal/` | Zellij / p10k / PowerShell 設定 |
| `ai/` | Codex / Claude Code / Copilot 設定（管理方針は [`ai/README.md`](ai/README.md)） |
| `macos/` | Brewfile / macOS デフォルト設定 |
| `host/` | ホスト固有設定（git 管理外） |
| `scripts/` | install / check 等のスクリプト |
