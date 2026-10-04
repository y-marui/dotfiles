# dotfiles — AI Context

## Reference Order

AI はタスク開始時に以下の順で参照する:

1. [README.md](README.md)（概要・セットアップ）
2. [DEVELOPING.md](DEVELOPING.md)（ビルド・実装規約・命名規則）

必要に応じて以下を参照する（順不同）:
- [CONTRIBUTING.md](CONTRIBUTING.md)（PR・Issue ルール）
- [docs/architecture.md](docs/architecture.md)（モジュール・コンポーネント構造）
- [docs/file-map.md](docs/file-map.md)（ファイルレベルの依存関係 ※情報が足りない・古い場合は適宜探索し、追記・更新する）
- [docs/specification.md](docs/specification.md)（コマンドの動作定義）
- [docs/ui-design.md](docs/ui-design.md)（UI 設計。本リポジトリは該当なし）

## Applied Charter Principles

憲章参照: [docs/dev-charter/CHARTER_INDEX.md](docs/dev-charter/CHARTER_INDEX.md) でトピックを特定してから該当ファイルのみ読む（`docs/dev-charter/` は `git subtree` 導入、直接編集禁止）。

このプロジェクトの開発・運用フローに直接影響する原則は、以下の各セクションに実装済み（重複転記しない）:
- ドキュメント構成（README/DEVELOPING/CONTRIBUTING/docs/）: [DOCS_STRUCTURE.md](docs/dev-charter/DOCS_STRUCTURE.md)
- AI コンテキストファイルの構成: [AI_TOOL_SETUP.md](docs/dev-charter/AI_TOOL_SETUP.md)
- Issue/Project運用: [topics/GITHUB_PROJECT_MANAGEMENT.md](docs/dev-charter/topics/GITHUB_PROJECT_MANAGEMENT.md)（→「ドキュメントとタスクの管理」節）
- セキュリティ・pre-commit: [SECURITY_POLICY.md](docs/dev-charter/SECURITY_POLICY.md)（→ `.pre-commit-config.yaml`）

## AI Tool Assignments

- **使用ツール**：Claude Code、Codex、GitHub Copilot
- **標準担当の正本**：`docs/dev-charter/AI_COLLABORATION_RULES.md` の「AI Tool Responsibilities」と「Rules for Multi-AI Usage」
- **プロジェクト固有の上書き**：
  - Codex へのPRレビュー依頼は、対象PRに `@codex review` とコメントする
    （GitHub App `chatgpt-codex-connector` がこのリポジトリに導入済み）。結果は
    インクリメンタルに表示されず、完了時に一括で反映される
  - tokenを消費するため、AIがこのコメントを投稿する場合は依頼前に必ずユーザーへ確認する
    （`codex review` / `codex exec` 経由でのレビュー依頼も同様に、実行前にユーザーへ確認する）

## Purpose of This Repository

macOS・Raspberry Pi・Windows の開発環境設定（シェル・Git・エディタ・ターミナル）を一元管理し、
シンボリックリンクを通じて設定を共有するための dotfiles リポジトリ。

## Environment

- OS: macOS（メイン）、Raspberry Pi OS（Linux / サブ）、Windows（サブ）
- Shell: zsh（zprezto + Powerlevel10k）— macOS / Raspberry Pi
- Shell: bash — macOS / Raspberry Pi（副）
- Shell: PowerShell（Oh My Posh）— **Windows のみ**（Windows で zsh は使わない）
- Terminal: iTerm2（macOS）、Windows Terminal（Windows）
- Terminal multiplexer: Zellij（全プラットフォーム共通）
- Mac: 複数台（ホスト名で差分管理）
- Version managers: pyenv, rbenv, nodebrew
- Editor: Vim, VSCode
- AI: Codex、Claude Code、GitHub Copilot

## Platform-Specific Setup

| プラットフォーム | インストール方法 |
|---|---|
| macOS / Linux | `make install`（内部で bash スクリプトを実行） |
| Windows | `mingw32-make install`（内部で `pwsh scripts/install.ps1` 等を実行） |

