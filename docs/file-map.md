# File Map

_最終更新: 2026-09-02_

全ファイルを網羅する必要はない。AI が参照・編集したファイルを作業のたびに追記していく運用（[DOCS_STRUCTURE.md](dev-charter/DOCS_STRUCTURE.md) 参照）。

## claude-perms

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `bin/unix/claude-perms` | `settings.local.json`/`settings.json`のpermissions整理、pathRuleベースの一括配布（`sync`）、run-quiet修飾版の自動補完 | `~/.claude/settings.json`、`~/.claude/claude-perms.json`（実体は`dotfiles-private/ai/claude/claude-perms.json`） |
| `completions/_claude-perms` | `claude-perms`のzsh補完 | `bin/unix/claude-perms` |

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
| `macos/dots-check-monitor.sh` | 結果キャッシュ更新と状態変化時のmacOS通知（terminal-notifier優先、未導入時はosascriptへフォールバック） | `~/.local/bin/dotfiles/dots`、`~/.cache/dots/`、`terminal-notifier` |
| `macos/dots-check-monitor-popup.sh` | 通知クリック時に`check-summary`全文をダイアログ表示し、コピー/閉じるを選ばせる | `~/.cache/dots/check-summary` |
| `macos/*_keyboard_shortcuts.sh` | アプリケーションショートカットの適用・差分・同期・キャッシュ更新 | `macos/keyboard_shortcuts.py`、`dotfiles-private/macos/keyboard-shortcuts.plist` |
| `macos/keyboard_shortcuts.py` | `NSUserKeyEquivalents` を読み取り、管理ファイルと同期（applyは完全一致・未管理項目を削除、mergeは現在値を取り込み） | `defaults`、`dotfiles-private/macos/keyboard-shortcuts.plist` |
| `macos/setup_dots_check_launchagent.sh` | LaunchAgentの登録・解除 | `~/Library/LaunchAgents/com.y-marui.dotfiles-check.plist` |
| `macos/profile` | macOS共通のHomebrew・TeX・SQLite関連環境変数 | `~/.profile.macos`、`shell/profile` |
| `shell/zshrc` | キャッシュ済み警告だけをシェル起動時に表示 | `~/.cache/dots/check-summary` |

## Museum Status Refresh (macOS)

Glance Task の「美術展: 関東」「美術展: 東北」タスクを、AIを使わず毎週月曜8時に非対話で
ステータス絵文字更新・並べ替えする LaunchAgent。ステータス絵文字（🎟️開催中 / ⏳開催前 /
🏁開催終了 / ❌書式エラー）の判定ロジックは `glance-task-format-museum-events` skill の
`museum_events.py` に同居し、AI主導の `refresh` 以外のサブコマンドとは独立している。

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `macos/com.y-marui.museum-status-refresh.plist` | 毎週月曜8時の `museum-status-refresh` 実行を定義 | `~/.local/bin/museum-status-refresh` |
| `macos/museum-status-refresh.sh` | ステータス更新スクリプトを非対話で起動 | `~/.claude/skills/glance-task-format-museum-events/scripts/museum_events.py` |
| `macos/setup_museum_status_launchagent.sh` | LaunchAgentの登録・解除 | `~/Library/LaunchAgents/com.y-marui.museum-status-refresh.plist` |
| `ai/skills/glance-task-format-museum-events/scripts/museum_events.py` (`refresh` サブコマンド) | 日付からのステータス絵文字判定・書式エラーの末尾送り・書式エラー時のmacOS通知 | Glance Task.app（AppleScript） |
