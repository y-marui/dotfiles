# Developing

dotfiles リポジトリの開発者向けガイド。プロジェクト固有のルール・構成は [AI_CONTEXT.md](AI_CONTEXT.md) を参照。

## Build & Test

このリポジトリに専用のビルドプロセスはない。変更のたびに以下を実行する。

```bash
make check                          # シンボリックリンクの整合性確認
shellcheck scripts/*.sh bin/unix/*  # シェルスクリプトの静的解析
pre-commit run --all-files          # 全 pre-commit フックを実行
```

Windows 向け変更（`bin/windows/`、`*.ps1`）は PowerShell 上で動作確認する（`pwsh -File <script>.ps1`）。

## Conventions

詳細は [AI_CONTEXT.md](AI_CONTEXT.md) を参照。要点のみ:

- **OS 別実装**: macOS/Raspberry Pi は zsh/bash/sh ネイティブ、Windows は PowerShell ネイティブ。片方の実装をラッパー経由で呼び出さない（[AI_CONTEXT.md#OS別実装の方針](AI_CONTEXT.md)）
- **bin/unix ⇔ bin/windows・.sh ⇔ .ps1 の対応**: 原則両OSに実装する。片方専用にする場合は `scripts/check-bin-parity.sh` / `scripts/check-sh-ps1-parity.sh` の `EXCEPTIONS` に理由を追記する
- **シェルスクリプト**: 先頭に `set -euo pipefail`、ShellCheck 準拠
- **CLIコマンド**: `bin/unix/`・`bin/windows/` の新規カスタムコマンドは `-h`/`--help`
  （POSIX慣例と衝突しない範囲で `-h` も）を実装し、対応する `completions/_<name>`
  （zsh補完。`fpath` へ自動リンクされる）も用意する。AIが単体でスクリプトを呼び出す
  際にも仕様を把握できるようにするため
- **コミットメッセージ**: Conventional Commits 形式（`feat:` / `fix:` / `chore:` / `docs:` / `refactor:` 等）
- **シークレット**: コミットしない。ローカル専用設定は `~/.zshrc.local` または `host/<hostname>.zsh`

## Debugging

- `dots status` : dotfiles / dotfiles-private の未コミット・未push・未pull状態を確認
- `dots check`  : 全 AI Agent の MCP・plugin・skill 差分を一括確認
- `ghq-status`  : ghq 管理下の全リポジトリの git 状態・dev-charter追従状況を一覧表示

## Branch Policy Attributes

リポジトリ固有のブランチ運用方針は、各端末の`.git/config`ではなく、
リポジトリルートの`.gitattributes`へ宣言する。

```gitattributes
* repo-main-branch=develop
* repo-protected-branches=main,develop
* repo-remote-only-branches=lite
```

- `repo-main-branch`: `git-sweep`の統合先。`ghq-status`の自動判定にも使う
- `repo-protected-branches`: 削除を禁止し、ローカル・origin双方に存在する恒久ブランチ
- `repo-remote-only-branches`: ローカルには置かず、originだけに存在する恒久ブランチ

`git-sweep`のmain判定は、明示的なCLI引数、属性、ローカルGit config、`origin/HEAD`、
`main`の順。属性未設定の外部リポジトリでは、
`local.repo-main-branch`、`local.repo-protected-branches`、
`local.repo-remote-only-branches`をfallbackとして設定できる。属性がある場合、
ローカルconfigでは上書きしない。protected方針も未設定の場合は、解決したmain branchに
加えて、`main`が実在すれば安全のため両方を保護する。

旧`git-sweep-main`・`git-sweep-protected`属性と
`local.status-allowed-remote-branch`は既存リポジトリ向けの互換fallbackとしてのみ扱う。
`local.keep-up-to-date`と`local.status-ignore-charter-outdated`は端末・表示固有なので、
引き続きGit configで管理する。

## About docs/dev-charter/

`docs/dev-charter/` は [dev-charter](https://github.com/y-marui/dev-charter) を `git subtree` で取り込んだものであり、**直接編集しない**。変更が必要な場合は dev-charter リポジトリに Issue を立て、`git subtree pull` で取り込む。
