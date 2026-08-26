# File Map

_最終更新: 2026-08-26_

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
