# File Map

_最終更新: 2026-10-01_

全ファイルを網羅する必要はない。AI が参照・編集したファイルを作業のたびに追記していく運用（[DOCS_STRUCTURE.md](dev-charter/DOCS_STRUCTURE.md) 参照）。

## claude-perms

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `bin/unix/claude-perms` | `settings.local.json`/`settings.json`のpermissions整理、pathRuleベースの一括配布（`merge`＝追記／`apply`＝置き換え、pathGlobは文字列/配列いずれも可）、`candidates --json`/`remove --json`によるローカル未カバーallowのJSON出力・一括削除、run-quiet修飾版の自動補完 | `~/.claude/settings.json`、`~/.claude/claude-perms.json`（実体は`dotfiles-private/ai/claude/claude-perms.json`） |
| `completions/_claude-perms` | `claude-perms`のzsh補完 | `bin/unix/claude-perms` |

## dots verb table

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `bin/unix/_dots-verbs.sh` | ドメイン×動詞（apply/diff/sync/merge/prune/cache）の状態（ok/na/todo）、N/Aの理由、共通オプションの許可、動詞ゲート、`dots help`・`dots verbs` の生成元（正本） | `bin/unix/dots`（source） |
| `bin/windows/dots.ps1`（`$verbSpecs`） | Windowsで使えるドメイン（ghq・winget・ai・claude・codex・copilot）の同形式のテーブルと動詞ゲート | `scripts/check-dots-verb-table.sh`（Unix側との一致を検証） |
| `scripts/check-dots-verb-table.sh` | Unix側テーブルを正本に、READMEの動詞表とWindows側テーブルの一致を検証（pre-commit） | `README.md`、`bin/unix/dots verbs`、`bin/windows/dots.ps1` |
| `scripts/test-dots-verbs.sh` | 動詞ゲートとnpm/pipxの`apply`・`prune`・`sync`・`merge`の回帰テスト（Unix版のみ。偽の`npm`/`pipx`を使う） | `bin/unix/dots`、`npm/*.sh`、`pipx/*.sh` |
| `npm/{apply,diff,prune,sync,update_npmcache}...sh` / `pipx/...` | npm・pipxの動詞実装。`--dry-run`・`--no-prune`・`--yes`・`--backup-dir` を受け付ける | `npm/npmfile`・`pipx/pipxfile`、各`*.cache`（gitignore） |