`make links` / `make check` / `make uninstall` も同様に `$(OS)` を見て
Windows では対応する `scripts/*.ps1` を、それ以外では `scripts/*.sh` を実行する
（`Makefile` 内で分岐）。隣接する `dotfiles-private` があれば、同リポジトリの
`links.conf` に宣言されたリンクも扱う。

## OS-Specific Implementation Policy

- macOS / Raspberry Pi 向けスクリプトは zsh / bash / sh でネイティブに実装する
- Windows 向けスクリプトは PowerShell でネイティブに実装する（Windows で zsh は使わない）
- 他 OS 向けの実装（bash スクリプト等）を `*.cmd` 等のラッパー経由で別 OS から
  呼び出す設計は避け、各 OS のネイティブシェルで書き直す
  （例: `bin/windows/dots.ps1` は `bin/unix/dots`（bash版）のロジックをPowerShellに
  移植したもの。`bin/windows/*.ps1` は全てこのパターン）
- Windows で bare コマンド名（拡張子なし）から呼べるようにするには `*.cmd` シムが必須。
  `$env:PATHEXT` に `.PS1` は含まれておらず、`pwsh -File` を呼ぶだけの薄い `*.cmd`
  （`bin/windows/dots.cmd` 等）と併置する構成にする。これは PowerShell の意図的な
  セキュリティ設計（なりすまし実行やダブルクリックでの誤実行を防ぐため）であり
  回避すべきではない
- `bin/unix/`（拡張子なしのbash/zshスクリプト）と `bin/windows/`（`*.ps1` + `*.cmd`）
  は別ディレクトリに分離する。同じ `bin/` に混在させると、Unix側で `bin` 全体を
  `~/.local/bin/dotfiles` へリンクした際に `*.cmd` が紛れ込んでしまうため
- **コマンドは原則両OSに実装し、`bin/unix/` と `bin/windows/` の対応関係を保つ**
  （片方専用は明確な理由がある場合のみ許容: 例 `install-my-apps` はmacOS専用の
  .appインストーラー）。`scripts/check-bin-parity.sh` が pre-commit でこの対応
  関係を検証する。片方専用にする場合はスクリプト内の `EXCEPTIONS` に理由を追記する
- `bin/` 以外の `.sh`/`.ps1` も同様に対応関係を保つのが原則。OS固有で片方にしか
  存在しないと分かっているもの（macOS/Raspberry Pi専用スクリプト、Windows専用の
  `dots.ps1` 未実装サブコマンド向けスクリプト等）だけ、理由付きで例外にする。
  `scripts/check-sh-ps1-parity.sh` が pre-commit でこの対応関係を検証する。
  片方専用にする場合はスクリプト内の `EXCEPTIONS` に理由を追記する

## Zellij Auto-Attach and SSH Wrapper

挙動の説明は README の「Zellij Auto-Attach & SSH Wrapper」を参照する。実装で守る点:

- 起動条件: macOS は `$TERM_PROGRAM == "iTerm.app"` または `$SSH_CONNECTION`、Raspberry Pi は
  `$SSH_CONNECTION` のみ、Windows(pwsh) は `$env:WT_SESSION` または `$env:SSH_CONNECTION`
- `NO_ZELLIJ=1` または `$ZELLIJ` 設定済みならスキップ。エディタ等のサブプロセスのシェルも条件外でスキップ
- Windowsは対話的なWindows Terminal/SSH接続でホスト名セッションを作成し、切断後もZellijサーバーを維持する。
  入力不能を避けるため`attach --create-background`やScheduled Taskによる事前作成は使わない
- WindowsのPowerShellプロファイルは`$env:SHELL`を`pwsh.exe`にし、専用設定
  `terminal/zellij/windows/config.kdl`でも`default_shell "pwsh.exe"`を明示する
