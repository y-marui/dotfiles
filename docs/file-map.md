# File Map

_最終更新: 2026-10-19_

全ファイルを網羅する必要はない。AI が参照・編集したファイルを作業のたびに追記していく運用（[DOCS_STRUCTURE.md](dev-charter/DOCS_STRUCTURE.md) 参照）。

## README and Reference Docs

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `README.md` | 概要・セットアップと、`docs/commands.md`・`ai-configuration.md`・`zellij-ssh-wrapper.md`・`local-settings.md`・`security-hooks.md` への入口 | 各文書 |

## Raspberry Pi Platform

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `rpi/bootstrap-platform.sh` | Trixieホスト基盤を再構築。Homebridgeの復元・起動は別工程 | パッケージ・links・Prezto・Tailscale・Docker・Zellij・gpg-agent |
| `rpi/repos/setup_docker.sh` | Docker公式DebianリポジトリとComposeプラグイン導入 | Docker署名鍵、systemd |
| `rpi/homebridge/compose.yaml` | 公式イメージ・hostネットワーク・永続データ・ログ制限・UI healthcheck | privateなimage digest/data path環境ファイル |
| `rpi/setup_pwm_fan.sh` | 確認済みGPIO12ファンのハードウェアPWMと旧サービス無効化 | インストール済み`pwm-fan` overlay、boot設定 |
| `docs/raspberry-pi-platform.md` / `docs/ssh-agent-zellij.md` | 運用・確認・rollbackの正本 | 上記管理設定、`rpi/setup_gpg_agent.sh`、`shell/zshrc` |

