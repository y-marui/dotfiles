# Changelog

このリポジトリは個人の dotfiles であり、バージョンタグ付きリリースは行っていない。変更履歴は `git log` および各 Pull Request を正とする。

破壊的変更（シンボリックリンク先の変更、コマンドの削除・改名等）があった場合のみ、ここに記録する。

## Unreleased

- `install-my-apps`のインストール先を、`/Applications`直下から`/Applications/My Swift`（Swift）と`/Applications/My Tauri`（Tauri）に変更。種類は iCloud の`Build/Swift`・`Build/Tauri`の DMG の置き場で決める（移行前の`Build`直下はSwift扱い）。旧い置き場の同じ自作アプリを整理する`--migrate-old`は移行期間の措置で既定ON（新旧の両方にあるとき、App Store版、バンドルIDが違うときは消さない）。全Macの移行後に既定をOFFにする
- dev-charter lite 版を `docs/dev-charter/` に subtree で導入し、LICENSE・DEVELOPING.md・CONTRIBUTING.md・docs/architecture.md 等を追加
- dotfiles-privateのリンク操作を本リポジトリへ統合し、private側の`links.conf`をBash/PowerShell共通の宣言として扱う構成へ変更
- `.example`付きの未有効化private雛形を作る`make private-scaffold`と、隣接repoだけを条件付き検証する構造契約を追加