- Zellijは macOS/Raspberry Pi で`0.45.1`、ネイティブWindowsで`0.44.3`に固定する
- macOSのiTerm2では、0.44.xでアイドル中の全画面再描画がCSI 2026（同期出力）で囲まれず点滅した
  （#31、0.45.1で解消）。固定版を更新するときは次を確認する:
  - iTerm2の通常シェルは常にZellij内になる（`zellij attach -c ... && exit`のため、デタッチでシェルが
    終了し再attachされる）。`NO_ZELLIJ=1`はネスト起動を止めないので、外側のZellijが描画して検証にならない。
    シェルを経由せず`osascript`で`create window with default profile command "env NO_ZELLIJ=1 script -q <log> <zellij> ..."`
    のように直接起動する
  - `script`のログで`ESC[?2026h`/`ESC[?2026l`が対応して出ること、出力の大半がその内側にあること、
    本番の`config.kdl`で数分アイドルにして点滅・プロンプト断片の重複・意図しない改行がないことを見る
  - 新しいバージョンは旧バージョンと別のセッション領域を使う（旧セッションには新クライアントから接続できない）
- `ssh` ラッパー（zsh/bash/pwsh共通）は Zellij 内で新タブ（既定・`--new`）、`--same` で縦分割ペインに接続し、
  接続先では auto-attach する。`--no-zellij` は `NO_ZELLIJ=1` を渡して無効化する

## Directory Structure and Responsibilities

```
dotfiles/
├── bin/
│   ├── unix/       # カスタムコマンド（zsh/bash、拡張子なし）— ~/.local/bin/dotfiles にリンク（Unix）
│   └── windows/    # カスタムコマンド（*.ps1 ネイティブ実装 + bareコマンド名用*.cmdシム）— 同（Windows）
├── shell/          # zsh / bash / sh 設定ファイル
├── git/            # gitconfig、gitignore_global、エイリアス
│   └── gitconfig.d/
├── terminal/       # Zellij、p10k、PowerShell 設定
├── karabiner/      # Karabiner-Elements 設定（macOS専用。詳細は docs/karabiner-rdp-jis.md）
├── ai/
│   ├── skills/     # Claude Code / Codex で共有する Agent Skills
│   ├── codex/      # Codex 固有の skill / plugin / MCP 宣言
│   ├── claude/     # Claude Code 固有の設定と skill / plugin / MCP 宣言
│   ├── copilot/    # GitHub Copilot 設定ドキュメント
├── macos/          # Brewfile、macOS defaults スクリプト
├── windows/        # WingetPin（winget一時pin宣言）
├── host/           # マシン固有設定（コミット対象外）
├── ghq/            # ghq-update の更新対象（keep-up-to-date）の宣言管理スクリプト（宣言ファイルは dotfiles-private）
├── scripts/        # install / uninstall / check / init スクリプト
├── docs/           # 設計ドキュメント
└── .github/        # GitHub / Copilot 設定
```

## Documentation and Task Management

このリポジトリでは、完成後も参照する設計・運用・確認・復旧・rollbackを `docs/` に残し、
進捗、期限、ブロッカー、調査途中の候補、実装チェックリストはGitHub Issue・sub-issue・Projectで
管理する。一時的な計画ファイルや完了済みTODOをリポジトリへ残さない。

仕様・ルール・構成に変更が生じたとき、変更と同じ作業内で関連ドキュメントを更新する。対象は
`docs/` 内のファイルに限らず、`AI_CONTEXT.md`・`README.md` 等のルートファイルも含む。Issueと
docsへ同じチェックリストを重複させない。公開リポジトリのため、実機固有のホスト名、IPアドレス、
鍵情報、不要なサービス構成はIssue・Project・docsに記載しない。

詳細な責務境界、引用元、整合性確認条件は `docs/project-management.md` を参照する。

## Shell File Responsibility Separation Rules

