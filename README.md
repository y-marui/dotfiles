# dotfiles

macOS を中心に、Raspberry Pi・Windowsでも共有する個人開発環境設定。
zsh (zprezto + Powerlevel10k) / Vim / Zellij / Codex + Claude Code + GitHub Copilot + Gemini CLI。

## Setup (New Machine)

詳細な手順は **[macOS](docs/setup-mac.md)** / **[Windows](docs/setup-windows.md)** を参照。

概要:

1. Homebrew をインストール（Apple Silicon は PATH の追加設定が必要）
2. SSH キーを生成して GitHub に登録
3. `brew install ghq` → `ghq get https://github.com/y-marui/dotfiles.git`
4. `scripts/setup-prezto.sh` で zprezto をインストール（`make install-macos` でも自動実行）
5. `make init` → ホスト固有設定を編集（`DOTFILES_DIR` の設定が必要）
6. `brew install gh && gh auth login` → `make private` でプライベート設定を取得
7. `make install-macos` → dotfiles 一括適用
8. iTerm2 の Shell Integration をインストール

## Command List

| コマンド | 説明 |
|---------|------|
| `make install` | OS別のフルセットアップを実行（Zellijの固定版を含む） |
| `make links` | public/privateのシンボリックリンクだけを再適用 |
| `make uninstall` | public/privateの管理リンクを削除 |
| `make check` | public/privateのリンク整合性確認 |
| `make launchagent` | macOSの`dots check`定期監視を再登録 |
| `make init` | ホスト固有設定テンプレートを生成 |
| `make private` | dotfiles-private をクローン・更新し、`links.conf` のリンクを適用 |
| `make private-scaffold` | `.example` 付きの安全な dotfiles-private 雛形を新規生成 |
| `make private-validate` | 隣接する dotfiles-private の雛形・必須構造を検証 |
| `make private-lint` | dotfiles-private のpre-commitを全ファイルに実行 |
| `make update-private-charter` | dotfiles-private のdev-charter subtreeを更新 |

初回セットアップ後の日常操作は、カレントディレクトリに依存しない `dots` を使用する。

| コマンド | 説明 |
|---------|------|
| `dots status` | dotfiles / dotfiles-private の未コミット・未push・未pullを確認 |
| `dots update` | dotfiles を更新・再リンクし、PreztoとOS別パッケージを更新 |
| `dots brew apply` | Brewfileと現在のHomebrew状態の差分だけを適用 |
| `dots brew apply --full` | Brewfile / Brewfile.localを従来どおり全件適用 |
| `dots brew diff` | Brewfileの差分を表示 |
| `dots brew sync` | 現在のHomebrew状態をBrewfileに同期 |
| `dots dock apply` | Dock・Finderサイドバーを適用 |
| `dots dock diff` | Dock・Finderサイドバーの差分を表示 |
| `dots dock sync` | 現在のDock・Finderサイドバーを管理ファイルに同期 |
| `dots shortcuts {apply\|diff\|sync\|merge\|cache}` | macOSのアプリケーションショートカットを管理（applyは管理ファイルと完全一致、mergeで現在値を先に取り込める） |
| `dots npm {apply\|diff\|sync\|cache}` | npmグローバルパッケージ設定を操作 |
| `dots pipx {apply\|diff\|sync\|cache}` | pipxパッケージ設定を操作 |
| `dots ai {apply\|diff\|prune}` | Claude Code・Codex・Gemini の MCP・plugin・skill を一括管理 |
| `dots commit` | sync系コマンドが書き換えたファイルのみの変更を自動commit |
| `dots push` | 未pushのcommitが自動commitのみならpush、対象外ファイルが混じれば手動pushを促す |

`dots status` は両リポジトリを `git fetch --prune` してから確認し、要対応の状態が
1つでもあれば終了コード1を返す。ネットワークへ接続せず、既存のremote-tracking refだけで
確認する場合は `dots status --no-fetch` を使用する。

