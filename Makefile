SHELL := /bin/bash
DOTFILES_DIR := $(CURDIR)
PRIVATE_DIR  := $(DOTFILES_DIR)-private

.DEFAULT_GOAL := help

.PHONY: help install uninstall update brew brew-sync macos link dock dock-sync check init private

help: ## コマンド一覧を表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

install: ## シンボリックリンクを展開してホームディレクトリに設定を反映
	@bash scripts/install.sh

uninstall: ## シンボリックリンクを削除
	@bash scripts/uninstall.sh

update: ## git pull --rebase して再インストール
	@git pull --rebase origin main
	@$(MAKE) install

brew: ## Brewfile を適用（適用前に ~/.dotfiles-backup へバックアップ）
	@BACKUP_DIR="$(HOME)/.dotfiles-backup/$$(date +%Y%m%d%H%M%S)"; \
	 mkdir -p "$$BACKUP_DIR"; \
	 brew bundle dump --force --file="$$BACKUP_DIR/Brewfile" 2>/dev/null && \
	   echo "  BACKUP  $$BACKUP_DIR/Brewfile" || true; \
	 brew bundle --file=macos/Brewfile

brew-sync: ## 現在の Homebrew 状態を Brewfile に同期
	@brew bundle dump --force --file=macos/Brewfile
	@echo "Brewfile updated."

macos: ## macOS のデフォルト設定を適用
	@bash macos/defaults.sh

link: ## dotfiles-private のシンボリックリンクを設定
	@bash $(PRIVATE_DIR)/setup.sh

dock: ## Dock アプリ・Finder サイドバーを適用
	@bash $(PRIVATE_DIR)/macos/dock.sh

dock-sync: ## 現在の Dock・サイドバーを dock.sh に同期
	@bash macos/dock-sync.sh

check: ## シンボリックリンクの整合性を確認
	@bash scripts/check.sh

init: ## このマシン用のホスト固有設定テンプレートを生成
	@bash scripts/init-host.sh

private: ## dotfiles-private を GitHub からクローン・更新
	@bash scripts/setup-private.sh