| ファイル | 書くもの | 書かないもの |
|---------|---------|------------|
| `shell/profile` | PATH、全シェル共通の環境変数 | zsh/bash 固有の構文（`[[` 等） |
| `shell/zshenv` | ZDOTDIR 等、全 zsh セッションで必要なもの | 対話的な設定、エイリアス |
| `shell/zshrc` | zprezto source、エイリアス、関数、補完、ツール初期化 | ログイン時のみ必要なもの |
| `shell/zprofile` | zsh login で必要な環境変数（Homebrew PATH 等） | 対話設定 |
| `shell/zlogin` | ログイン後の処理（通常は最小限） | 対話設定 |
| `shell/zlogout` | ログアウト時の後処理 | — |
| `shell/zpreztorc` | zprezto のモジュール・テーマ設定 | zprezto 以外の設定 |
| `shell/bashrc` | bash 対話設定、`source ~/.profile` | zsh 固有構文 |
| `shell/bash_profile` | `source ~/.bashrc` のみ | それ以外 |

## Secret Management Rules

- シークレットは絶対にコミットしない
- ローカル専用設定は `~/.zshrc.local` または `host/<hostname>.zsh` に書く
- Git の user 情報等は Private Gist で管理（`~/.gitconfig.d/` にシンボリックリンク）
- `make private` でprivateリポジトリを取得・更新し、`links.conf` のリンクを自動設定

## Frequently Used Commands

コマンド一覧は [README.md](README.md)（`make` 表・`dots` 動詞表）、動作定義は
[docs/specification.md](docs/specification.md) を参照する。変更時に外せない点:

- `dots verbs` / `dots <domain> help` の正本は `bin/unix/_dots-verbs.sh` の動詞テーブル。
  README の動詞表と `bin/windows/dots.ps1` は `scripts/check-dots-verb-table.sh`（pre-commit）が検証する
- `dots {npm|pipx} prune` は宣言にないパッケージを削除する（`--dry-run`・`--backup-dir`）。
  `apply` は追加後にpruneするため、無人経路は `--no-prune` を付ける
- `dots brew apply` は管理状態との差分だけを適用する（`--full` で全件、`--no-prune` でcleanup省略）
- `dots {claude|codex} apply/prune` と `dots ai` は、dotfiles管理境界内の宣言済み項目だけを対象にする
- `dots check` は zsh 起動時に `~/.cache/dots/check-summary` を表示するだけで、完了を待たない
  （macOSはLaunchAgentがログイン時と1時間ごとに実行し、状態変化時だけ通知）

## About zprezto

`~/.zprezto` 本体はこのリポジトリに含めず、外部 Git リポジトリとして管理する。
`scripts/setup-prezto.sh` が初回 clone、`scripts/update-prezto.sh` が fast-forward 更新と
サブモジュール同期を担当する。Powerlevel10k は Prezto のサブモジュールを使用し、
単独ではインストール・更新しない。設定ファイルは `shell/zpreztorc` のみリンク対象。

## Notes When Making Changes

- このリポジトリは `main` に直接 push 可能。memory/コンテキストの移管、Brewfile等の
  依存関係定義ファイルの追従的な更新、typo修正等の小さな変更、既存ドキュメント・skillの
  軽微な更新、既存スクリプトの回帰テスト付きバグ修正（実装済みのテストで動作を検証
  できる場合。例: `bin/unix/git-sweep` 等の過去の `fix:` commit群は全てmainへの直接
  commitで行われている）は、作業前にブランチを切る必要はない。新規スクリプトの追加、
  新規skillの追加や既存skillの大規模改修、プロジェクト全体構造（AIコンテキスト階層等）
  に関わるrefactoringは、ブランチを作成しPR経由でmainへ統合する（詳細は
  `~/.ai/AI_CONTEXT_CLI.md` の Scope-Based PR Requirement 参照）
- シェルスクリプトは ShellCheck を通す（`shellcheck scripts/*.sh`）
- シェルスクリプトの先頭に `set -euo pipefail` を書く
- 既存ファイルを変更する前に `make check` を実行する
- 不明な設定はユーザーに確認してから進める
- `host/` 配下はコミットしない（`.gitignore` 対象）
- `scripts/.env` はコミットしない
- `shell/profile` は sh 互換構文のみ（`[[` 不可）
- `~/.gitconfig.local` の内容をリポジトリ内ファイルにコピーしない
