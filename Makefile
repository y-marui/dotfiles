SHELL      := /bin/bash
DOTFILES_DIR := $(CURDIR)
PRIVATE_DIR  := $(DOTFILES_DIR)-private
BACKUP_DIR   := $(HOME)/.dotfiles-backup/$(shell date +%Y%m%d%H%M%S)
BACKUP       := 0

.DEFAULT_GOAL := help

.PHONY: help install install-macos install-rpi install-windows uninstall update brew brew-sync brew-cache brew-diff macos dock dock-sync dock-cache dock-diff npm npm-sync npm-cache npm-diff pipx pipx-sync pipx-cache pipx-diff check init private

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

install-macos: ## macOS 向けフルセットアップ（シンボリックリンク + macos + brew + dock）
	@bash scripts/install.sh
	@if [[ -f "$(PRIVATE_DIR)/setup.sh" ]]; then \
	   bash $(PRIVATE_DIR)/setup.sh; \
	 else \
	   echo "  SKIP    dotfiles-private (make private でセットアップしてください)"; \
	 fi
	@$(MAKE) macos
	@$(MAKE) brew BACKUP=1 BACKUP_DIR="$(BACKUP_DIR)"
	@$(MAKE) dock BACKUP=1 BACKUP_DIR="$(BACKUP_DIR)"

install-rpi: ## Raspberry Pi 向けセットアップ（未実装）
	@echo "TODO: install-rpi は未実装です。"

install-windows: ## Windows 向けセットアップ（シンボリックリンク作成）
	gsudo pwsh -NoLogo -NonInteractive -File scripts/install.ps1

uninstall: ## シンボリックリンクを削除
	@bash scripts/uninstall.sh

# TODO: RPi 用途が増えたら RPI_TARGET 変数等でスクリプト（update-rpi-*.sh）を分岐する
update: ## OS を検出して対応する update スクリプトを実行
ifeq ($(OS),Windows_NT)
	gsudo pwsh -NoLogo -NonInteractive -File scripts/update-windows.ps1
else
	@OS="$$(uname -s)"; \
	 case "$$OS" in \
	   Darwin)  zsh scripts/update-macos.zsh ;; \
	   Linux)   bash scripts/update-rpi-homebridge.sh ;; \
	   *)       echo "Unsupported OS: $$OS" >&2; exit 1 ;; \
	 esac
endif

brew: ## Brewfile を適用（差分なしはスキップ、適用後に cache 更新）
	@if DOTFILES_DIR="$(DOTFILES_DIR)" bash macos/diff_brewfile.sh; then \
	   echo "差分なし: Brewfile はすでに適用済みです。"; \
	   exit 0; \
	 fi; \
	 if [ "$(BACKUP)" = "1" ]; then \
	   mkdir -p "$(BACKUP_DIR)"; \
	   brew bundle dump --force --file="$(BACKUP_DIR)/Brewfile" 2>/dev/null && \
	     echo "  BACKUP  $(BACKUP_DIR)/Brewfile" || true; \
	 fi; \
	 DOTFILES_DIR="$(DOTFILES_DIR)" bash macos/apply_brewfile.sh --force; \
	 DOTFILES_DIR="$(DOTFILES_DIR)" bash macos/update_brewcache.sh

brew-sync: ## 現在の Homebrew 状態を Brewfile に同期
	@bash macos/sync_brewfile.sh

brew-cache: ## 現在の Homebrew 状態を Brewfile.cache に記録
	@bash macos/update_brewcache.sh

brew-diff: ## Brewfile.cache と Brewfile の差分を表示
	@bash macos/diff_brewfile.sh || true

npm: ## npmfile を適用（差分なしはスキップ、適用後に cache 更新）
	@if DOTFILES_DIR="$(DOTFILES_DIR)" bash npm/diff_npmfile.sh; then \
	   echo "差分なし: npmfile はすでに適用済みです。"; \
	   exit 0; \
	 fi; \
	 DOTFILES_DIR="$(DOTFILES_DIR)" bash npm/apply_npmfile.sh

npm-sync: ## 現在の npm グローバルパッケージ状態を npmfile に同期
	@DOTFILES_DIR="$(DOTFILES_DIR)" bash npm/sync_npmfile.sh

npm-cache: ## 現在の npm グローバルパッケージ状態を npmfile.cache に記録
	@DOTFILES_DIR="$(DOTFILES_DIR)" bash npm/update_npmcache.sh

npm-diff: ## npmfile.cache と npmfile の差分を表示
	@DOTFILES_DIR="$(DOTFILES_DIR)" bash npm/diff_npmfile.sh || true

pipx: ## pipxfile を適用（差分なしはスキップ、適用後に cache 更新）
	@if DOTFILES_DIR="$(DOTFILES_DIR)" bash pipx/diff_pipxfile.sh; then \
	   echo "差分なし: pipxfile はすでに適用済みです。"; \
	   exit 0; \
	 fi; \
	 DOTFILES_DIR="$(DOTFILES_DIR)" bash pipx/apply_pipxfile.sh

pipx-sync: ## 現在の pipx パッケージ状態を pipxfile に同期
	@DOTFILES_DIR="$(DOTFILES_DIR)" bash pipx/sync_pipxfile.sh

pipx-cache: ## 現在の pipx パッケージ状態を pipxfile.cache に記録
	@DOTFILES_DIR="$(DOTFILES_DIR)" bash pipx/update_pipxcache.sh

pipx-diff: ## pipxfile.cache と pipxfile の差分を表示
	@DOTFILES_DIR="$(DOTFILES_DIR)" bash pipx/diff_pipxfile.sh || true

macos: ## macOS のデフォルト設定を適用
	@bash macos/defaults.sh

dock: ## Dock アプリ・Finder サイドバーを適用（差分なしはスキップ、適用後に cache 更新）
	@if DOTFILES_DIR="$(DOTFILES_DIR)" bash macos/diff_dockfile.sh; then \
	   echo "差分なし: Dock はすでに適用済みです。"; \
	   exit 0; \
	 fi; \
	 if [ "$(BACKUP)" = "1" ]; then \
	   mkdir -p "$(BACKUP_DIR)"; \
	   if [[ -f "$(PRIVATE_DIR)/macos/dockfile.cache" ]]; then \
	     cp "$(PRIVATE_DIR)/macos/dockfile.cache" "$(BACKUP_DIR)/dockfile.cache" && \
	       echo "  BACKUP  $(BACKUP_DIR)/dockfile.cache" || true; \
	   fi; \
	 fi; \
	 DOTFILES_DIR="$(DOTFILES_DIR)" bash macos/apply_dockfile.sh

dock-sync: ## 現在の Dock・サイドバーを dockfile に同期
	@bash macos/sync_dockfile.sh

dock-cache: ## 現在の Dock 状態を dockfile.cache に記録
	@bash macos/update_dockcache.sh

dock-diff: ## dockfile.cache と dockfile の差分を表示
	@bash macos/diff_dockfile.sh || true

check: ## シンボリックリンクの整合性を確認
	@bash scripts/check.sh

init: ## このマシン用のホスト固有設定テンプレートを生成
	@bash scripts/init-host.sh

private: ## dotfiles-private を GitHub からクローン・更新
	@bash scripts/setup-private.sh