## ghq-status / ghq-update

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `bin/unix/ghq-status` | ghq 管理下の全リポジトリの git 状態・BRANCHES・dev-charter追従・keep-up-to-date を一覧表示 | `.gitattributes`（repo-main-branch、repo-protected-branches、repo-remote-only-branches）、属性未設定時の`local.repo-*`、`local.status-ignore-charter-outdated` |
| `bin/unix/ghq-update` | ghq 管理下リポジトリの fetch/pull と uv/npm 同期、upstream fork sync、ロックファイル更新の自動PR | `git config local.keep-up-to-date`、`upstream` remote、`bin/ghq-upstream-pr-allow` |
| `bin/unix/ghq-pull` | ghq 管理下リポジトリ全件に `git-pull-all` を実行（ロックファイル stash 付き） | `bin/unix/git-pull-all`、`bin/unix/_ghq-lib.sh` |
| `bin/unix/ghq-sweep` | ghq 管理下リポジトリの `git-sweep --all` 一括実行 | `bin/unix/git-sweep` |
| `bin/unix/my-hosts` | 宣言した他のMacで`ghq-pull`/`ghq-update`/`ghq-sweep`と`ghq-status`、`install-my-apps`をサブコマンド（`status`/`pull`/`sweep`/`update`/`apps`）に応じてssh経由で実行し、結果表を出す（macOS専用。詳細は[specification.md#my-hosts](specification.md#my-hosts)） | `dotfiles-private/hosts/hosts`・`.local`、`ssh`、`scutil`、`install-my-apps`、`scripts/test-my-hosts.sh`（回帰テスト） |
| `bin/unix/_ghq-lib.sh` | ghq-pull/ghq-update/ghq-sweep共通関数（ロックファイルstash、`git-pull-all`の呼び出し、自動PRのPR先解決） | `bin/unix/_git-fork-lib.sh`、`bin/unix/git-pull-all`、`bin/ghq-upstream-pr-allow` |
| `bin/unix/_git-fork-lib.sh` / `bin/windows/_git-fork-lib.ps1` | GitHub標準のfork運用（`upstream` remote）の共通関数（owner/repo解決、`gh repo sync`によるupstream→origin同期）。ghqを前提としないため`git-sweep`からも直接利用する | `upstream` remote |
| `bin/ghq-upstream-pr-allow` | 自動PR機能がfork元（upstream）へPRしてよい`owner/repo`パターンの許可リスト | `bin/unix/_ghq-lib.sh`、`bin/windows/_ghq-lib.ps1`、`shell/zshrc`（`gh()`） |
| `shell/zshrc`（`gh()`関数） | `upstream` remoteがあり許可リストに一致するリポジトリで、`gh pr create --repo <origin>`を拒否（うっかり防止） | `bin/ghq-upstream-pr-allow` |
| `ghq/keep-up-to-date.sh` / `ghq/keep-up-to-date.ps1` | `local.keep-up-to-date`の宣言管理（`dots ghq {apply\|diff\|sync\|merge}`と`dots check`の要約。詳細は[specification.md#dots-ghq](specification.md#dots-ghq)） | `dotfiles-private/ghq/keep-up-to-date`・`.local`、`git config local.keep-up-to-date`、`ghq root`/`ghq list -p`、`scripts/test-ghq-keep-up-to-date.sh`（Unix版回帰テスト） |
| `bin/unix/git-pull-all` / `bin/windows/git-pull-all.ps1` | 1リポジトリの全ローカルブランチのfast-forward同期（現在ブランチはpull、他は作業ツリーを動かさず同期。upstream fork sync含む） | `bin/unix/_git-fork-lib.sh` / `_git-branch-lib.sh`（Windowsは`.ps1`）、`scripts/test-git-pull-all.sh`（Unix版回帰テスト） |
| `bin/unix/git-sweep` / `bin/windows/git-sweep.ps1` | マージ済みブランチの自動整理（`git-pull-all`のあと削除。dirty worktree・他worktree使用中ブランチの保護、squash/rebase merge内容検証。詳細は[specification.md](specification.md#git-pull-all--git-sweep--ghq-pull--ghq-update--ghq-sweep--my-hosts)） | `bin/unix/git-pull-all`、`_git-branch-lib.sh` / `_git-branch-lib.ps1`、`.gitattributes`（repo-main-branch、repo-protected-branches）、属性未設定時の`local.repo-*`、`scripts/test-git-sweep.sh`（Unix版回帰テスト） |
| `bin/unix/_git-branch-lib.sh` / `bin/windows/_git-branch-lib.ps1` | ブランチ方針（main/protectedの解決）とworktree判定の共通関数。`git-sweep`と`git-pull-all`が共有する | `.gitattributes`、`local.repo-*` |
| `bin/unix/obsidian-project-home` / `bin/windows/obsidian-project-home.ps1` | Git `origin`と通常領域Project Homeの`repositories`を正規化して一意に解決。本文・Privateは探索せず、未登録・重複・不正設定を終了コードで明示する | `dotfiles-private/obsidian/project-home-resolver.conf`、`templates/dotfiles-private/obsidian/project-home-resolver.conf.example`、`scripts/test-obsidian-project-home.sh` |

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
| `bin/unix/dots` | 個別エージェント操作と `dots ai` による Claude Code・Codex の一括操作。`check`（非verbose）はmacOSの sudo Touch IDを含む環境差分を検査し、結果キャッシュ（`~/.cache/dots/{check-summary,check-state,check-digest}`）も実行の都度書き込む | `ai/{claude,codex}/{mcp,plugin}/`、`ai/skills/`、`/etc/pam.d/sudo{,_local}`、`~/.cache/dots/` |
| `bin/windows/dots.ps1`（`Invoke-AiAgent`） | Windows版の `dots {ai|claude|codex|copilot}`。同名の `ai/**/{apply,diff,prune}.ps1` を子プロセスで実行する | `ai/**/*.ps1`、`ai/_common.ps1` |
| `ai/_common.ps1` | `ai/` 配下の `*.ps1` が dot source する共通関数（JSON読込、集合演算、外部コマンド実行、バックアップ退避、skill のリンク判定）。想定外のエラーは終了コード2で終え、diffの「差分あり」（1）と区別する | — |
| `ai/{claude,codex}/{mcp,plugin}/*.ps1`、`ai/copilot/mcp/*.ps1`、`ai/skills/*.ps1` | 各 `*.sh` のPowerShell移植（pythonの代わりに `ConvertFrom-Json -AsHashtable`）。codex の plugin は `codex app-server` と標準入出力のJSON-RPCで通信する | 各エージェントのCLI、`ai/_common.ps1` |

## dots check Monitor (macOS)

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `macos/com.y-marui.dotfiles-check.plist` | ログイン時・1時間ごとの`dots check`実行を定義 | `~/.local/bin/dots-check-monitor` |
| `macos/dots-check-monitor.sh` | `dots check`実行（結果キャッシュ自体は`bin/unix/dots`が書く）と状態変化時のmacOS通知（terminal-notifier優先、未導入時はosascriptへフォールバック）。`dots`コマンドが見つからない場合のみ例外的に自らキャッシュへ書き込む | `~/.local/bin/dotfiles/dots`、`~/.cache/dots/`、`terminal-notifier` |
| `macos/dots-check-monitor-popup.sh` | 通知クリック時に`check-summary`全文をダイアログ表示し、コピー/閉じるを選ばせる | `~/.cache/dots/check-summary` |
| `macos/*_keyboard_shortcuts.sh` | アプリケーションショートカットの適用・差分・同期・キャッシュ更新 | `macos/keyboard_shortcuts.py`、`dotfiles-private/macos/keyboard-shortcuts.plist` |
| `macos/keyboard_shortcuts.py` | `NSUserKeyEquivalents` を読み取り、管理ファイルと同期（applyは完全一致・未管理項目を削除、mergeは現在値を取り込み） | `defaults`、`dotfiles-private/macos/keyboard-shortcuts.plist` |
| `macos/setup_dots_check_launchagent.sh` | LaunchAgentの登録・解除 | `~/Library/LaunchAgents/com.y-marui.dotfiles-check.plist` |
| `macos/profile` | macOS共通のHomebrew・TeX・SQLite関連環境変数 | `~/.profile.macos`、`shell/profile` |
| `shell/zshrc` | キャッシュ済み警告だけをシェル起動時に表示 | `~/.cache/dots/check-summary` |
| `bin/windows/dots.ps1`（`Get-CheckSummary`・`Invoke-CheckVerbose`・`Write-CheckCache`）、`terminal/powershell/profile.ps1` | Windows版の`dots check`。リンク・backup蓄積・Git状態・winget・ghq・AI（claude・codex・copilot）の要約を同じ書式で出し、同じキャッシュへ書く。profileがキャッシュをシェル起動時に表示する。LaunchAgent相当の定期実行・通知とmacOS固有項目（brew・dock・shortcuts・sudo Touch ID）は対象外 | `~/.cache/dots/check-summary`、`ai/**/*.ps1` |

## Self-hosted Runner (macOS)

private リポジトリの macOS ジョブを手元の Mac で実行する、ネイティブの GitHub Actions runner の登録・解除。
専用の標準ユーザーで LaunchDaemon として常駐する。構成・立ち上げ手順・運用は
[self-hosted-runner.md](self-hosted-runner.md)。

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `macos/setup_actions_runner.sh` | `install`/`status`/`uninstall`。private リポジトリだけを受け付け、runner のアーカイブを公式の sha256 と照合し、`~ghrunner/actions-runner/<repo>` に展開して登録、`DEVELOPER_DIR` を固定、`/Library/LaunchDaemons/com.y-marui.actions-runner.<repo>.plist` を作って常駐させる。`--dry-run` で実行内容だけ表示 | `gh`、`sudo`、`launchctl`、runner の公式リリース（`actions/runner`）、`/Applications/Xcode-<version>.app` |
| `docs/self-hosted-runner.md` | 構成・設計判断・Mac の追加手順・デプロイキー・運用・トラブルシューティング | `macos/setup_actions_runner.sh` |

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
