---
description: make・dots・カスタムコマンドの一覧と動詞表（dots の動詞表は check-dots-verb-table.sh の検証対象）
---

# Commands

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

状態を管理ファイルと突き合わせるコマンドは、`apply` `diff` `sync` `merge` `prune` `cache` の
6動詞を共通の入口として持つ。各セルは次のいずれかで、かっこ内は標準動作との違いを表す。

- `◯`: 実装あり
- `N/A（理由）`: 意図的に存在しない。実行しても終了コード0で、標準エラーに理由を1行出す
- `未実装`: 実装予定。実行するとエラーになる

この表と `dots help` / `dots <domain> help` は `bin/unix/_dots-verbs.sh`（Windowsは
`bin/windows/dots.ps1`）の動詞テーブルを正本とし、`scripts/check-dots-verb-table.sh` が
pre-commitで一致を検証する。動詞の意味は [docs/specification.md](specification.md#dots-verbs) を参照。

| コマンド | apply | diff | sync | merge | prune | cache | 説明 |
|---------|-------|------|------|-------|-------|-------|------|
| `dots brew` | ◯（既定は差分のみ。`--full`で全件。余分はcleanup。`--no-prune`でcleanupを省略。`--dry-run`あり） | ◯（`--summary`・`--exit-code`あり） | ◯（削除を伴う場合は`--yes`。`--dry-run`あり） | ◯（`--dry-run`あり） | ◯（cleanup。`--dry-run`あり） | ◯ | Brewfile / Brewfile.local / Brewfile-pin |
| `dots dock` | ◯（差分のある側を再構築。`--dry-run`はdiffと同じ表示） | ◯（`--summary`・`--exit-code`あり） | ◯（実機と完全一致。他マシン由来の項目も消えるため、削除を伴う場合は`--yes`。`--dry-run`あり） | ◯（他マシン由来の項目を保持。`--dry-run`あり） | N/A（applyが全体を再構築するため削除だけを分離できない） | ◯ | Dock・Finderサイドバー（dotfiles-private） |
| `dots shortcuts` | ◯（ローカルのみの設定は消える。`--no-prune`で追加・更新のみ。`--dry-run`あり） | ◯（`--summary`・`--exit-code`あり） | ◯（削除を伴う場合は`--yes`。`--dry-run`あり） | ◯（`--dry-run`あり） | ◯（ローカルのみの設定を削除。`--dry-run`あり） | ◯ | macOSのアプリケーションショートカット |
| `dots npm` | ◯（余分はprune。`--no-prune`で追加のみ。`--dry-run`あり） | ◯（`--summary`・`--exit-code`あり） | ◯（削除を伴う場合は`--yes`。`--dry-run`あり） | ◯（`--dry-run`あり） | ◯（`--dry-run`あり） | ◯ | npmグローバルパッケージ |
| `dots pipx` | ◯（余分はprune。`--no-prune`で追加のみ。`--dry-run`あり） | ◯（`--summary`・`--exit-code`あり） | ◯（削除を伴う場合は`--yes`。`--dry-run`あり） | ◯（`--dry-run`あり） | ◯（`--dry-run`あり） | ◯ | pipxパッケージ |
| `dots ghq` | ◯（宣言外は`--unset`。`--no-prune`で設定のみ。`--dry-run`あり） | ◯（`--summary`・`--exit-code`あり） | ◯（共通宣言から削除する場合は`--yes`。`--dry-run`あり） | ◯（`--dry-run`あり） | ◯（宣言外の`--unset`のみ。`--dry-run`あり） | N/A（実状態をGit configから直接読む） | `ghq-update`の更新対象（`local.keep-up-to-date`） |
| `dots ai` / `dots claude` / `dots codex` | ◯（追加・更新の後にprune。`--no-prune`で追加・更新のみ） | ◯ | N/A（宣言は人が編集する） | N/A（宣言は人が編集する） | ◯（apply単独の削除部分） | N/A（実状態を直接読む） | MCP・plugin・skill（`--mcp-only`等で対象を絞れる）。`dots ai`はClaude Code・Codexを一括実行 |
| `dots copilot` | ◯（追加・更新の後にprune。`--no-prune`で追加・更新のみ） | ◯ | N/A（宣言は人が編集する） | N/A（宣言は人が編集する） | ◯ | N/A（実状態を直接読む） | Copilot CLIのuser scope MCPのみ |
| `dots winget`（Windowsのみ） | ◯（宣言にないpinはunpinして完全一致。`--no-prune`でpinのみ。`--dry-run`あり） | ◯（`--summary`・`--exit-code`あり） | N/A（宣言は理由コメント付きで人が編集する） | N/A（宣言は理由コメント付きで人が編集する） | ◯（未宣言のpinを解除。`--dry-run`あり） | ◯ | `windows/WingetPin`の一時pin宣言 |
| 標準動作 | 管理ファイル → 実状態へ適用 | 差分を表示するだけ | 実状態 → 管理ファイル（完全一致） | 実状態 → 管理ファイル（追加のみ） | 管理ファイルにない項目を削除・退避 | 実状態のキャッシュを更新 | |

共通オプション（各動詞が受け付けるものはドメインごとに決まっており、受け付けないものはエラー）:

- `--no-prune`: `apply` で削除を行わず、追加・更新のみ行う。`make install`など無人で実行される経路は、
  dock・shortcutsを除いてこれを付ける
- `--dry-run`: 何も変更せず、実行した場合の変更予定だけを表示する（brew・dock・shortcuts・npm・pipx・ghq・
  wingetが対象。ai系は未対応）
- `--yes`: 宣言側の項目を削除する `sync` に必要（削除がなければ不要。brew・dock・shortcuts・npm・pipx・
  ghqが対象）
- `--summary` / `--exit-code`: `diff` 専用。`--summary` は差分の件数を1行で示し（aiの`diff`を除く）、
  `--exit-code` は差分があれば終了コード1を返す（既定は差分があっても0）
- `--backup-dir DIR`: 削除・上書きの前に退避するディレクトリ（既定は `~/.dotfiles-backup/<timestamp>/`）

その他のコマンド:

| コマンド | 説明 |
|---------|------|
| `dots status` | dotfiles / dotfiles-private の未コミット・未push・未pullを確認 |
| `dots check` | リンク・dotfilesの状態・パッケージ管理・AI Agentの差分を一括検査（Windowsは簡易版） |
| `dots update [--all]` | dotfiles を更新・再リンクし、PreztoとOS別パッケージを更新（`--all`で`ghq-update`の依存更新対象を`.venv`/`node_modules`があるリポジトリまで拡張） |
| `dots commit` | sync系コマンドが書き換えたファイルのみの変更を自動commit |
| `dots push` | 未pushのcommitが自動commitのみならpush、対象外ファイルが混じれば手動pushを促す |

`dots status` は両リポジトリを `git fetch --prune` してから確認し、要対応の状態が
1つでもあれば終了コード1を返す。ネットワークへ接続せず、既存のremote-tracking refだけで
確認する場合は `dots status --no-fetch` を使用する。

`dots commit` は dotfiles / dotfiles-private それぞれの working tree を確認し、
`macos/Brewfile` / `macos/Brewfile.local` / `npm/npmfile` / `pipx/pipxfile`
（dotfiles-private側は `macos/dockfile` / `macos/keyboard-shortcuts.plist` / `ghq/keep-up-to-date`）
だけが変更されている場合に限り、自動生成した Conventional Commits 形式のメッセージで
commitする。これら以外のファイルが1つでも変更に含まれる場合は何もcommitせず、
手動でのcommitを促す（自動commit対象のファイルだけを部分的にcommitすることはしない）。

`dots push` は各リポジトリでunpushedなcommit群の変更ファイルを調べ、全て上記の
自動commit対象ファイルだけであればpushする。対象外ファイルを含むcommitが1つでも
混在する場合はpushせず、該当ファイルを提示して手動pushを促す。

ZellijはOS別に互換性を確認したバージョンを固定する。macOS/Raspberry Piは
`scripts/setup-zellij.sh`で`0.45.1`を、Windowsは`scripts/setup-zellij.ps1`で
同じ`0.45.1`の公式Windowsビルドをユーザーローカルへインストールする。

## Custom Commands (`~/.local/bin/`)

`make install` で `~/.local/bin/` にシンボリックリンクが作成される。実装は
`bin/unix/`（zsh/bash、拡張子なし）と `bin/windows/`（`*.ps1` ネイティブ実装 +
bareコマンド名用の`*.cmd`シム）に分かれており、`scripts/check-bin-parity.sh`が
pre-commitで両者の対応関係を検証する。

| コマンド | 説明 |
|---------|------|
| `dots` | dotfilesとマシン環境を管理 |
| `run-quiet <cmd>` | コマンドをラップし、成功時は1行サマリーのみ出力。warning/deprecated 行は抜粋表示 |
| `git-pull-all [--fetch-only] [main-branch]` | 1リポジトリの全ローカルブランチをupstreamへfast-forward同期（現在ブランチは`pull --ff-only`、他は作業ツリーを動かさず同期） |
| `git-sweep [--all] [--no-pull] [main-branch]` | `git-pull-all`のあと、マージ済みブランチを整理（fast-forward・squash・rebase merge 対応）。`--no-pull`で同期を省く |
| `chatgpt-export {install\|doctor\|capture}` | 隣接する`chrome-chatgpt-exporter/cli/`を起動。ログイン済みChromeの拡張から会話ZIPを取得。導入・接続・手動代替は[仕様](specification.md#chatgpt-export)を参照 |
| `obsidian-project-home [check\|ensure] [--repo DIR] [--vault DIR] [--description TEXT]` | Git `origin`と通常領域のProject Home `repositories`を照合し、一意の対応先を解決。`ensure`は許可オーナー（`auto_create_owners`）の未登録リポジトリだけ雛形を作る。設定は`dotfiles-private/obsidian/project-home-resolver.conf` |
| `doc-lint` | カレントのリポジトリの全Markdownのサイズ・frontmatterを検査して表示（警告のみ・ログなし。[仕様](specification.md#doc-lint)） |
| `git-survey [main-branch]` | main以外のブランチをlocal/remote別に表示 |
| `ghq-pull [--fetch-only]` | ghq管理リポジトリ全件をfetch + pull |
| `ghq-update [--all\|--pull-all\|--sync-only\|--pull-only\|--no-auto-pr]` | ghq管理リポジトリを更新（uv sync・npm update/build、lock自動PR含む） |
| `ghq-sweep [--no-pull]` | ghq管理リポジトリ全件に`git-sweep --all`を実行（`--no-pull`はローカルブランチの更新を行わない） |
| `my-hosts [status\|pull\|sweep\|update\|apps] [--no-status\|-f pattern\|-H host\|--dry-run] [-- install-my-appsの引数]` | 宣言した他のホスト（Mac/Windows）で`ghq-pull`/`ghq-sweep`/`ghq-update`と`ghq-status`、`install-my-apps`をssh経由で実行（`status`=statusのみ、`pull`=pull→status、`sweep`=sweep→status（省略時）、`update`=pull→依存更新→status、`apps`=`install-my-apps`のみ（リモートは`--no-gui`付き）、`--no-status`でstatusを省く。ホスト間は並列、実行元はmacOS専用、対象にはWindows（OpenSSH+pwsh、`<host>:windows`）とRaspberry Pi（`<host>:rpi`、`apps`のみ`skip`）も宣言できる。Windowsは`apps`が`skip`で、`pull`系はGitHub認証の制限で未対応（詳細はspecification）、対象は`dotfiles-private`の`hosts/hosts`で実行元ごとに宣言） |
| `install-my-apps [-f\|-r\|-u\|--no-gui\|--migrate-old\|--no-migrate-old] [app...]` | iCloud Driveの`Build/Swift/*.dmg`と`Build/Tauri/*.dmg`から自作アプリを`/Applications/My Swift`と`/Applications/My Tauri`へインストール（App Store版と同名でも衝突しない。`Build`直下の移行前のDMGはSwift扱い。移行期間の措置として、`/Applications`直下に残っている同じ自作アプリを整理する`--migrate-old`が既定でONで、新旧の両方にあるときは消さない。macOS専用。Windows版は`my-hosts`用の何もしないスタブで、終了コード64を返す。`--no-gui`でアプリの終了・起動・ウィジェット編集画面を省く） |
| `ghq-check [--sync]` | GitHub の全リポジトリの取得状況を確認。`--sync` で未取得リポジトリを `ghq get` |
| `ghq-status` | ghq 管理リポジトリの git 状態・ブランチをテーブル表示 |
| `sync-labpc <job-name\|host-ip\|all\|list>` | 測定器室PCのデータをSMB経由で一方向同期（macOS専用、ジョブ定義は`~/.config/labpc/jobs.d/`。`list`でジョブ一覧表示） |