`dots commit` は dotfiles / dotfiles-private それぞれの working tree を確認し、
`macos/Brewfile` / `macos/Brewfile.local` / `npm/npmfile` / `pipx/pipxfile`
（dotfiles-private側は `macos/dockfile` / `macos/keyboard-shortcuts.plist`）
だけが変更されている場合に限り、自動生成した Conventional Commits 形式のメッセージで
commitする。これら以外のファイルが1つでも変更に含まれる場合は何もcommitせず、
手動でのcommitを促す（自動commit対象のファイルだけを部分的にcommitすることはしない）。

`dots push` は各リポジトリでunpushedなcommit群の変更ファイルを調べ、全て上記の
自動commit対象ファイルだけであればpushする。対象外ファイルを含むcommitが1つでも
混在する場合はpushせず、該当ファイルを提示して手動pushを促す。

ZellijはOS別に互換性を確認したバージョンを固定する。macOS/Raspberry Piは
`scripts/setup-zellij.sh`で`0.43.1`を、Windowsは`scripts/setup-zellij.ps1`で
ネイティブWindows対応の`0.44.3`をユーザーローカルへインストールする。

### Custom Commands (`~/.local/bin/`)

`make install` で `~/.local/bin/` にシンボリックリンクが作成される。実装は
`bin/unix/`（zsh/bash、拡張子なし）と `bin/windows/`（`*.ps1` ネイティブ実装 +
bareコマンド名用の`*.cmd`シム）に分かれており、`scripts/check-bin-parity.sh`が
pre-commitで両者の対応関係を検証する。

| コマンド | 説明 |
|---------|------|
| `dots` | dotfilesとマシン環境を管理 |
| `run-quiet <cmd>` | コマンドをラップし、成功時は1行サマリーのみ出力。warning/deprecated 行は抜粋表示 |
| `git-sweep [--all] [main-branch]` | マージ済みブランチを整理（fast-forward・squash・rebase merge 対応） |
| `git-survey [main-branch]` | main以外のブランチをlocal/remote別に表示 |
| `ghq-pull [--fetch-only]` | ghq管理リポジトリ全件をfetch + pull |
| `ghq-update [--all\|--pull-all\|--uv-sync-only\|--pull-only\|--no-auto-pr]` | ghq管理リポジトリを更新（uv sync・npm update/build、lock自動PR含む） |
| `ghq-sweep` | ghq管理リポジトリ全件に`git-sweep --all`を実行 |
| `ghq-check [--sync]` | GitHub の全リポジトリの取得状況を確認。`--sync` で未取得リポジトリを `ghq get` |
| `ghq-status` | ghq 管理リポジトリの git 状態・ブランチをテーブル表示 |
| `sync-labpc <job-name\|host-ip\|all\|list>` | 測定器室PCのデータをSMB経由で一方向同期（macOS専用、ジョブ定義は`~/.config/labpc/jobs.d/`。`list`でジョブ一覧表示） |

## File Structure

| パス | 説明 |
|-----|------|
| `shell/` | zsh / bash 設定 |
| `git/` | Git 設定（公開分のみ） |
| `terminal/` | Zellij / p10k / PowerShell 設定 |
| `ai/` | Codex / Claude Code / Copilot / Gemini CLI 設定 |
| `macos/` | Brewfile / macOS デフォルト設定 |
| `host/` | ホスト固有設定（git 管理外） |
| `scripts/` | install / check 等のスクリプト |

## AI Configuration

グローバル共通指示は [`ai/AI_CONTEXT.md`](ai/AI_CONTEXT.md)（→ `~/.ai/AI_CONTEXT.md`）に集約し、各エージェントのグローバル設定ファイルからインポートまたは直接リンクしている。
リポジトリ固有のコンテキストは [`AI_CONTEXT.md`](AI_CONTEXT.md) に集約し、各エージェントのリポジトリ固有ファイルから参照している。

### Claude Code

