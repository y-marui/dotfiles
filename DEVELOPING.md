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

`bin/unix/git-sweep` を変更した場合は、使い捨てのgitリポジトリで回帰テストを実行する:

```bash
scripts/test-git-sweep.sh
```

`ghq/keep-up-to-date.sh` を変更した場合も、同様に使い捨ての ghq root で回帰テストを実行する
（`ghq` コマンドが必要。無ければスキップされる）:

```bash
scripts/test-ghq-keep-up-to-date.sh
```

`bin/unix/dots`・`bin/unix/_dots-verbs.sh` や `npm/`・`pipx/` の動詞スクリプトを変更した場合は、
動詞テーブル（N/A・未実装・オプションゲート）と npm / pipx の `apply` `prune` `sync` `merge` を、
一時ディレクトリと偽の `npm` / `pipx` で検証する（実環境には影響しない）:

```bash
scripts/test-dots-verbs.sh
```

動詞の実装状況を変えたときは、`bin/unix/_dots-verbs.sh` のテーブルを更新し、README の動詞表と
`bin/windows/dots.ps1` の `$verbSpecs` を合わせる（`scripts/check-dots-verb-table.sh` が
pre-commitで検証する。`dots verbs` で現在のテーブルを確認できる）。

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
引き続きGit configで管理する。ただし`local.keep-up-to-date`は、更新対象のリポジトリ
一覧をdotfiles-privateの`ghq/keep-up-to-date`（端末固有分は`.local`）に宣言し、
`dots ghq {diff|apply|sync|merge}`でGit configとの差分確認・同期ができる
（詳細は[specification.md](docs/specification.md#dots-ghq)）。

## Fork Upstream Sync / PR

GitHubのforkを`ghq`管理下に置く場合、fork元を指す標準の`upstream`という名前の
remote（`git remote add upstream <url>`）を設定しておくと、`ghq-pull`/`ghq-update`が
fetch/pullの前に`gh repo sync`で`upstream`のデフォルトブランチを`origin`（自分の
fork）・ローカル双方へfast-forward反映する（diverge時は警告のみで自動マージしない。
`gh`未インストール・未認証ならスキップ）。`upstream` remoteが無いリポジトリには
何もしない。

`ghq-update`の自動PR機能（`uv.lock`/`package-lock.json`更新）のPR先は通常`origin`
（自分のfork）のまま。`upstream` remoteがあり、かつその`owner/repo`が
[`bin/ghq-upstream-pr-allow`](bin/ghq-upstream-pr-allow)に列挙されたパターン
（globも可）に一致する場合のみ、`upstream`（fork元）へPRを作成する。許可対象は
今後増える見込みのため、このファイルに追記して管理する。

手動での`gh pr create`にも同じ許可リストを適用する。`shell/zshrc`の`gh()`
ラッパー関数（`git()`の`--no-verify`禁止と同じ、うっかり防止のための仕組み）が、
`upstream` remoteがあり`bin/ghq-upstream-pr-allow`で許可されたリポジトリに対して、
`--repo`で明示的に`origin`を指定した`gh pr create`を拒否する。`--repo`未指定なら
`gh`標準の「forkのデフォルトはparent（upstream）へPR」という挙動に任せるため、
このラッパーは何もしない。

## About docs/dev-charter/

`docs/dev-charter/` は [dev-charter](https://github.com/y-marui/dev-charter) を `git subtree` で取り込んだものであり、**直接編集しない**。変更が必要な場合は dev-charter リポジトリに Issue を立て、`git subtree pull` で取り込む。
