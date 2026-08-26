# File Map

_最終更新: 2026-08-27_

全ファイルを網羅する必要はない。AI が参照・編集したファイルを作業のたびに追記していく運用（[DOCS_STRUCTURE.md](dev-charter/DOCS_STRUCTURE.md) 参照）。

## ghq-status / ghq-update

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `bin/unix/ghq-status` | ghq 管理下の全リポジトリの git 状態・BRANCHES・dev-charter追従・keep-up-to-date を一覧表示 | `.gitattributes`（repo-main-branch、repo-protected-branches、repo-remote-only-branches）、属性未設定時の`local.repo-*`、`local.status-ignore-charter-outdated` |
| `bin/unix/ghq-update` | ghq 管理下リポジトリの fetch/pull と uv/npm 同期 | `git config local.keep-up-to-date` |
| `bin/unix/git-sweep` | マージ済みブランチの自動整理 | `.gitattributes`（repo-main-branch、repo-protected-branches）、属性未設定時の`local.repo-*` |

## dev-charter Installation

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `docs/dev-charter/` | dev-charter lite 版（`git subtree`、直接編集禁止） | `docs/dev-charter/VERSION` |
| `.pre-commit-config.yaml` | pre-commit フック定義（独自フック + dev-charter 準拠フック） | `scripts/check-*.sh` |
| `scripts/check-*.sh`（dev-charter系12本） | dev-charter の各憲章ルールを機械的に検証 | `docs/dev-charter/SECURITY_POLICY.md` |

## Private Links

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `scripts/_links.sh` / `scripts/_links.ps1` | privateのリンク対応表を検証してOS別リンク集合へ変換 | `../dotfiles-private/links.conf` |
| `scripts/install.sh` / `scripts/install.ps1` | public/privateリンクの作成、既存ファイルのバックアップ、非該当OSリンクの除去 | `scripts/_links.*` |
| `scripts/check.sh` / `scripts/check.ps1` | public/privateリンクの参照先を検査 | `scripts/_links.*` |
| `scripts/uninstall.sh` / `scripts/uninstall.ps1` | 各リポジトリを指す管理リンクだけを削除 | `scripts/_links.*` |
| `scripts/setup-private.sh` | privateリポジトリをclone/pullした後、共通リンク処理を実行 | `scripts/install.sh` |
| `templates/dotfiles-private/` | 未有効化のprivate雛形と公開可能な設定例 | `templates/dotfiles-private.contract` |
| `scripts/scaffold-private.sh` / `scripts/scaffold-private.ps1` | private雛形を新規ディレクトリへコピーしてGit初期化 | `templates/dotfiles-private/` |
| `scripts/check-private-contract.sh` / `scripts/check-private-contract.ps1` | privateの雛形同期・必須設定・実行ロジック不在を検証 | `templates/dotfiles-private/`, `templates/dotfiles-private.contract` |

## dots AI Management

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `bin/unix/dots` | 個別エージェント操作と `dots ai` による Claude Code・Codex・Gemini の一括操作 | `ai/{claude,codex,gemini}/{mcp,plugin}/`、`ai/skills/` |

## dots check Monitor (macOS)

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `macos/com.y-marui.dotfiles-check.plist` | ログイン時・1時間ごとの`dots check`実行を定義 | `~/.local/bin/dots-check-monitor` |
| `macos/dots-check-monitor.sh` | 結果キャッシュ更新と状態変化時のmacOS通知 | `~/.local/bin/dotfiles/dots`、`~/.cache/dots/` |
| `macos/setup_dots_check_launchagent.sh` | LaunchAgentの登録・解除 | `~/Library/LaunchAgents/com.y-marui.dotfiles-check.plist` |
| `shell/zshrc` | キャッシュ済み警告だけをシェル起動時に表示 | `~/.cache/dots/check-summary` |