| ファイル | リンク先 | 説明 |
|---------|---------|------|
| [`ai/AI_CONTEXT.md`](ai/AI_CONTEXT.md) | `~/.ai/AI_CONTEXT.md` | 全エージェント共通グローバル指示 |
| [`ai/claude/settings.json`](ai/claude/settings.json) | `~/.claude/settings.json` | ツール許可・フック設定 |
| [`ai/claude/CLAUDE.md`](ai/claude/CLAUDE.md) | `~/.claude/CLAUDE.md` | グローバル指示（`@~/.ai/AI_CONTEXT.md` をインポート） |
| [`ai/claude/hooks/`](ai/claude/hooks/) | `~/.claude/hooks/` | タスク完了通知フック |
| [`ai/skills/`](ai/skills/) | `~/.claude/skills/<skill-name>/` | Codex と共有する個人 skill |
| [`ai/claude/skills/`](ai/claude/skills/) | `~/.claude/skills/<skill-name>/` | Claude Code 専用の個人 skill |
| [`ai/claude/mcp/`](ai/claude/mcp/) | Claude Code user scope | MCP の宣言と実態との差分・追加 |
| [`ai/claude/plugin/`](ai/claude/plugin/) | Claude Code user scope | marketplace / plugin の宣言と実態との差分・追加 |
| [`CLAUDE.md`](CLAUDE.md) | — | リポジトリ固有指示（`@./AI_CONTEXT.md` をインポート） |

`dots claude {diff|apply|prune}` は MCP・plugin・skill をまとめて処理する。
`--mcp-only`、`--plugin-only`、`--skill-only` で対象を1種類に限定できる。
`apply` は追加・更新だけを行い、`prune` は未宣言の user scope MCP / plugin と
dotfiles 所有の skill リンクだけを削除またはバックアップへ退避する。
IDE/app と local/project scope のMCPは検出するが `prune` の対象外とする。local scopeは
`~/.claude.json` 内の端末・リポジトリ固有設定、project scopeは各リポジトリの
`.mcp.json` にある共有設定として区別して表示する。

