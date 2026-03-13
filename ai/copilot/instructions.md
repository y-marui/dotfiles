# GitHub Copilot Instructions

## このリポジトリ

dotfiles リポジトリ。シェル設定・開発環境の管理。

## 補完時の注意

- zsh を優先しつつ bash 互換を維持する
- シークレット・APIキー・パスワードを補完しない
- シェルスクリプトは ShellCheck に準拠する
- ハードコードされたパスを避ける（`$HOME` を使う）
