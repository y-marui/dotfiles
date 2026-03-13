# CLAUDE.md

## このリポジトリについて

dotfiles リポジトリ。詳細は AI_CONTEXT.md を参照。

## 必須ルール

### セキュリティ

- APIキー・パスワード・トークンを絶対にファイルに書かない
- `host/` 配下のファイルをコミットしない
- `scripts/.env` をコミットしない
- `~/.gitconfig.local` の内容をリポジトリ内ファイルにコピーしない

### コード品質

- シェルスクリプトは必ず ShellCheck を通す（`shellcheck scripts/*.sh`）
- `set -euo pipefail` を全スクリプトの先頭に書く
- zsh 固有構文を `shell/profile`・`shell/bashrc` に書かない

### 作業フロー

- 既存ファイルを変更する前に `make check` を実行する
- 不明な設定はユーザーに確認してから進める
- 各ステップ完了時に git commit する

## zprezto について

`~/.zprezto` 本体はこのリポジトリで管理しない。
`shell/zpreztorc` のみリンク対象。
