# GitHub Copilot Instructions — dotfiles

## このリポジトリ

macOS の開発環境設定（シェル・Git・エディタ・ターミナル・AI ツール）を
シンボリックリンクで複数 Mac に展開する dotfiles リポジトリ。
詳細は `AI_CONTEXT.md` を参照。

## よく使うコマンド

- `make install` — シンボリックリンクを展開
- `make check` — リンク整合性を確認
- `make update` — git pull + 再インストール
- `shellcheck scripts/*.sh` — シェルスクリプトの静的解析

## 必須ルール

- `host/` 配下・`scripts/.env` はコミットしない
- `shell/profile` と `shell/bashrc` に zsh 固有構文（`[[` 等）を書かない
- 既存ファイルを変更する前に `make check` を実行する
- `~/.gitconfig.local` の内容をリポジトリ内ファイルにコピーしない

## zprezto

`~/.zprezto` 本体はこのリポジトリで管理しない。
`shell/zpreztorc` のみリンク対象。
