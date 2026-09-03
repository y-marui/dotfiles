DOTFILES_DIR := $(CURDIR)
PRIVATE_DIR  := $(DOTFILES_DIR)-private
PRIVATE_SCAFFOLD_DIR ?= $(PRIVATE_DIR)
BACKUP_DIR   := $(HOME)/.dotfiles-backup/$(shell date +%Y%m%d%H%M%S)

.DEFAULT_GOAL := help

.PHONY: help install install-macos install-rpi install-windows links uninstall check check-skills launchagent launchagent-museum-status init private private-scaffold private-validate private-lint update-charter update-private-charter

help: ## コマンド一覧を表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

install: ## OS を検出して対応する install-* を実行
ifeq ($(OS),Windows_NT)
	$(MAKE) install-windows
else
	@OS="$$(uname -s)"; \
	 case "$$OS" in \
	   Darwin)  $(MAKE) install-macos ;; \
	   Linux)   $(MAKE) install-rpi ;; \
	   *)       echo "Unsupported OS: $$OS" >&2; exit 1 ;; \
	 esac
endif

install-macos: ## macOS 向けフルセットアップ（Prezto + シンボリックリンク + macos + brew + dock + shortcuts）
	@bash scripts/setup-prezto.sh
	@bash scripts/install.sh
	@bash macos/setup_dots_check_launchagent.sh install
	@bash macos/setup_museum_status_launchagent.sh install
	@bash scripts/setup-zellij.sh
	@bash macos/defaults.sh
	@bash bin/unix/dots brew apply --backup-dir "$(BACKUP_DIR)"
	@bash bin/unix/dots dock apply --backup-dir "$(BACKUP_DIR)"
	@bash bin/unix/dots shortcuts apply --backup-dir "$(BACKUP_DIR)"

install-rpi: ## Raspberry Pi 向けセットアップ（シンボリックリンク + apt パッケージ + claude-code/homebridge/tailscale + zsh化 + gpg-agent永続化）
	@bash scripts/install.sh
	@DOTFILES_DIR="$(DOTFILES_DIR)" bash rpi/apply_packages.sh
	@bash scripts/setup-prezto.sh
	@bash bin/unix/dots pipx apply
	@bash rpi/repos/setup_claude-code.sh
	@bash rpi/repos/setup_homebridge.sh
	@bash rpi/repos/setup_tailscale.sh
	@bash scripts/setup-zellij.sh
	@bash rpi/setup_zsh.sh
	@bash rpi/setup_gpg_agent.sh

install-windows: ## Windows 向けセットアップ（gsudo + jq + シンボリックリンク + Zellij自動attach + private repo リンク）
	pwsh -NoLogo -NoProfile -File scripts/setup-gsudo.ps1
	pwsh -NoLogo -NoProfile -File scripts/setup-jq.ps1
	pwsh -NoLogo -NoProfile -File scripts/setup-zellij.ps1
	gsudo pwsh -NoLogo -NonInteractive -File scripts/install.ps1

links: ## public/privateのシンボリックリンクだけを再適用
ifeq ($(OS),Windows_NT)
	gsudo pwsh -NoLogo -NonInteractive -File scripts/install.ps1
else
	@bash scripts/install.sh
endif

uninstall: ## public/privateの管理シンボリックリンクを削除
ifeq ($(OS),Windows_NT)
	pwsh -NoLogo -File scripts/uninstall.ps1
else
	@bash scripts/uninstall.sh
endif

check: ## public/privateのシンボリックリンク整合性を確認
ifeq ($(OS),Windows_NT)
	pwsh -NoLogo -NonInteractive -File scripts/check.ps1
else
	@bash scripts/check.sh
endif

check-skills: ## uv で全 Agent Skill の構造と同梱テストを検証
	@bash scripts/check-skills.sh

launchagent: ## macOSのdots check定期監視LaunchAgentを再登録
	@bash macos/setup_dots_check_launchagent.sh install

launchagent-museum-status: ## 美術展タスクのステータス更新LaunchAgent（毎週月曜8時）を再登録
	@bash macos/setup_museum_status_launchagent.sh install

init: ## このマシン用のホスト固有設定テンプレートを生成
	@bash scripts/init-host.sh

private: ## dotfiles-privateをクローン・更新し、リンクを適用
	@bash scripts/setup-private.sh

private-scaffold: ## .example付きの安全なdotfiles-private雛形を新規生成
ifeq ($(OS),Windows_NT)
	pwsh -NoLogo -NoProfile -File scripts/scaffold-private.ps1 "$(PRIVATE_SCAFFOLD_DIR)"
else
	@bash scripts/scaffold-private.sh "$(PRIVATE_SCAFFOLD_DIR)"
endif

private-validate: ## 隣接するdotfiles-privateの雛形・必須構造を検証
ifeq ($(OS),Windows_NT)
	pwsh -NoLogo -NoProfile -File scripts/check-private-contract.ps1 "$(PRIVATE_DIR)"
else
	@bash scripts/check-private-contract.sh "$(PRIVATE_DIR)"
endif

private-lint: ## dotfiles-private のpre-commitを全ファイルに実行
	@test -d "$(PRIVATE_DIR)/.git" || { echo "エラー: $(PRIVATE_DIR) がありません。make private を実行してください。" >&2; exit 1; }
	@cd "$(PRIVATE_DIR)" && pre-commit run --all-files

update-charter: ## dev-charter (lite) を最新版に更新
	curl -fsSL https://raw.githubusercontent.com/y-marui/dev-charter/main/scripts/install.sh | CHARTER_UPDATE_ONLY=1 CHARTER_BRANCH=lite bash

update-private-charter: ## dotfiles-private のdev-charter subtreeを更新
	@test -d "$(PRIVATE_DIR)/.git" || { echo "エラー: $(PRIVATE_DIR) がありません。make private を実行してください。" >&2; exit 1; }
	@cd "$(PRIVATE_DIR)" && curl -fsSL https://raw.githubusercontent.com/y-marui/dev-charter/main/scripts/install.sh | CHARTER_UPDATE_ONLY=1 CHARTER_BRANCH=lite bash