## Cloud sessions

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `scripts/cloud-bootstrap.sh` | クラウドVM向け。`setup`でAI設定・skillのlinkとSessionStartフック登録、`session`でdotfiles更新・private/vault取得・環境変数注入 | `scripts/_links.sh`、`ai/skills/apply.sh`、`ai/skills/cloud-code.json`、`jq`、環境変数のPAT |
| `ai/skills/cloud-code.json` | クラウドへ展開するskillの明示リスト | `ai/skills/*`、`ai/skills/external.json`、`scripts/check-skills.sh`（実在検証） |
| `ai/claude/rules/cloud-environment.md` | クラウドだけで読まれる補足規約（vaultはai/cloud/*ブランチのみ等） | `scripts/cloud-bootstrap.sh`（`~/.claude/rules/`へlink） |
| `scripts/test-cloud-bootstrap.sh` | 上記の副作用なし回帰テスト（一時HOME・ローカルgit） | `scripts/cloud-bootstrap.sh`、`ai/skills/apply.sh` |
| `docs/cloud-sessions.md` | 前提・設計・環境設定・確認・運用の正本 | 上記 |

## claude-perms

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `bin/unix/claude-perms` | `settings.local.json`/`settings.json`のpermissions整理、pathRuleベースの一括配布（`merge`＝追記／`apply`＝置き換え、pathGlobは文字列/配列いずれも可）、`candidates --json`/`remove --json`によるローカル未カバーallowのJSON出力・一括削除、run-quiet修飾版の自動補完 | `~/.claude/settings.json`、`~/.claude/claude-perms.json`（実体は`dotfiles-private/ai/claude/claude-perms.json`） |
| `bin/windows/claude-perms.ps1`・`claude-perms.cmd` | `bin/unix/claude-perms`のPowerShell版（`.cmd`はbareコマンド名用シム）。同じサブコマンド・正規化規則・出力で、zshのcdフック連携（`claude-perms shell`）だけ持たない。ホームは`$HOME`（テスト時は`CLAUDE_PERMS_HOME`で上書き） | `~/.claude/settings.json`、`~/.claude/claude-perms.json` |
| `completions/_claude-perms` | `claude-perms`のzsh補完 | `bin/unix/claude-perms` |

## dots verb table

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `bin/unix/_dots-verbs.sh` | ドメイン×動詞（apply/diff/sync/merge/prune/cache）の状態（ok/na/todo）、N/Aの理由、共通オプションの許可、動詞ゲート、`dots help`・`dots verbs` の生成元（正本） | `bin/unix/dots`（source） |
| `bin/windows/dots.ps1`（`$verbSpecs`） | Windowsで使えるドメイン（ghq・winget・ai・claude・codex・copilot）の同形式のテーブルと動詞ゲート | `scripts/check-dots-verb-table.sh`（Unix側との一致を検証） |
| `scripts/check-dots-verb-table.sh` | Unix側テーブルを正本に、docs/commands.mdの動詞表とWindows側テーブルの一致を検証（pre-commit） | `docs/commands.md`、`bin/unix/dots verbs`、`bin/windows/dots.ps1` |
| `scripts/test-dots-verbs.sh` | 動詞ゲートとnpm/pipxの`apply`・`prune`・`sync`・`merge`の回帰テスト（Unix版のみ。偽の`npm`/`pipx`を使う） | `bin/unix/dots`、`npm/*.sh`、`pipx/*.sh` |
| `npm/{apply,diff,prune,sync,update_npmcache}...sh` / `pipx/...` | npm・pipxの動詞実装。`--dry-run`・`--no-prune`・`--yes`・`--backup-dir` を受け付ける | `npm/npmfile`・`pipx/pipxfile`、各`*.cache`（gitignore） |

## ghq-status / ghq-update

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `bin/unix/ghq-status` | ghq 管理下の全リポジトリの git 状態・BRANCHES・dev-charter追従・keep-up-to-date を一覧表示 | `.gitattributes`（repo-main-branch、repo-protected-branches、repo-remote-only-branches）、属性未設定時の`local.repo-*`、`local.status-ignore-charter-outdated` |
| `bin/unix/ghq-update` | ghq 管理下リポジトリの fetch/pull と uv/npm 同期、upstream fork sync、ロックファイル更新の自動PR | `git config local.keep-up-to-date`、`upstream` remote、`bin/ghq-upstream-pr-allow` |
| `bin/unix/ghq-pull` | ghq 管理下リポジトリ全件に `git-pull-all` を実行（ロックファイル stash 付き） | `bin/unix/git-pull-all`、`bin/unix/_ghq-lib.sh` |
| `bin/unix/ghq-sweep` | ghq 管理下リポジトリの `git-sweep --all` 一括実行 | `bin/unix/git-sweep` |
| `bin/unix/ghq-build-deploy` | swift-\*/chrome-\*/tauri-\*（template除外）のリポジトリを対象に、Makefileに実在する候補ターゲット（deploy/ios/build等）だけを逐次`make`実行（macOS専用。詳細は[specification.md#ghq-build-deploy](specification.md#ghq-build-deploy)） | `ghq list -p`、`make`、`bin/ghq-build-deploy-targets`、`completions/_ghq-build-deploy`、`scripts/check-bin-parity.sh`（例外宣言）、`scripts/test-ghq-build-deploy.sh`（回帰テスト） |
| `bin/ghq-build-deploy-targets` | `ghq-build-deploy`の候補ターゲットを個別リポジトリ単位で上書きする宣言（既定のグループ判定・template除外より優先） | `bin/unix/ghq-build-deploy` |
| `bin/windows/update-wsl.ps1`（+ `.cmd`） | WSL登録のapt系ディストリビューションをrootで更新（Windows専用。`dots update`の最後に呼ぶ） | `wsl.exe`、`bin/windows/dots.ps1`、`scripts/check-bin-parity.sh`（例外宣言） |
| `bin/unix/my-hosts` | 宣言した他のMacで`ghq-pull`/`ghq-update`/`ghq-sweep`と`ghq-status`、`install-my-apps`をサブコマンド（`status`/`pull`/`sweep`/`update`/`apps`）に応じてssh経由で実行し、結果表を出す（実行元はmacOS専用、対象はWindowsも可。詳細は[specification.md#my-hosts](specification.md#my-hosts)） | `dotfiles-private/hosts/hosts`・`.local`、`ssh`、`scutil`、`install-my-apps`、`scripts/test-my-hosts.sh`（回帰テスト） |
| `bin/unix/install-my-apps` | iCloud Drive の `Build/Swift`・`Build/Tauri` の DMG から自作アプリを `/Applications/My Swift`・`/Applications/My Tauri` へインストール・削除する（macOS 専用。旧い置き場の整理は移行期間のオプション。詳細は[specification.md#install-my-apps](specification.md#install-my-apps)） | `hdiutil`、`scripts/test-install-my-apps.sh`（回帰テスト） |
| `bin/windows/install-my-apps.ps1` / `.cmd` | `install-my-apps`のWindows側スタブ（何もせず終了コード64を返す。`my-hosts apps`がWindowsの対象を`skip`扱いにする合図。詳細は[specification.md#my-hosts](specification.md#my-hosts)） | `bin/unix/my-hosts` |
| `bin/unix/_ghq-lib.sh` | ghq-pull/ghq-update/ghq-sweep共通関数（ロックファイルstash、`git-pull-all`の呼び出し、自動PRのPR先解決） | `bin/unix/_git-fork-lib.sh`、`bin/unix/git-pull-all`、`bin/ghq-upstream-pr-allow` |
| `bin/unix/_git-fork-lib.sh` / `bin/windows/_git-fork-lib.ps1` | GitHub標準のfork運用（`upstream` remote）の共通関数（owner/repo解決、`gh repo sync`によるupstream→origin同期。`gh`不可時はgit fetch/pushへフォールバック）。ghqを前提としないため`git-sweep`からも直接利用する | `upstream` remote、`scripts/test-git-fork-sync.sh`（Unix版回帰テスト） |
| `bin/ghq-upstream-pr-allow` | 自動PR機能がfork元（upstream）へPRしてよい`owner/repo`パターンの許可リスト | `bin/unix/_ghq-lib.sh`、`bin/windows/_ghq-lib.ps1`、`shell/zshrc`（`gh()`） |
| `shell/zshrc`（`gh()`関数） | `upstream` remoteがあり許可リストに一致するリポジトリで、`gh pr create --repo <origin>`を拒否（うっかり防止） | `bin/ghq-upstream-pr-allow` |
| `ghq/get.sh` | `host/role`が`work`の端末で、`dotfiles-private/ghq/get`・`.local`の宣言のうち未取得のものを`ghq get`（`dots ghq get`。Unixのみ。詳細は[specification.md](specification.md#dots-ghq-get)） | `scripts/host-role.sh`、`dotfiles-private/ghq/get`・`.local`、`ghq`、`scripts/test-ghq-get.sh`（回帰テスト） |
| `scripts/host-role.sh` | `host/role`（`DOTS_HOST_ROLE`で上書き可）から端末の役割（work / other / unset / invalid）を返す。`ghq/get.sh`と`pipx/apply_pipxfile.sh`、`dots check`が使う | `host/role` |
| `ghq/keep-up-to-date.sh` / `ghq/keep-up-to-date.ps1` | `local.keep-up-to-date`の宣言管理（`dots ghq {apply\|diff\|sync\|merge}`と`dots check`の要約。詳細は[specification.md#dots-ghq](specification.md#dots-ghq)） | `dotfiles-private/ghq/keep-up-to-date`・`.local`、`git config local.keep-up-to-date`、`ghq root`/`ghq list -p`、`scripts/test-ghq-keep-up-to-date.sh`（Unix版回帰テスト） |
| `bin/unix/git-pull-all` / `bin/windows/git-pull-all.ps1` | 1リポジトリの全ローカルブランチのfast-forward同期（現在ブランチはpull、他は作業ツリーを動かさず同期。upstream fork sync含む） | `bin/unix/_git-fork-lib.sh` / `_git-branch-lib.sh`（Windowsは`.ps1`）、`scripts/test-git-pull-all.sh`（Unix版回帰テスト） |
| `bin/unix/git-sweep` / `bin/windows/git-sweep.ps1` | マージ済みブランチの自動整理（`git-pull-all`のあと削除。dirty worktree・他worktree使用中ブランチの保護、squash/rebase merge内容検証。詳細は[specification.md](specification.md#git-pull-all--git-sweep--ghq-pull--ghq-update--ghq-sweep--my-hosts)） | `bin/unix/git-pull-all`、`_git-branch-lib.sh` / `_git-branch-lib.ps1`、`.gitattributes`（repo-main-branch、repo-protected-branches）、属性未設定時の`local.repo-*`、`scripts/test-git-sweep.sh`（Unix版回帰テスト） |
| `bin/unix/_git-branch-lib.sh` / `bin/windows/_git-branch-lib.ps1` | ブランチ方針（main/protectedの解決）とworktree判定の共通関数。`git-sweep`と`git-pull-all`が共有する | `.gitattributes`、`local.repo-*` |
| `bin/unix/obsidian-project-home` / `bin/windows/obsidian-project-home.ps1` | Git `origin`と通常領域Project Homeの`repositories`を正規化して一意に解決。本文・Privateは探索せず、未登録・重複・不正設定を終了コードで明示する。`ensure`は許可オーナーの未登録リポジトリにだけ雛形を作る | `dotfiles-private/obsidian/project-home-resolver.conf`、`templates/dotfiles-private/obsidian/project-home-resolver.conf.example`、`scripts/test-obsidian-project-home.sh` |

## dev-charter Installation

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `docs/dev-charter/` | dev-charter lite 版（`git subtree`、直接編集禁止） | `docs/dev-charter/VERSION` |
| `.pre-commit-config.yaml` | pre-commit フック定義（独自フック + dev-charter 準拠フック） | `scripts/check-*.sh` |
| `scripts/measure-doc-size.py` | AI_CONTEXT（`~/.ai/`と各リポジトリ直下）の行数・文ごとの表示幅・概算トークン数を測って表示する。`--inventory`で全リポジトリの棚卸し（目安の測定のみ、強制しない。doc-lintとの共通ロジックも持つ。詳細は[specification.md#measure-doc-size](specification.md#measure-doc-size)） | `ghq list -p`、`scripts/test-measure-doc-size.sh`（回帰テスト） |
| `bin/unix/doc-lint`・`bin/windows/doc-lint.ps1`・`doc-lint.cmd` | 手動でカレントのリポジトリの全Markdownを検査する薄いラッパー（`.cmd`はbareコマンド名用シム） | `scripts/doc-lint.py --all` |
| `scripts/doc-lint.py` | commit時にステージ済みMarkdownのサイズ・frontmatterを警告のみで検査し、逸脱をログへ記録する（`git/hooks/pre-commit`・`commit-msg`から呼ぶ。詳細は[specification.md#doc-lint](specification.md#doc-lint)） | `scripts/measure-doc-size.py`（共通ロジック）、`scripts/test-doc-lint.sh`（回帰テスト） |
| `scripts/vault-move-notes.py` | Obsidian Vaultのノート（.md）を`git mv`で移動・改名し、Vault全体の`[[...]]`のターゲットを検証付きで書き換える（commit・pushはしない。詳細は[specification.md#vault-move-notes](specification.md#vault-move-notes)） | `git`、`scripts/test-vault-move-notes.sh`（回帰テスト） |
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
| `bin/unix/dots` | 個別エージェント操作と `dots ai` による Claude Code・Codex の一括操作。`check`（非verbose）はmacOSの sudo Touch IDや`gh`の認証状態（失効・未ログイン・workflowスコープ欠落・macOSでのhosts.yml平文保存）を含む環境差分を検査し、結果キャッシュ（`~/.cache/dots/{check-summary,check-state,check-digest}`）も実行の都度書き込む | `ai/{claude,codex}/{mcp,plugin}/`、`ai/skills/`、`/etc/pam.d/sudo{,_local}`、`~/.cache/dots/` |
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
| `karabiner/complex_modifications/services-menu.json`、`karabiner/open-services.applescript` | `⌃⌥S`で前面アプリのサービス一覧を開く | `karabiner/karabiner.json`、`scripts/_links.sh`、`docs/services-menu-shortcut.md` |
| `macos/setup_dots_check_launchagent.sh` | LaunchAgentの登録・解除 | `~/Library/LaunchAgents/com.y-marui.dotfiles-check.plist` |
| `macos/profile` | macOS共通のHomebrew・TeX・SQLite関連環境変数 | `~/.profile.macos`、`shell/profile` |
| `shell/zshrc` | キャッシュ済み警告だけをシェル起動時に表示 | `~/.cache/dots/check-summary` |
| `bin/windows/dots.ps1`（`Get-CheckSummary`・`Invoke-CheckVerbose`・`Write-CheckCache`）、`terminal/powershell/profile.ps1` | Windows版の`dots check`。リンク・backup蓄積・`gh`の認証状態・Git状態・winget・ghq・AI（claude・codex・copilot）の要約を同じ書式で出し、同じキャッシュへ書く。profileがキャッシュをシェル起動時に表示する。LaunchAgent相当の定期実行・通知とmacOS固有項目（brew・dock・shortcuts・sudo Touch ID）は対象外 | `~/.cache/dots/check-summary`、`ai/**/*.ps1` |

## Self-hosted Runner (macOS)

private リポジトリの macOS ジョブを手元の Mac で実行する、ネイティブの GitHub Actions runner の登録・解除。
専用の標準ユーザーで LaunchDaemon として常駐する。構成・立ち上げ手順・運用は
[self-hosted-runner.md](self-hosted-runner.md)。

| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `macos/setup_actions_runner.sh` | `install`/`status`/`uninstall`。private リポジトリだけを受け付け、runner のアーカイブを公式の sha256 と照合し、`~ghrunner/actions-runner/<repo>` に展開して登録、`DEVELOPER_DIR` を固定、`/Library/LaunchDaemons/com.y-marui.actions-runner.<repo>.plist` を作って常駐させる。`--dry-run` で実行内容だけ表示 | `gh`、`sudo`、`launchctl`、runner の公式リリース（`actions/runner`）、`/Applications/Xcode-<version>.app` |
| `windows/setup_actions_runner.ps1` | macOS 版の Windows 版。`install`/`status`/`uninstall`。private リポジトリだけを受け付け、runner のアーカイブを公式の sha256 と照合し、`C:\actions-runner\<repo>` に展開（ACL を絞る）して、専用ユーザー `ghrunner` の Windows サービスとして登録する（ラベル `windows-sh`、runner 名 `<ホスト名>-<repo>-win`）。`-DryRun` で実行内容だけ表示 | `gh`、`git`、`dotnet`、管理者権限、runner の公式リリース（`actions/runner`） |
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

## Chat Archive Launcher

`bin/unix/chatgpt-export`・`bin/windows/chatgpt-export.ps1`（`.cmd` shim）は隣接する`chrome-chatgpt-exporter/cli/index.js`を起動するだけ。`CHATGPT_EXPORTER_ROOT`で場所を指定できる。実装・通信仕様・テストは拡張側で管理し、取得・読取順序は`ai/skills/obsidian-save-record/references/exported-chat.md`に集約する。

## Cinema Skills

| ファイル | 役割 | 主な依存先 |
| --- | --- | --- |
| `ai/skills/cinema-check-sendai/SKILL.md`・`references/` | 仙台3館の推薦と好み分析。通常はvaultの傾向だけ読む | 劇場公式サイト、Filmarks、vaultの映画の好み |
| `ai/skills/glance-task-add-movie/SKILL.md`・`scripts/movie_tasks.py` | 映画の同定・重複更新・開始日順登録・再取得検証 | Python 3.11以上、macOS、Glance TaskのAppleScript |
| `ai/skills/glance-task-add-movie/scripts/test_movie_tasks.py` | 実アカウントへ書かない登録処理の回帰テスト | 同梱CLI、標準unittest |
| `docs/cinema-skills.md` | 導入・個人データ境界・登録契約・復旧 | 上記skill、`make links`、`make check-skills` |

## Spotify Skills

| ファイル | 役割 | 主な依存先 |
| --- | --- | --- |
| `ai/skills/spotify-distribute-liked-songs/SKILL.md` | お気に入り曲の既存プレイリストへの振り分け | vaultの`knowledge/music/spotify-playlists.md`、`spotify-inventory`、`split-playlist` |
| `ai/skills/spotify-reorder-playlist-by-key/SKILL.md` | ユーザー提供のキー情報で曲順を変更 | `spotify-inventory`、`reorder-by-key`。移動対象ノートへの固定参照なし |