参照: [Claude Code ドキュメント](https://docs.anthropic.com/en/docs/claude-code)

### Codex

| ファイル | リンク先 | 説明 |
|---------|---------|------|
| [`ai/codex/AGENTS.md`](ai/codex/AGENTS.md) | `~/.codex/AGENTS.md` | グローバル指示の読み込み指示（`~/.ai/AI_CONTEXT.md`、`~/.ai/AI_CONTEXT_CLI.md` を順に参照） |
| [`ai/skills/`](ai/skills/) | `~/.agents/skills/<skill-name>/` | Claude Code と共有する個人 skill |
| [`ai/codex/skills/`](ai/codex/skills/) | `~/.agents/skills/<skill-name>/` | Codex 専用の個人 skill |
| [`ai/codex/mcp/`](ai/codex/mcp/) | `~/.codex/config.toml` 内の MCP 設定 | 公式 MCP の宣言と実態との差分・追加 |
| [`ai/codex/plugin/`](ai/codex/plugin/) | Codex の plugin 状態 | plugin の宣言と実態との差分・追加 |
| [`AGENTS.md`](AGENTS.md) | — | リポジトリ固有指示（`AI_CONTEXT.md` を参照） |

Codex の個人 skill は現行標準の `~/.agents/skills` へ追加する。
`~/.codex/skills` も検知対象に含め、`.system` 以外は `+codex` として報告するが、
`apply` では変更しない。管理対象と同名の skill がある場合、`make install` は二重読み込みを
避けるため `~/.dotfiles-backup/<timestamp>/codex-skills/` へ退避してからリンクする。
`.system` はCodex管理のため対象外とする。外部・curated skillを共通利用する場合は
[`ai/skills/external.json`](ai/skills/external.json) に取得元とrefを宣言し、
dotfiles専用キャッシュからClaude CodeとCodexの両方へリンクする。第三者のskill本体は
このリポジトリへvendorしない。

`dots codex {diff|apply|prune}` は MCP・plugin・skill をまとめて処理する。
Claude Code と同じく `--mcp-only`、`--plugin-only`、`--skill-only` を指定できる。
Codex CLI が返す統合済みの実態を使うため、Codex アプリまたは CLI から追加された
local / remote MCP と plugin を検知する。skill は実際の個人 skill ディレクトリを検査する。
plugin内包MCPとChatGPT/Codexアプリの内部MCPは所有元を表示し、直接MCPの差分や
`prune`対象には含めない。

追加する MCP は、公式サーバーが確認できる次の接続だけに限定する。

- Claude Code → Codex の公式 MCP server mode、GitHub Remote MCP、同 Copilot toolset
- Codex → Claude Code の公式 MCP server mode、GitHub Remote MCP、同 Copilot toolset

### Gemini / Antigravity

| ファイル | リンク先 | 説明 |
|---------|---------|------|
| [`ai/gemini/GEMINI.md`](ai/gemini/GEMINI.md) | `~/.gemini/GEMINI.md` | グローバル指示 |
| [`ai/skills/`](ai/skills/) | `~/.gemini/skills/`, `~/.gemini/config/skills/` | Gemini CLI / Antigravity にも配置する共有 skill |
| [`ai/gemini/skills/`](ai/gemini/skills/) | `~/.gemini/skills/`, `~/.gemini/config/skills/` | Gemini CLI / Antigravity 専用の個人 skill |
| [`ai/gemini/mcp/`](ai/gemini/mcp/) | `~/.gemini/config/mcp_config.json` | MCP の宣言と実態との差分・追加 |
| [`ai/gemini/plugin/plugins/`](ai/gemini/plugin/plugins/) | `~/.gemini/config/plugins/<plugin-name>/` | Antigravity plugin の実体（`plugin.json` 必須） |

`dots gemini {diff|apply|prune}` は MCP・plugin・skill をまとめて処理する。
GitHub MCP (`github/github-mcp-server`) は `gh auth token` (GitHub CLI) を使用して認証情報を動的に読み込むラッパースクリプト経由で安全に起動される。

### Batch-Check All Agents (`dots check`)

`dots check` は `claude`, `codex`, `gemini`, `copilot` の全 AI Agent の MCP・plugin・skill の設定差分をまとめて検査する。

macOSでは、`make install-macos` がLaunchAgentを登録し、ログイン時と1時間ごとに
`dots check`をバックグラウンド実行する。結果は`dots check`本体が
`~/.cache/dots/check-summary`へ保存し、内容が変わった場合だけシステム通知する。
zsh起動時はこのキャッシュを読むだけなので、`dots check`の完了を待たない。
LaunchAgentのplistと実行スクリプトはdotfilesで共有し、既存Macでも`dots update`時に
再リンク・再登録する。手動で`dots check`を実行した場合も同じキャッシュが更新される
ため、`dots ...`コマンドで警告を解消した直後でも次のシェル起動時の表示は最新になる。

Claude Code・Codex・Gemini の宣言をまとめて同期する場合は
`dots ai {apply|diff|prune}` を使用する。`--mcp-only`、`--plugin-only`、
`--skill-only` は3エージェントすべてへ渡される。Copilot は管理対象が user scope MCP
のみで引数体系が異なるため、`dots ai` には含めず `dots copilot` で個別に操作する。

GitHub の認証値は `apply` 時に `gh auth token` から取得する。値は公開 repo には書かず、
Claude Code は `~/.claude.json`、Codex は `~/.codex/config.toml` の静的 Authorization
ヘッダーへ保存する。これは `GITHUB_PAT_TOKEN` 環境変数や手動発行PATを必要としない。
トークンが更新された場合は `apply --mcp-only` を再実行する。
両設定ファイルは `600` とし、Claude側は `diff` で権限も検査する。
`codex mcp list --json` は静的ヘッダー値も返すため、出力をログやIssueへ貼らない。

- Copilot CLI → Claude Code / Codex の公式 MCP server mode
- Copilot CLI エージェント自体、Gemini CLI、別PCの Ollama を汎用操作する公式 MCP
  server は採用していない。独自 MCP bridge も作成しない。

`~/.codex` の次の内容も管理対象外とする。

- `auth.json`、履歴、DB、ログ、キャッシュ、端末・セッション状態
- `rules/default.rules`（端末固有パスや過去の承認を蓄積したローカル状態）
- `config.toml` 全体（プロジェクト信頼状態、アプリ固有の絶対パス等を含み、Codex が更新する）

MCP と plugin の管理ファイルは公開可能な宣言だけを保持し、`config.toml` 自体はリンクせず
各CLI経由で追加・更新・削除する。トークン値は管理対象外とする。

将来、シークレットを含む Codex 設定を再現する必要が出た場合は、公開 repo ではなく
`dotfiles-private/ai/codex/` に置き、同リポジトリの `links.conf` にリンク対応を宣言する。

参照: [Codex skills](https://learn.chatgpt.com/docs/build-skills)、[Codex MCP](https://learn.chatgpt.com/docs/extend/mcp)、[Codex plugins](https://learn.chatgpt.com/docs/build-plugins)

### GitHub Copilot CLI

| ファイル | リンク先 | 説明 |
|---------|---------|------|
| [`ai/copilot/instructions.md`](ai/copilot/instructions.md) | `~/.copilot/copilot-instructions.md` | グローバル指示（`~/.ai/AI_CONTEXT.md` への参照のみ） |
| [`ai/copilot/mcp/`](ai/copilot/mcp/) | `~/.copilot/mcp-config.json` 内の MCP 設定 | MCP の宣言と実態との差分・追加 |
| [`.github/copilot-instructions.md`](.github/copilot-instructions.md) | — | リポジトリ固有指示 |

`dots copilot {diff|apply|prune}` は Copilot CLI の user scope MCP を処理する。
workspace・plugin・builtin MCP は検出対象だが `prune` の対象外とする。

参照: [Copilot CLI ベストプラクティス](https://docs.github.com/ja/copilot/how-tos/copilot-cli/cli-best-practices)

### Gemini CLI

| ファイル | リンク先 | 説明 |
|---------|---------|------|
| [`ai/gemini/GEMINI.md`](ai/gemini/GEMINI.md) | `~/.gemini/GEMINI.md` | グローバル指示（`@~/.ai/AI_CONTEXT.md` をインポート） |
| [`GEMINI.md`](GEMINI.md) | — | リポジトリ固有指示（`@./AI_CONTEXT.md` をインポート） |

参照: [GEMINI.md ドキュメント](https://geminicli.com/docs/cli/gemini-md/)

---

## Zellij Auto-Attach & SSH Wrapper

### Zellij Auto-Attach

以下の条件で起動時に自動的にZellijセッション（セッション名: ホスト名）にアタッチする。

- iTerm2から起動した場合
- SSHでリモートログインした場合（`$SSH_CONNECTION` が設定されている場合）

`NO_ZELLIJ=1` を設定するか、`ZELLIJ` が設定済みの場合はスキップされる。

WindowsではWindows TerminalまたはSSHからの最初の接続でホスト名セッションを作成し、
切断後もZellijサーバーを維持するため、同じセッションへ再接続できる。
詳細は [Windowsセットアップ](docs/setup-windows.md) を参照。
Zellijなしで作業する場合は、Windows Terminalの `PowerShell (No Zellij)` を選ぶ。

### ssh Command Wrapper (Active Only Inside iTerm2 + Zellij)

Zellij内で `ssh` を実行するとZellijが二重になるため、iTerm2の別ペイン/タブで開くラッパーを提供している。
接続先でもZellijが自動起動する。

| コマンド | 動作 | 接続先の Zellij |
|---------|------|----------------|
| `ssh user@host` | 新規タブで接続（デフォルト） | 自動起動 |
| `ssh --same user@host` | 現在のタブを縦分割して右ペインで接続 | 自動起動 |
| `ssh --no-zellij user@host` | 新規タブで接続 | 起動しない |
| `ssh --same --no-zellij user@host` | 現在のタブを縦分割して右ペインで接続 | 起動しない |

> `--same` と `--no-zellij` は独立したフラグなので併用できる。

### claude-rc — Launching Remote Claude Remote-Control

デスクトップの ghq リポジトリを fzf で選択し、リモートの zellij 新タブで `claude remote-control` を起動する。

| コマンド | spawn モード | 説明 |
|---------|------------|------|
| `claude-rc <host>` | same-dir（デフォルト） | CWD で複数セッション共存 |
| `claude-rc <host> -w` / `--worktree` | worktree | セッションごとに git worktree を分離 |
| `claude-rc <host> -s` / `--session` | session | 1セッションのみ（終了で退出） |

- `<host>` は `~/.ssh/config` の Host エントリをタブ補完できる
- リモートの zellij セッションが起動済みである必要がある（自動アタッチで通常は起動済み）

---

## Managing Private Settings

Git の user 情報・SSH config・Dock・アプリケーションショートカット設定は `dotfiles-private`（GitHub プライベートリポジトリ）で管理する。
private側は設定データと `links.conf` の対応表だけを保持し、リンク操作はこのリポジトリの
`install` / `links` / `check` / `uninstall` が行う。

新しい private repository は `make private-scaffold` で `.example` 付きの安全な雛形を
生成できる。既存パスは上書きせず、設定完了までリンクを有効化しない。ファイル一覧、
有効化手順、public側pre-commitによる条件付き検証は
[dotfiles-private Repository](docs/private-repository.md) を参照。

```bash
# リポジトリを設定
cp scripts/.env.example scripts/.env
vi scripts/.env  # PRIVATE_REPO を記入（例: y-marui/dotfiles-private）

# クローン
make private
```

## Local-Only Settings

マシン固有の設定は以下のファイルに書く（git 管理外）：

- `./host/$(hostname -s).zsh` — zsh のマシン固有設定
- `~/.profile.local` — zsh / bash 共通。このMacだけの設定や、privateにも置かない機密値（`shell/profile.local.example` をコピー）
- `~/.zshrc.local` — zsh専用の追加設定（`shell/zshrc.local.example` をコピー）
- `~/.bashrc.local` — bash: 自動的に読み込まれる追加設定
- `macos/Brewfile.local` — Homebrew: このマシン固有のパッケージ（`make init` で空ファイルを生成）

### Profile Settings Layers

`~/.profile` は、後の層で前の層を上書きできる順に設定を読む。

1. `shell/profile` — OS共通の公開設定
2. macOSのみ `macos/profile`（`~/.profile.macos` へリンク）
3. dotfiles-private の `shell/profile.private`（`~/.profile.private` へリンク）
4. 未管理の `~/.profile.local`

複数の自分のマシンで共有する個人用パスは dotfiles-private へ、このMacだけの値とトークン等の認証情報は `~/.profile.local` へ置く。zshだけに関わる設定は `~/.zshrc.local`、bashだけに関わる設定は `~/.bashrc.local` を使う。

### Brewfile.local — Machine-Specific Homebrew Packages

メインの `Brewfile` に含めたくない（他のマシンには入れたくない）パッケージを管理する。

```bash
# make init で凡例付き空ファイルが生成される
make init

# Brewfile.local を編集してパッケージを追加する
vi macos/Brewfile.local
```

記法は `Brewfile` と同じ:

```ruby
brew "some-work-tool"        # CLI ツール
cask "proprietary-app"       # GUI アプリ（Cask）
tap "org/tap"                # Tap
mas "App Name", id: 1234567  # Mac App Store
vscode "publisher.extension" # VS Code 拡張
```

**自動整合（`dots brew sync` 実行時）:**

| 状況 | 動作 |
|------|------|
| パッケージをシステムからアンインストールした | `Brewfile.local` からも自動除去 |
| パッケージをメインの `Brewfile` に追記した | `Brewfile.local` からも自動除去（重複防止） |

**インストール（`dots brew apply` 実行時）:**
`Brewfile.cache`との差分から、`Brewfile` / `Brewfile.local`にのみ存在するエントリを
一時Brewfileへ抽出して適用する。管理ファイルにないエントリがある場合だけcleanupするため、
差分と無関係な既存パッケージは処理しない。

`dots brew apply --full`は従来のapplyと同じく、`Brewfile`と`Brewfile.local`を
それぞれ`brew bundle install`へ渡して全件適用した後、cleanupを実行する。

### Environment Variables That Need Configuring

以下の変数は `~/.profile.local` に設定する。

| 変数 | タイミング | 説明 |
|------|-----------|------|
| `DOTFILES_DIR` | ghq 等で `~/dotfiles` 以外にクローンした場合は**必須** | dotfiles のクローン先パス（例: `/path/to/dotfiles`）。未設定時は `~/dotfiles` が使われる |
| `HOMEBREW_GITHUB_API_TOKEN` | `brew search` 等でレート制限に当たる場合 | GitHub API への認証トークン。現在の Homebrew では必須ではないが、API 制限が頻繁に発生する場合に設定する |

---

## Security: pre-commit Hooks

機密情報（トークン・秘密鍵・ローカルパス等）の誤コミットを防ぐ静的解析フックを導入している。
[gitleaks](https://github.com/gitleaks/gitleaks) と [pre-commit](https://pre-commit.com/) を使用。

### What Gets Detected

| カテゴリ | 具体例 |
|---------|-------|
| クラウド認証情報 | AWS アクセスキー / シークレット、GCP サービスアカウントキー、Azure Storage キー |
| VCS トークン | GitHub Personal Access Token (classic / fine-grained) |
| 秘密鍵 | SSH 秘密鍵ファイル・インライン記述 |
| ローカル絶対パス | `/Users/username/`、`/home/username/`、`C:\Users\` |
| .env ファイル | `.env`、`.env.local`、`.env.production` 等（`.env.example` は許可） |
| 汎用シークレット | `password = "..."` のような直接代入 |

### Setup

```bash
# 1. pre-commit をインストール（Python 3.8+ が必要）
pip install pre-commit
# または Homebrew
brew install pre-commit

# 2. gitleaks をインストール（macOS）
brew install gitleaks
# または Linux
# curl -sSfL https://raw.githubusercontent.com/gitleaks/gitleaks/main/scripts/install.sh | sh

# 3. フックをリポジトリに登録（以降は git commit 時に自動実行）
pre-commit install

# 4. 全ファイルを対象に手動スキャン（初回確認推奨）
pre-commit run --all-files
```

### Configuration Files

| ファイル | 説明 |
|---------|------|
| `.pre-commit-config.yaml` | フック定義（使用するツール・バージョン） |
| `.gitleaks.toml` | gitleaks カスタムルール・除外設定 |

### Handling False Positives

**特定ファイルをスキャン対象から除外する**

`.gitleaks.toml` の `[allowlist]` セクションに追加する:

```toml
[allowlist]
paths = [
  '''tests/fixtures/.*''',   # テスト用フィクスチャ
  '''docs/examples/.*''',    # ドキュメント例
]
```

**特定行をインラインで除外する**

コード内のコメントで 1 行だけ除外できる:

```bash
# gitleaks:allow
EXAMPLE_KEY="AKIAIOSFODNN7EXAMPLE"  # AWS 公式ドキュメントのサンプル
```

**特定コミットを除外する**

`.gitleaks.toml` の `commits` リストにハッシュを追加する:

```toml
[allowlist]
commits = [
  "abc123def456...",  # 既知の false positive が含まれるコミット
]
```

**フックを一時的にスキップする（緊急時のみ）**

```bash
# 特定フックだけスキップ
SKIP=gitleaks git commit -m "..."

# 全フックをスキップ（非推奨・緊急時のみ）
git commit --no-verify -m "..."
```

> [!CAUTION]
> `--no-verify` は緊急時以外使用しないこと。
> スキップした場合は必ず直後のコミットで修正すること。

### Updating the Hooks

```bash
# 全フックを最新バージョンに更新
pre-commit autoupdate

# CI での利用（キャッシュを使って高速化）
pre-commit run --all-files --show-diff-on-failure
```
