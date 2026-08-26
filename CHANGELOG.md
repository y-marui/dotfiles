# Changelog

このリポジトリは個人の dotfiles であり、バージョンタグ付きリリースは行っていない。変更履歴は `git log` および各 Pull Request を正とする。

破壊的変更（シンボリックリンク先の変更、コマンドの削除・改名等）があった場合のみ、ここに記録する。

## Unreleased

- dev-charter lite 版を `docs/dev-charter/` に subtree で導入し、LICENSE・DEVELOPING.md・CONTRIBUTING.md・docs/architecture.md 等を追加
- dotfiles-privateのリンク操作を本リポジトリへ統合し、private側の`links.conf`をBash/PowerShell共通の宣言として扱う構成へ変更
- `.example`付きの未有効化private雛形を作る`make private-scaffold`と、隣接repoだけを条件付き検証する構造契約を追加
