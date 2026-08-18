SHELL      := /bin/bash
DOTFILES_DIR := $(CURDIR)
PRIVATE_DIR  := $(DOTFILES_DIR)-private
BACKUP_DIR   := $(HOME)/.dotfiles-backup/$(shell date +%Y%m%d%H%M%S)

.DEFAULT_GOAL := help

.PHONY: help install install-macos install-rpi install-windows links uninstall check check-skills init private

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

install-macos: ## macOS 向けフルセットアップ（Prezto + シンボリックリンク + macos + brew + dock）
	@bash scripts/setup-prezto.sh
	@bash scripts/install.sh
	@bash scripts/setup-zellij.sh
	@if [[ -f "$(PRIVATE_DIR)/setup.sh" ]]; then \
	   bash $(PRIVATE_DIR)/setup.sh; \
	 else \
	   echo "  SKIP    dotfiles-private (make private でセットアップしてください)"; \
	 fi
	@bash macos/defaults.sh
	@bash bin/dots brew apply --backup-dir "$(BACKUP_DIR)"
	@bash bin/dots dock apply --backup-dir "$(BACKUP_DIR)"

install-rpi: ## Raspberry Pi 向けセットアップ（シンボリックリンク + apt パッケージ + claude-code/homebridge/tailscale + zsh化）
	@bash scripts/install.sh
	@if [[ -f "$(PRIVATE_DIR)/setup.sh" ]]; then \
	   bash $(PRIVATE_DIR)/setup.sh; \
	 else \
	   echo "  SKIP    dotfiles-private (make private でセットアップしてください)"; \
	 fi
	@DOTFILES_DIR="$(DOTFILES_DIR)" bash rpi/apply_packages.sh
	@bash scripts/setup-prezto.sh
	@bash bin/dots pipx apply
	@bash rpi/repos/setup_claude-code.sh
	@bash rpi/repos/setup_homebridge.sh
	@bash rpi/repos/setup_tailscale.sh
	@bash scripts/setup-zellij.sh
	@bash rpi/setup_zsh.sh

install-windows: ## Windows 向けセットアップ（gsudo + シンボリックリンク + Zellij自動attach）
	pwsh -NoLogo -NoProfile -File scripts/setup-gsudo.ps1
	pwsh -NoLogo -NoProfile -File scripts/setup-zellij.ps1
	gsudo pwsh -NoLogo -NonInteractive -File scripts/install.ps1

links: ## シンボリックリンクだけを再適用
ifeq ($(OS),Windows_NT)
	gsudo pwsh -NoLogo -NonInteractive -File scripts/install.ps1
else
	@bash scripts/install.sh
endif

uninstall: ## シンボリックリンクを削除
ifeq ($(OS),Windows_NT)
	pwsh -NoLogo -File scripts/uninstall.ps1
else
	@bash scripts/uninstall.sh
endif

check: ## シンボリックリンクの整合性を確認
ifeq ($(OS),Windows_NT)
	pwsh -NoLogo -NonInteractive -File scripts/check.ps1
else
	@bash scripts/check.sh
endif

check-skills: ## uv で全 Agent Skill の構造と同梱テストを検証
	@bash scripts/check-skills.sh

init: ## このマシン用のホスト固有設定テンプレートを生成
	@bash scripts/init-host.sh

private: ## dotfiles-private を GitHub からクローン・更新
	@bash scripts/setup-private.sh
