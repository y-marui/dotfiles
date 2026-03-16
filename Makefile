SHELL      := /bin/bash
DOTFILES_DIR := $(CURDIR)
PRIVATE_DIR  := $(DOTFILES_DIR)-private
BACKUP_DIR   := $(HOME)/.dotfiles-backup/$(shell date +%Y%m%d%H%M%S)
BACKUP       := 0

.DEFAULT_GOAL := help

.PHONY: help install install-macos uninstall update brew brew-sync brew-cache brew-diff macos dock dock-sync dock-cache dock-diff check init private

help: ## コマンド一覧を表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

install: ## シンボリックリンクを展開してホームディレクトリに設定を反映
	@bash scripts/install.sh
	@if [[ -f "$(PRIVATE_DIR)/setup.sh" ]]; then \
	   bash $(PRIVATE_DIR)/setup.sh; \
	 else \
	   echo "  SKIP    dotfiles-private (make private でセットアップしてください)"; \
	 fi

install-macos: ## install + macos + brew + dock を一括適用（バックアップあり）
	@$(MAKE) install
	@$(MAKE) macos
	@$(MAKE) brew BACKUP=1 BACKUP_DIR="$(BACKUP_DIR)"
	@$(MAKE) dock BACKUP=1 BACKUP_DIR="$(BACKUP_DIR)"

uninstall: ## シンボリックリンクを削除
	@bash scripts/uninstall.sh

update: ## git pull --rebase して再インストール
	@git pull --rebase origin main
	@$(MAKE) install

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

macos: ## macOS のデフォルト設定を適用
	@bash macos/defaults.sh

dock: ## Dock アプリ・Finder サイドバーを適用（差分なしはスキップ、適用後に cache 更新）
	@if DOTFILES_DIR="$(DOTFILES_DIR)" bash macos/diff_dock.sh; then \
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
	 DOTFILES_DIR="$(DOTFILES_DIR)" bash macos/dock.sh

dock-sync: ## 現在の Dock・サイドバーを dock.sh に同期
	@bash macos/dock-sync.sh

dock-cache: ## 現在の Dock 状態を dockfile.cache に記録
	@bash macos/dock-sync.sh --snapshot-only

dock-diff: ## dockfile.cache と dock.sh の差分を表示
	@bash macos/diff_dock.sh || true

check: ## シンボリックリンクの整合性を確認
	@bash scripts/check.sh

init: ## このマシン用のホスト固有設定テンプレートを生成
	@bash scripts/init-host.sh

private: ## dotfiles-private を GitHub からクローン・更新
	@bash scripts/setup-private.sh
