SHELL := /bin/bash
DOTFILES_DIR := $(CURDIR)

.DEFAULT_GOAL := help

.PHONY: help install uninstall update brew macos check init private

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

brew: ## Brewfile からパッケージをインストール（Brewfile.local がなければ現在の状態をスナップショット）
	@[[ -f macos/Brewfile.local ]] || brew bundle dump --file=macos/Brewfile.local
	@brew bundle --file=macos/Brewfile

macos: ## macOS のデフォルト設定を適用
	@bash macos/defaults.sh

check: ## シンボリックリンクの整合性を確認
	@bash scripts/check.sh

init: ## このマシン用のホスト固有設定テンプレートを生成
	@bash scripts/init-host.sh

private: ## Private Gist からプライベート設定を取得
	@bash scripts/setup-private.sh
