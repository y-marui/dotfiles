# Specification

コマンド一覧は [AI_CONTEXT.md](../AI_CONTEXT.md) の「よく使うコマンド」を参照。ここでは主要コマンドの動作定義のみを記す。

## Install / Link

- `make install` / `make links` はシンボリックリンクの作成のみを行う（べき等。既存のリンクが正しい参照先を指していれば何もしない）
- 隣接する `dotfiles-private` が存在する場合は、同リポジトリの `links.conf` も読み込む
- `links.conf` は `platform|source|destination` の3列とし、未対応platform、絶対パス、`.` / `..`、存在しないsource、重複destinationを拒否する。設定ファイルをコードとして実行しない
- リンク先が管理外の実ファイルとして既に存在する場合は、`~/.dotfiles-backup/<timestamp>/`へ退避してからリンクする
- `make check` はリンク切れ・リンク先不一致・未リンクファイルを検出するが、修復はしない（`make links` を促す）
- `make uninstall` はdotfilesまたはdotfiles-privateを指す管理リンクだけを削除する
- macOSの`make install-macos`はリンク作成後に`dots check`監視用LaunchAgentと、美術展タスクのステータス更新用LaunchAgentを登録する
- Windows では `mingw32-make install` が `pwsh scripts/install.ps1` を呼び、PowerShell ネイティブでシンボリックリンク（`New-Item -ItemType SymbolicLink`）を作成する

## Private Repository Scaffold

- `make private-scaffold` は既定で隣接する `../dotfiles-private` を生成する。生成先が存在する場合は上書きせず失敗する
- `PRIVATE_SCAFFOLD_DIR` で生成先を変更できる
- 生成物は `.example` と説明ファイルだけを持ち、`links.conf` を作らない未有効化状態とする
- 設定完了後に `.dotfiles-private-scaffold` を削除すると、有効化済みrepositoryとして検証される
- `make private-validate` は公開側雛形との一致、必須設定、リンク対応表、private側の実行ロジック不在を検証する
- public側pre-commitは同じ検証を常時実行するが、隣接するprivate Git repositoryがない環境では成功扱いでスキップする

## dots update

以下を順に実行する（失敗しても後続は継続し、最後にまとめて結果を報告する）:

1. dotfiles / dotfiles-private を fast-forward 更新
2. インストーラーでリンクを再適用し、macOSでは`dots check`監視用LaunchAgentと美術展タスクのステータス更新用LaunchAgentを再登録
3. zprezto をサブモジュール込みで更新
4. OS 別パッケージマネージャー（Homebrew / winget）の更新

pipx は、各仮想環境を作成した基底 Python の実体パス・バージョンを現在の global Python と
比較する。異なる環境や Python 実行ファイルが失われた環境がある場合は、
`pipx reinstall-all --python <global Python>` で全仮想環境を作り直す。全環境が一致する
場合は `pipx upgrade-all` のみを実行する。macOSでpyenvを使用している場合は、実行場所の
`.python-version` や `PYENV_VERSION` ではなく `pyenv global` を基準にする。

## dots check Monitor (macOS)

- `com.y-marui.dotfiles-check`をユーザーLaunchAgentとして、ログイン時と1時間ごとに実行する
- plistとrunnerはdotfiles内で管理し、`~/Library/LaunchAgents/`と`~/.local/bin/`へリンクする
- `make install-macos`と`dots update`が各Macで自動登録し、`make launchagent`で手動再登録できる
- `dots check`（`--verbose`を付けない通常実行）本体が、実行の都度
  `~/.cache/dots/{check-summary,check-state,check-digest}`を原子的に保存する
  （`DOTS_CHECK_CACHE_DIR`で保存先を上書き可能）。LaunchAgent経由に限らず、
  ユーザーが直接`dots check`を実行した場合も同じキャッシュが更新されるため、
  `dots ...`コマンドで警告を手動解消した直後でも、次のシェル起動時の表示が
  古い警告のまま残ることはない。`--verbose`はこの一覧形式に合わないため
  キャッシュを更新しない
- `dots-check-monitor.sh`（LaunchAgentのrunner）自体はキャッシュを書かず、
  `dots check`を呼び出した後にキャッシュの実行前後の状態を比較してmacOS通知
  だけを出す（`dots`コマンド自体が見つからずキャッシュを更新できない場合のみ、
  例外的にrunner側が直接書き込む）
- 警告内容のハッシュが変わった場合と、警告が解消した場合だけmacOS通知を出す
- 警告・エラー通知はterminal-notifier経由で出し、クリックすると`dots-check-monitor-popup`が
  `check-summary`全文をダイアログ表示する（コピー/閉じるを選択可能）。osascriptの
  `display notification`はクリック時の送信元がScript Editorに固定され空の新規スクリプトが
  開いてしまうため、terminal-notifier未導入時のみそちらへフォールバックする
- zsh起動時はキャッシュを読み取るだけで、チェック処理を同期実行しない
- macOSでは、`/etc/pam.d/sudo` が `sudo_local` を読み込み、
  `/etc/pam.d/sudo_local` で `auth sufficient pam_tid.so` が有効になっていることを検査する
- 自動修復は行わない。詳細確認と手動再実行には`dots check`を使う
- `make uninstall`は確認後にLaunchAgentを解除してから管理リンクを削除する

## Museum Status Refresh (macOS)

- `com.y-marui.museum-status-refresh`をユーザーLaunchAgentとして、毎週月曜8時に実行する
- plistとrunnerはdotfiles内で管理し、`~/Library/LaunchAgents/`と`~/.local/bin/`へリンクする
- `make install-macos`と`dots update`が各Macで自動登録し、`make launchagent-museum-status`で手動再登録できる
- 実行対象は`glance-task-format-museum-events` skillの`museum_events.py refresh --apply`で、AIを一切呼び出さない
- 各グループの未完了タスクについて、今日の日付と会期からステータス絵文字（🎟️開催中 / ⏳開催前 / 🏁開催終了）をタイトル末尾に反映し、期間・開始日順に並べ替える
- メモの期間が解析できないタスクは❌を付けてリスト最後尾に送り、他タスクの更新・並べ替えはブロックしない
- ❌が1件以上あった実行ではmacOS通知を1回出す（該当タスク名と件数を含む）
- `make uninstall`は確認後にLaunchAgentを解除してから管理リンクを削除する

## dots verbs

状態を管理ファイルと突き合わせるコマンド（`dots brew|dock|shortcuts|npm|pipx|ghq|claude|codex|copilot|winget`）
が持つ動詞の標準的な意味。どの動詞をどのコマンドが実装しているか、および標準動作との違いは
[README.md](../README.md#command-list) の動詞表を正本とする。

| 動詞 | 標準動作 |
|---|---|
| `apply` | 管理ファイル → 実状態へ適用する。差分がなければ何もしない |
| `diff` | 差分を表示するだけで何も変更しない。差分があっても終了コードは 0（`dots ghq diff` も同様に、スクリプトの終了コード 1 を正常終了として扱う） |
| `sync` | 実状態 → 管理ファイル。実状態と完全一致させる（追加・削除の両方） |
| `merge` | 実状態 → 管理ファイル。追加のみで削除しない |
| `prune` | 管理ファイルにない項目を削除・退避する |
| `cache` | 実状態のキャッシュを更新する（`diff` の比較基準） |

`sync` / `merge` が書き換える管理ファイルのうち、`dots commit` の自動commit対象は
[dots commit / dots push](#dots-commit--dots-push) に列挙したものだけである。

### Verb states and the verb gate

`bin/unix/_dots-verbs.sh` の動詞テーブルが、ドメイン×動詞の状態を定義する単一の正本である。
`dots help`・`dots <domain> help`・`dots verbs`・READMEの動詞表との整合チェック
（`scripts/check-dots-verb-table.sh`）はすべてここから導く。Windowsは `bin/windows/dots.ps1` の
`$verbSpecs`（ghq・winget）と、動詞ごとの共通オプションの表 `$verbOptions` が同じ書式で持つ。
どちらもUnix側のテーブルとの一致を `scripts/check-dots-verb-table.sh` が検証する。

| 状態 | 意味 | `dots <domain> <verb>` を実行したとき |
|---|---|---|
| `ok` | 実装済み | 通常どおり実行する |
| `na` | 意図的に存在しない（理由付き） | 終了コード0。標準出力には何も出さず、標準エラーに `N/A: dots <domain> <verb> — <理由>` を1行出す |
| `todo` | 実装予定 | エラー（終了コード1）。`未実装です` を出す |

未知の動詞は `unknown <domain> action` のエラーになる。動詞を省略すると、実装済みの動詞を
示すusageエラーになる。全ドメインの動詞の実行前に、この動詞ゲートを通す。

### Common options

| オプション | 意味 |
|---|---|
| `--no-prune` | `apply` で削除を行わず、追加・更新のみ行う |
| `--dry-run` | 何も変更せず、実行した場合の変更予定だけを表示する。`diff`（宣言と実状態の全差分）とは別で、他のオプション（`--no-prune`など）を反映した変更予定を出す |
| `--yes` | 宣言側の項目を削除する `sync` に必要（削除がなければ不要）。`merge` は削除しないので受け付けない |
| `--backup-dir DIR` | 削除・上書きの前に退避するディレクトリ。既定は `~/.dotfiles-backup/<timestamp>/` |

各動詞が受け付ける共通オプションは `_dots_verb_options` で(ドメイン, 動詞)ごとに決まっており、
受け付けないものは動詞ゲートがエラーにする。ドメイン固有のオプション（`brew apply --full`、
`--mcp-only` など）はゲートの対象外で、各実装が検証する。

`make install` や `dots update` のように人が見ていない経路では、`apply` に `--no-prune` を付けて
削除を避ける。例外は、現状の `apply` が完全一致で動くdockとshortcuts。

### npm / pipx

`apply` は宣言にあって未導入のものを入れ、続けて `prune` を実行して宣言と一致させる。
`prune` は宣言にない導入済みパッケージを削除し、削除前に一覧を `<backup-dir>/npm-removed.txt`
（pipxは `pipx-removed.txt`）へ保存する。npm本体は導入済み一覧から除外される。
差分の有無はキャッシュではなく実状態で判定する（`apply` は事前のdiffによる早期終了をしない）。
`sync` が宣言から項目を削除する場合は `--yes` を要求し、なければ何も書き換えずに終了コード2で終わる。
`--dry-run` はキャッシュも書き換えない。

### brew / dock / shortcuts

- **brew**: `prune` は `brew bundle cleanup`（未管理パッケージの削除）と、cleanupの対象外である
  mas アプリの未管理警告を行い、インストールはしない。`apply` は差分だけのインストールに続けて
  cleanupし、`--no-prune` でcleanupを省く。`sync` が `Brewfile` / `Brewfile.local` からエントリを
  削除する場合（システムから削除済みのもの）は `--yes` が必要で、`Brewfile.local` から `Brewfile`
  への昇格に伴う重複除去は削除として扱わない。`--dry-run` はキャッシュも管理ファイルも書き換えない
- **dock**: `sync` は `dockfile` を実機と完全一致させ、他マシン由来の項目（実機に存在しない
  アプリ）も削除する。削除が1件でもあれば `--yes` が必要。他マシン由来の項目を保持して更新する
  従来の挙動は `merge` に移した。サイドバーの取得ツールが使えないときは、既存のサイドバーの
  項目を空で上書きせず保持する。`apply` は差分のある側を丸ごと再構築するため `prune` は
  N/A で、`apply --dry-run` は `diff` と同じ表示になる
- **shortcuts**: `apply` は宣言と完全一致（追加・更新に加えローカルのみの設定を削除）で、
  `--no-prune` は追加・更新のみを行い、`prune` はローカルのみの設定の削除だけを行う
  （残す設定の値は変更しない）。書き込みは差分のあるドメインだけに行う。`sync` が管理ファイルから
  エントリを削除する場合は `--yes` が必要

### Exit code of diff

`dots <domain> diff` は差分があっても終了コード0で、差分の表示だけを行う。`--exit-code` を付けると、
差分があれば終了コード1を返す（想定外の失敗は従来どおり表示のみで、終了コードに影響しない）。
`--summary` は差分の件数を1行で示し、`dots check` の要約と同じ形式である。aiの `diff`
（複数の対象を順に処理する）は `--summary` を受け付けない。

### Migration status

すべてのドメインで、READMEの表の「未実装」はなくなった。`--dry-run` は ai 系を除く全ドメイン、
`--yes` は宣言側の項目を削除する `sync` を持つ全ドメイン（brew・dock・shortcuts・npm・pipx・ghq）が
受け付ける。ai 系（claude・codex・copilot）の `apply` / `prune` は `--dry-run` を受け付けない。

### ghq / winget

- **ghq**: `apply` は宣言済みを `true` にし、宣言にない `true` を `--unset` する（完全一致）。
  `--no-prune` は `true` にするだけで、宣言にない `true` は一覧表示だけにする。`prune` は
  `--unset` だけを行い、宣言済みのリポジトリを `true` にはしない。`sync` が共通宣言から
  エントリを削除する場合は `--yes` が必要。`--dry-run` は Git config も宣言も書き換えない
  （`keep-up-to-date.sh` と `.ps1` は同じ規則）
- **winget**（Windowsのみ）: `apply` は `WingetPin` の宣言に実際の pin を一致させる（宣言外の pin は
  解除する）。`--no-prune` は pin だけを行い、`prune` は解除だけを行う。判定の前に `WingetPin.cache`
  （gitignore対象のスナップショット）を更新する。`diff` の終了コードは既定で0になった
  （従来は差分ありで1）。差分ありを終了コード1で返すには `--exit-code` を付ける

## dots {claude|codex} diff / apply / prune

MCP・plugin・skill の「宣言（dotfiles 内の設定ファイル）」と「実状態（各ツールの実際の設定）」を比較・同期する。

- `diff`: 差分のみ表示（変更なし）
- `apply`: 宣言済みだが未反映の項目を追加・更新し、続けて `prune` を実行して宣言と完全一致させる。
  `--no-prune` を付けると追加・更新のみを行う（各 `ai/<agent>/*/apply.sh` は追加・更新だけを担当し、
  削除は `prune.sh` が担当する。`dots` がこの2つを順に呼ぶ）
- `prune`: 未宣言かつ dotfiles 管理境界内の項目だけを削除・退避する（管理境界外のユーザー独自設定は対象外）。
  単独でも実行できる
- Codex plugin のうち、`plugin/list` で remote かつ `INSTALLED_BY_DEFAULT` と判定されるものは
  Codex 管理のため、宣言との差分・`apply`・`prune` の対象外とする

## dots ai diff / apply / prune

Claude Code、Codex の順に、各エージェントの同じ操作を一括実行する。
`--mcp-only`、`--plugin-only`、`--skill-only` を指定した場合は、同じ限定オプションを
3エージェントすべてへ渡す。途中のエージェントで `apply` または `prune` が失敗した場合は
そこで終了し、後続エージェントは処理しない。

Copilot は user scope MCP のみを管理し、対応する対象種別とオプションが異なるため含めない。
個別の `dots {claude|codex}` コマンドは引き続き利用できる。

Windows でも同じコマンドを `ai/**/*.ps1` で実行する。Unix 版との違いは次のとおり。

- `~/.claude.json` の権限検査（`~permission`）は行わない（Windows に `chmod 600` 相当がないため）
- skill のリンクは `New-Item -ItemType SymbolicLink` で作る。権限がなければ `gsudo` で昇格して
  `apply.ps1` 全体を再実行する（処理は冪等）。`gsudo` がない場合は、開発者モードの有効化を促して失敗する
- 外部 skill の取得は `python3` / `python` を探して `skill-installer` を実行する
- `diff` の終了コードは 1 が差分あり、2 がエラー（想定外の例外）。`dots` は 2 以上を失敗として扱う

## dots commit / dots push

`sync` 系コマンド（`dots brew sync` / `dots npm sync` / `dots pipx sync` /
`dots dock sync` / `dots shortcuts sync` / `dots ghq sync`、および追加のみの
`dots {brew|npm|pipx|shortcuts|dock|ghq} merge`）は、システムの実態をそのまま管理ファイルへ
書き写すだけで、記述内容に人間の判断を伴わない。この種の変更を都度手動commitする
手間を省くためのコマンド。

**自動commit対象ファイル**（これ以外のファイルは対象外）:

- dotfiles: `macos/Brewfile`, `macos/Brewfile.local`, `npm/npmfile`, `pipx/pipxfile`
- dotfiles-private: `macos/dockfile`, `macos/keyboard-shortcuts.plist`, `ghq/keep-up-to-date`

`dots commit`:
- dotfiles / dotfiles-private それぞれのworking treeを確認する
- 変更ファイルが全て上記の対象ファイルであれば、変更されたファイル名から
  Conventional Commits形式のメッセージ（例: `chore: Brewfile・npmfileを実態に同期`）を
  自動生成してcommitする
- 対象外のファイルが1つでも変更に含まれる場合は、対象ファイルも含めて一切commitせず
  （部分commitはしない）、対象外ファイルの一覧を表示して手動commitを促す
- `Brewfile-pin` やAI（claude/codex/copilot）のMCP・plugin・skill宣言ファイル、
  `ghq/keep-up-to-date.local`（端末固有の手編集専用）は人間が意図して編集する
  （更新対象とするかどうかの判断そのもの）ため対象外。`ghq/keep-up-to-date`は
  `dots ghq sync` / `merge` が実状態から機械的に書くため対象に含める

`dots push [--no-fetch]`:
- 既定では各リポジトリを`git fetch --prune`してから、upstreamに対してunpushedな
  commit群の変更ファイルをまとめて調べる
- 変更ファイルが全て自動commit対象ファイルであれば`git push`する
- 対象外ファイルを含むcommitが1つでも混在する場合はpushせず、該当ファイルと
  リポジトリパスを提示して手動pushを促す
- upstream未設定のリポジトリはスキップする

## git-pull-all / git-sweep / ghq-pull / ghq-update / ghq-sweep / my-hosts

ブランチ同期（pull）とブランチ整理（sweep）、それらを全リポジトリへ広げる`ghq-*`、
複数Macへ広げる`my-hosts`の責務分担と共通ルールを定める。各コマンドのオプションは
スクリプト冒頭のコメントを正本とする（`bin/windows/*.ps1`も同一仕様。`my-hosts`だけは
macOS専用）。

### Responsibilities

| コマンド | 責務 |
|---|---|
| `git-pull-all` | 1リポジトリの全ローカルブランチをupstreamへfast-forward同期する唯一の実装 |
| `git-sweep` | `git-pull-all`のあと、マージ済みブランチを削除する（`--no-pull`で同期を省く） |
| `ghq-pull` | 全リポジトリに`git-pull-all`を実行する（ロックファイルstash付き） |
| `ghq-update` | keep-up-to-dateのリポジトリを`git-pull-all`で更新し、依存更新（uv/npm）と自動PRを行う |
| `ghq-sweep` | 全リポジトリに`git-sweep --all`を実行する |
| `my-hosts` | 上記と`install-my-apps`を宣言した他のMacでssh経由に実行する |

pullの実装を`git-pull-all`だけに置き、`ghq-pull`・`ghq-update`・`git-sweep`はそれを呼ぶ。
ブランチ方針（main/protectedの解決）とworktree判定は`_git-branch-lib.sh`/`.ps1`を共有する。

### git-pull-all

- **fetch**: `fetch --all --prune`（dirty・detached HEADでも実行）。失敗は終了コード1。
  `upstream`というremoteがあれば、fetchの前に`gh repo sync`でupstreamのデフォルト
  ブランチをoriginへ反映する
- **現在のブランチ**: `pull --ff-only`で更新する。dirty・detached HEAD・upstream未設定
  （goneは無表示）の場合は更新せず`warning:`を出す。分岐・コンフリクトで失敗したら
  `error:`を出して終了コード1にする
- **現在のブランチ以外**: 保護ブランチも含め、upstreamへfast-forwardで同期する。
  HEADも作業ツリーも動かさない（`git fetch --no-prune . <upstream>:<branch>`。
  `fetch.prune=true`の設定下でもdstが削除されないよう`--no-prune`を付ける）。
  upstream未設定・goneは対象外、ローカルが先行していれば何もしない、分岐していれば
  `warning:`のみ、他worktreeで使用中のブランチは更新しない（遅れている場合のみ
  `Skipped:`を表示）。dirtyでも作業ツリーは変わらないので実行する
- **保護ブランチの新規作成**: ローカルに無い保護ブランチはoriginから作る。それが`$MAIN`で
  cleanなら切り替える
- **`--fetch-only`**: fetchだけ行い、ローカルブランチは更新しない
- **安全性**: pullはfast-forward-onlyで、暗黙のrebaseやautostashは行わない。
  `Updated ...`は対応するgitコマンドが成功し、ブランチが進んだ場合のみ表示する

### git-sweep

- **同期**: 既定で`git-pull-all`を実行する。失敗しても削除処理は続行し、最後に終了コード1にする。
  `--no-pull`では、upstream同期と`fetch --prune`だけ行う（マージ済み判定に必要）。
  ローカルの`$MAIN`が更新されないため、実際にはマージ済みでも削除されない場合がある
- **dirty worktreeの保護**: 現在のブランチがdirtyなら、checkout・削除を行わずスキップし、
  理由を表示する（`--all`による他ブランチの削除は行う）
- **他worktreeで使用中のブランチの保護**: `git worktree list --porcelain`で明示的に列挙し、
  現在のworktree以外でcheckout中のブランチは切り替え・削除の対象にしない
- **`gone`だけでのマージ済み判定をしない**: リモート追跡ブランチが`gone`でも、
  それだけでは削除しない。squash/rebase merge後のケースは、merge-baseからの差分が
  `$MAIN`側の履歴に実在することを検証してから（git-delete-squashed相当）のみ削除する。
  一致しない場合（未マージ、または追加のローカル専用コミットがある場合）は保持する
- **理由のない`-d`→`-D`フォールバックをしない**: `-D`は、上記の検証でsquash/rebase merge
  として内容一致を確認できた場合にのみ使う
- **成功メッセージは実際の成功時のみ**、**Skipped / Deleted / Remaining の区別**を表示する

### ghq-pull / ghq-update / ghq-sweep

- **対象**: `ghq-pull`と`ghq-sweep`は全リポジトリ（`ghq-sweep -s`は`ghq-status`で異常のある
  もののみ）。`ghq-update`はkeep-up-to-dateのリポジトリ（`--pull-all`で全リポジトリのpull、
  `--all`で`.venv`/`node_modules`のあるリポジトリまでsync対象を拡張）。`-f/--filter`は
  3コマンド共通。dotfilesとdev-charterは他より先に処理する
- **ロックファイルstash**: `uv.lock`/`package-lock.json`のみdirtyなら一時的にstashして実行し、
  実行後に復元する（復元でコンフリクトしたら失敗として扱い、stashは残す）。
  それ以外にもdirtyなら、`ghq-pull`は`git-pull-all`がwarning付きで現在ブランチの更新を見送り、
  `ghq-update`は依存更新を`[skip] dirty working tree`で見送り、`ghq-sweep`はリポジトリごと
  `[skip] dirty working tree`で見送る
- **`ghq-update`の依存更新**: pullに成功し、detached HEADでもdirtyでもなくupstreamがある
  リポジトリだけ、`uv sync --upgrade`/`npm update && npm run build --if-present`を実行する。
  `--pull-only`で省き、`--sync-only`（旧`--uv-sync-only`）でpullを省く（同時指定は不可）
- **`ghq-sweep --no-pull`**: `git-sweep`へ渡す

### Output and exit codes (ghq-pull / ghq-update / ghq-sweep)

- スキップは`[skip]`（pullだけの場合は`[skip pull]`）、警告は`[warn]`、競合は`[conflict]`、
  失敗は`[failed]`のタグ行で出す。`git-pull-all`と`git-sweep`は単体コマンドなので、
  警告を`warning:`、失敗を`error:`で出す
- 1つでも`[failed]`のリポジトリがあれば、残りのリポジトリを処理したうえで終了コード1にする。
  スキップと警告は終了コード0
- `ghq-update`では、pull・stash復元・`uv sync`・`npm update/build`の失敗が`[failed]`になる

### my-hosts

サブコマンドは`status` / `pull` / `sweep`（省略時）/ `update` / `apps`。`apps`以外は対応する
`ghq-*`を実行し、続けて`ghq-status`を実行する（`--no-status`で省く。`status`とは併用不可）。

| サブコマンド | 実行内容 |
|---|---|
| `status` | `ghq-status` |
| `pull` | `ghq-pull` → `ghq-status` |
| `sweep` | `ghq-sweep` → `ghq-status`（`ghq-sweep`が全ローカルブランチのpullも行う） |
| `update` | `ghq-pull` → `ghq-update --sync-only` → `ghq-status` |
| `apps` | `install-my-apps`のみ（`ghq-status`は実行しない。リモートは`--no-gui`付き。`--`以降は`install-my-apps`へ転送。`-f`とは併用不可。Windowsのリモートは`skip`） |

`-f/--filter`は各`ghq-*`の`-f`へそのまま渡す（sshの先のシェルはzsh/bash/pwshのいずれもありうるため、安全な文字だけの値は素のまま、
それ以外は`'...'`で囲んで渡す。`'`を含む値は拒否する）。成功したステップでも`[skip` `[warn` `[conflict` `[failed`のタグ行と
`warning:`で始まる行は表示し、結果表では`ok!`と示す。

回帰テスト:

- [scripts/test-git-pull-all.sh](../scripts/test-git-pull-all.sh): 現在・他ブランチのfast-forward、
  `--fetch-only`、分岐・ローカル先行・dirty・detached HEAD・upstream未設定・gone・他worktree・
  fetch失敗・保護ブランチの新規作成
- [scripts/test-git-sweep.sh](../scripts/test-git-sweep.sh): マージ済み検出（fast-forward/squash）、
  未マージ保持、dirty・他worktreeの保護、`--no-pull`、`git-pull-all`との統合
- [scripts/test-ghq-pull-update-sweep.sh](../scripts/test-ghq-pull-update-sweep.sh): 失敗の
  分離と終了コード、dirty、ロックファイルstash、`--fetch-only`、`ghq-update`の旧オプション廃止、
  `ghq-sweep --no-pull`（`ghq`コマンドが必要）
- [scripts/test-my-hosts.sh](../scripts/test-my-hosts.sh): 後述の`## my-hosts`節を参照

いずれも使い捨てのリポジトリで検証し、ネットワークアクセスはしない。Windows版（`.ps1`）の
同等テストは、pwsh実行環境で動作確認できるようになってから追加する。

## obsidian-project-home

`obsidian-project-home`は、Git repositoryの`origin`と通常領域のObsidian Project Home
`projects/**/*.md`のfrontmatter `repositories`を照合する。リポジトリURLはGitHubのHTTPS、SSH、
`github-public:`、`github-private:`形式を`https://github.com/owner/repository`へ正規化する。

- Vaultの既定位置はprivate設定`obsidian/project-home-resolver.conf`の`vault_root`で指定する。環境変数`OBSIDIAN_VAULT_ROOT`または`--vault DIR`は明示的な上書きであり、テストにも使う
- 本文、`External systems`、`private/**`は探索しない。対応付けがない場合はexit `3`、複数ならexit `4`、設定またはfrontmatterが不正ならexit `5`で終了し、推測やProject Home作成を行わない
- `check`は全mappingの重複を検出する。成功時だけexit `0`とする
- Unix版とPowerShell版は同じ引数・終了コードを提供する。Windowsでは`obsidian-project-home.cmd`がbare command用のshimとなる

Unix版の回帰テストは[scripts/test-obsidian-project-home.sh](../scripts/test-obsidian-project-home.sh)で、GitHub HTTPS/SSH/alias正規化、一意・未登録・重複・不正frontmatterをネットワークなしで確認する。

## sync-labpc

- ジョブ定義（`~/.config/labpc/jobs.d/<job-name>.conf`）に基づき、SMB共有からこのMacへ
  読み取り専用の一方向rsyncを行う（詳細は[_sync-labpc-lib.sh](../bin/unix/_sync-labpc-lib.sh)冒頭のコメントを参照）
- 既にFinder等でマウント済みの共有があればそれを再利用し、未マウントならこの関数が
  自前でマウントして処理後にアンマウントする（macOSのsmbfsは同一サーバー・共有・
  ユーザーの二重マウントを許可しないため）
- `SMB_USER`にスペース等のURL予約文字が含まれる場合（例: `PPMS-External PC`）は、
  `_labpc_url_encode`が自動的にパーセントエンコードしてから`mount_smbfs`のURLへ
  渡す。非ASCII（日本語等）はUTF-8バイト単位でエンコードする。job conf側では生の
  アカウント名をそのまま書けばよい
- `sync-labpc list`で全ジョブ定義（HOST/SHARE/SMB_USER/REMOTE_SUBPATH/DEST）を
  一覧表示できる

### Password authentication (Keychain)

`SMB_USER`が`guest`以外のジョブは、パスワードを一切スクリプトに持たせていない。
生の`mount_smbfs`（このスクリプトが使う経路）は、ログインキーチェーンの
Internetパスワード項目（server/account/protocol=smbが一致するもの）を自動的に
参照し、TTYの有無に関わらず無言で認証する。これはFinderの「サーバへ接続」
（`open smb://user@host/share`）が保存するのと同じキーチェーン項目であり、
別途スクリプト側でパスワードを管理する仕組みは不要。

初回セットアップ（またはパスワード変更後）は、対象ジョブについて一度だけ

```sh
open "smb://<SMB_USER>@<HOST>/<SHARE>"
```

を実行し、ダイアログで現在の正しいパスワードを入力・「このパスワードを
キーチェーンに保存」を有効にして接続する。以後は`sync-labpc`実行時（Terminal・
LaunchAgentいずれも）、キーチェーンの値がプロンプトなしで使われる。

注意点:

- キーチェーン項目のserverは`HOST`（IP）と一致している必要がある。Finderの接続ダイアログや
  ネットワーク一覧からホスト名（例: `vsm-pc`）で接続して保存すると、項目のserverがホスト名に
  なり、IPで接続する`sync-labpc`からは参照されず毎回パスワードを求められる。
  セットアップは必ず`open "smb://<SMB_USER>@<HOST>/<SHARE>"`（IP指定）で行う
- `sync-labpc`は`mount_smbfs -N`でマウントするため、キーチェーンに使える資格情報が
  ない場合はパスワードを聞かず`マウントに失敗しました`で終了する。複数ジョブでこの
  失敗や`Password:`が続く場合は、Finderの「サーバへ接続」（Cmd+K）で各ジョブを
  IP指定（`smb://<SMB_USER>@<HOST>/<SHARE>`）で接続し直して項目を保存し直すと
  解消した実績がある（日本語・スペースを含むアカウント名でも同様に動作する）
- `open smb://`（Finder経由）は、キーチェーンにパスワードが保存済みでも
  **接続のたびに人間の確認（ダイアログの「接続」クリック）を要求する**。これは
  生の`mount_smbfs`とは別経路（NetAuthAgent）のための仕様で、キーチェーンが
  機能していない証拠ではない。無人実行の可否は生`mount_smbfs`側の挙動だけで
  判断すること
- 上記セットアップ後も`mount_smbfs`が`Authentication error`で失敗する場合は、
  該当ジョブのキーチェーン項目に**古い/間違ったパスワードが残っている**のが
  原因である可能性が高い。ACL（アクセス制御）の変更では直らないため、Finder
  経由で現在の正しいパスワードを入力し直してキーチェーンの値そのものを更新する
- `guest`ジョブはそもそもパスワードが不要なため、この手順は不要

## claude-perms

Claude Code の permissions（`.claude/settings.local.json` / `~/.claude/settings.json`）を
整理するツール。サブコマンドの詳細と正規化規則は [claude-perms](../bin/unix/claude-perms)
冒頭のコメントを参照。

- `format` / `check` / `candidates` / `format-global` / `remove` / `remove-global` / `merge` /
  `apply` の8サブコマンドを持つ
- `candidates --json [DIR...]`は、グローバル・pathRuleいずれでも未カバーの移管候補を
  `[{"target": DIR, "allow": [...]}...]`形式のJSONで出力する（人手で必要なものだけへ
  絞り込んでから使う想定）。`remove --json <FILE|->`はそのJSON（絞り込み後でも元の
  ままでもよい）を読み、targetごとの`settings.local.json`からallowに列挙したエントリを
  厳密一致で削除する（既定はdry-run、`--apply`または`-y`で実際に削除）
- `~/.claude/claude-perms.json`（Claude Code本体は読まない専用設定。パス情報を含むため
  実体はdotfiles-privateの`ai/claude/claude-perms.json`）に`pathRules`
  （`pathGlob` → `allow`）を宣言すると、`merge [DIR...]`がDIRの絶対パスに一致する
  pathRuleのallowを`DIR/.claude/settings.local.json`へ**追記**（既存の
  allowはそのまま残す）する。`apply [DIR...]`は同じくpathRuleに一致するDIRを
  対象にするが、そのDIRのallowをpathRuleの内容で**置き換える**（既存のうち
  pathRuleに含まれないものは消える）。`dots brew/npm/pipx/dock/shortcuts`の`sync`
  （システム実態→管理ファイルの方向）とはコマンド名の向きが逆（宣言→ローカル）
  になるため、あえて`sync`ではなく`merge`と名付けている。`pathGlob`は単一文字列の
  ほか文字列配列も指定でき、配列の場合はいずれか1つに一致すればそのpathRuleの
  allowが適用される（同じallowを複数の無関係なパスパターンへまとめて配布したい
  場合に、pathRuleエントリごとallowを重複させずに済む）。複数のpathRuleが
  一致した場合、および1つのpathRule内でpathGlobの複数要素が一致した場合も、
  allowを全て合成する（OR/和集合）。一致するpathRuleが無いDIRはmerge・applyとも
  何もしない（settings.local.jsonを空にするような操作はしない）。pathRuleを
  外しても、過去に`merge`で追加したエントリを自動削除はしない（`apply`なら
  次回実行時に置き換えで消える）。典型的な移管フロー: `candidates`（`--json`も可）
  でローカル限定のallowを確認する→必要なものだけ`claude-perms.json`の
  `pathRules`へ手動で追記する→`apply`を実行すると、そのDIRのallowはpathRuleの
  内容だけになり、昇格しなかった残りは自動的に消える（merge・apply同様、
  dry-run無しで直接書き込む）。pathRuleを作らず個別に削除したいだけの場合は
  `remove --json`を使う
- `format` / `format-global` / `merge` / `apply`は、残ったBash allowエントリのうち末尾wildcard
  （`cmd:*`等）を持つものについて、run-quiet修飾版（`run-quiet cmd:*`）がまだ無ければ
  自動追加する（「素のコマンドを許可していればrun-quiet版も許可されているとみなす」
  という方針のため、pathRules・グローバル側は素のコマンドだけ書けばよい）。ただし
  これは「無ければ足す」自動補完に限られ、`format`の実削除判定（グローバルで
  カバー済みのローカルエントリを消す判定）はrun-quiet版を誤って失わないよう厳密な
  前方一致のままにしている。`candidates`の「pathRuleでカバー済みなので除外」判定
  だけは、run-quiet修飾版も考慮する緩い判定を使う
- `~/.claude/claude-perms.json`の`forbiddenAllow`に列挙したエントリ（例:
  `Bash(run-quiet:*)`のような無制限wildcard）は、`format`/`format-global`が
  ローカル・グローバルどちらのallowからも自動削除する

## dots ghq

`ghq-update`の更新対象は各リポジトリの`git config local.keep-up-to-date`（`true`のみが
対象。未設定はグローバル既定の`false`）で決まる。リポジトリごとにGit configを手で
設定するとどれが対象か分からなくなるため、対象リポジトリの一覧を
dotfiles-privateの宣言ファイルとして管理し、`dots ghq`で実状態と突き合わせる。
リポジトリ名（privateリポジトリを含む）を公開リポジトリへ書かないため、
宣言ファイルはdotfiles-privateに置き、ロジックだけをdotfiles（`ghq/keep-up-to-date.sh` /
`.ps1`）に置く。

**宣言ファイル**（dotfiles-private配下）:

- `ghq/keep-up-to-date`: 共通の宣言。1行1件でghq rootからの相対パス
  （`github.com/<owner>/<repo>`）を書く。`#`以降はコメント
- `ghq/keep-up-to-date.local`: この端末だけの追加分（`.gitignore`対象、手編集専用）。
  `Brewfile.local`と同様に追加のみで、打ち消し（`!`等）やglobは持たない
- 宣言の集合は両ファイルの和集合。比較は大文字小文字と末尾スラッシュを区別しない
- 雛形は`templates/dotfiles-private/ghq/keep-up-to-date.example`

**実状態**は各リポジトリの`git config --local --get local.keep-up-to-date`が`true`かどうか
（グローバル設定の影響を受けない）。`false`は書かず、対象から外すときは`--unset`する。

**コマンド**（`dots ghq {apply|diff|sync|merge}`。`cache`は実状態をGit configから直接読めるため持たない）:

| 動詞 | 動作 |
|---|---|
| `diff` | 宣言と実状態の差分を表示（差分があれば終了コード1）。`+actual`は`true`だが宣言なし、`-file`は宣言済みだが`true`でない |
| `apply` | 宣言 → 実状態。宣言済みの取得済みリポジトリを`true`にし、宣言にない`true`は`--unset`する（完全一致）。明示的な`false`は触らない |
| `sync` | 実状態 → 共通宣言（完全一致）。宣言にない`true`を追加し、`true`でない取得済みエントリを削除する |
| `merge` | 実状態 → 共通宣言。追加のみで削除しない |

- `sync` / `merge`の書き込み先は共通宣言のみ。`.local`は書き換えず、`.local`で宣言済みの
  リポジトリは共通宣言へ昇格させない。書き戻しではコメント・空行を先頭にまとめ、
  エントリは重複を除いて大文字小文字を無視してソートする
- ghq rootに取得されていないリポジトリは、宣言にあっても全動詞で無視する（`diff`で
  警告せず、`sync`でも削除しない）。取得された時点で次の`apply`から有効になる
- `.local`にだけ宣言され`true`でないリポジトリは、`sync`では共通宣言に関係ないため
  `diff`に残り続ける（`apply`で解消する）
- 宣言ファイル（共通）が無い、または`ghq`が無い場合、`dots check`のサマリは何も表示せず、
  `dots ghq`各動詞はエラーで終了する。スクリプトの終了コードは、`diff`の差分ありが1、
  エラー（宣言なし・`ghq`なし・引数誤り・想定外の失敗）が2で区別し、`dots ghq diff`は
  他の`diff`と同様に差分ありを正常終了として扱い、エラー（2）だけを伝える
- 複数の`ghq`rootが設定されている場合も、各リポジトリを所属するrootからの相対パスとして扱う
- `dots check`は差分があるとき`⚠ ghq keep-up-to-date: +N 宣言なし / -N 未適用`を表示する。
  Windowsの`dots check`は`ghq diff --summary`の結果を要約の1行（`⚠ ghq keep-up-to-date: ...`）として表示する
- 未決定（`.venv`/`node_modules`はあるが宣言も`true`もない）リポジトリの検出は行わない。
  全体の状態は`ghq-status`のKEEP列で確認する

テスト用に`GHQ_ROOT`（ghq root）と`DOTFILES_PRIVATE_DIR`（dotfiles-privateの場所）で
上書きできる。回帰テストは[scripts/test-ghq-keep-up-to-date.sh](../scripts/test-ghq-keep-up-to-date.sh)
（Unix版のみ）。

## my-hosts

`bin/unix/my-hosts`は、宣言した他のホストで`ghq-pull`/`ghq-update`/`ghq-sweep`/`ghq-status`/`install-my-apps`を
ssh経由で実行する。実行元はmacOS専用（`scripts/check-bin-parity.sh`の例外）で、対象にはmacOSに加えて
Windowsも宣言できる。サブコマンドと
共通ルールは前節、詳細なオプションは[my-hosts](../bin/unix/my-hosts)冒頭のコメントを参照。

- **対象の宣言**: dotfiles-privateの`hosts/hosts`に、実行元ごとに1行1件で書く
  （`<実行元>: <sshホスト名> ...`）。実行元は`scutil --get LocalHostName`と大文字小文字を
  区別せず照合し、一致しなければ`--from NAME`で指定する。どちらでも決まらない、または
  宣言にない実行元はエラーとする。対象は実行元ごとに非対称でよい（全ホスト相互とは限らない）。
  端末固有の追加分は`hosts/hosts.local`（`.gitignore`対象、手編集専用）に書く
- **処理順**: ホスト間は並列に処理する（`-j N`で同時数を制限、`-j 1`で逐次）。表示と結果表は
  実行元自身（`--no-local`で省略）→宣言順のリモートの順にまとめて出す。ステップはサブコマンドで決まり（`status` / `pull` /
  `sweep`（既定）/ `update`）、ホスト内では逐次に実行する。`--no-status`でstatusを省く
  `-H`は宣言済みの対象だけを絞り込む（宣言にないホストはエラー）
- **リモート実行**: `ssh -o BatchMode=yes -o ConnectTimeout=5 <host> ghq-pull`のように、
  リモートの`ghq-*`を直接呼ぶ（`my-hosts`は再帰しない）。非対話sshでも`~/.local/bin/dotfiles`が
  PATHに入っていることを前提とする
- **Windowsを対象にする場合の制限**: OpenSSHサーバーを有効にし、鍵認証（管理者ユーザーなら
  `administrators_authorized_keys`）とDefaultShellのpwsh（`HKLM:\SOFTWARE\OpenSSH`の`DefaultShell`）を
  設定すると、`apps`（`skip`）は実行できる（`status`はネットワークを使わないため動く見込みだが未確認）。pwshのprofileが`~/.local/bin/dotfiles`をPATHに入れ、
  ssh経由の非対話実行では出力をUTF-8にそろえ、起動時の警告表示を出さず、gitのsshが入力待ちで
  止まらないようにする。**`pull`/`sweep`/`update`はGitHubへのfetchが必要で、現時点では未対応**。
  宣言で`<ホスト>:windows`と書いたホストでは、これらのステップをsshで実行せず`[skip]`（結果表は`skip`、
  終了コードに影響しない）として通知する。実装（`step_command`）は残してあり、`WINDOWS_SKIP_STEPS`を空にすれば有効化できる。
  sshd経由のセッションはネットワーク型ログオンになり、ssh-agentに預けたパスフレーズ付きの鍵で
  GitHubへ署名できず、`Permission denied (publickey)`で失敗する（`ssh-add -l`で鍵は見える。
  原因はこの観測からの推定で、Windows側の設定では解消できなかった）。解消するには、agentを使わない
  非対話用の鍵（パスフレーズ無し）などが必要で、扱いは#107で検討する
- **失敗の扱い**: 接続不能・認証失敗（鍵ファイルが無い場合を含む）・コマンド失敗はすべて失敗とし、
  残りのホストは続行する。接続できなかったホストの残りのステップは`skip`と表示する。
  終了コードは失敗が1つでもあれば1
- **出力**: 既定は失敗したステップと`status`の出力だけを表示し、`-v`で成功したステップの出力も表示する。
  全出力は`~/.cache/dots/hosts/<host>.log`に残す。最後にホスト×ステップの結果表を出す。
  `status`は既定で異常のあるリポジトリだけ、`-a`で全件
- **スキップ・警告**: `ghq-pull`/`ghq-sweep`等はdirtyによるスキップなどを`[skip ...]`/`[warn]`/
  `[conflict]`/`[failed]`のタグ行で、`git-pull-all`/`git-sweep`は`warning:`行で出し、終了コードは
  0のままにする。成功したステップでも、これらの行を直前のリポジトリ見出し付きで必ず表示し、
  結果表では`ok!`と示す（終了コードには影響しない）
- **進捗表示**: 標準エラー出力が端末のときは、ホストごとに1行（`pull:ok sweep:⠹ status:-` の形）で
  ステップの状態を更新表示する。完了後に消してから宣言順の出力と結果表を出す。
  端末でない場合や`--no-progress`では出さない
- **`apps`**: ログインしているとは限らないリモートでは`install-my-apps --no-gui`を実行する
  （アプリの終了・ウィジェットキャッシュのクリア・起動・ウィジェット編集画面を省く。ウィジェット拡張は
  そのMacで次にアプリを起動したときに登録される）。実行元自身は通常どおりGUI付き。
  `--`以降の引数は各ホストの`install-my-apps`へ上記と同じ規則でクォートして転送する。
  `bin/windows/install-my-apps.ps1`はスタブで、何もせず専用の終了コード64で終了する。`my-hosts`は
  `apps`で64が返ると失敗ではなく`skip`（`[skip] apps: このホストでは未対応です`）として扱い、
  終了コードにも影響させない
- **`--dry-run`**: 実行内容だけを表示し、sshもコマンドも実行しない

回帰テストは[scripts/test-my-hosts.sh](../scripts/test-my-hosts.sh)（sshと`ghq-*`は偽のコマンドに
差し替える）。Windows版の`my-hosts`（Windowsを実行元にする）は作らない。
Windowsを対象にした実機のssh動作は自動テストの対象外で、手動で確認する（`apps`のskipは確認済み、`pull`系は上記の制限により`:windows`宣言でskipする）。

## ghq-status

`bin/unix/ghq-status` の BRANCHES 列・DEV-CHARTER 列・keep-up-to-date 判定ロジックは [ghq-status](../bin/unix/ghq-status) 冒頭のコメントと [DEVELOPING.md](../DEVELOPING.md) を参照。

BRANCHES列は`.gitattributes`の`repo-protected-branches`をローカル・origin双方、
`repo-remote-only-branches`をoriginだけの期待ブランチとして検証する。総数だけでなく
ブランチ名と配置も比較し、欠落・余分・remote-onlyのローカル作成をハイライトする。
Unix版とWindows版は同じ判定規則を使う。

配色は、対応が必要な状態を赤（保護対象外のBRANCH、cleanでないGIT STATUS、
BRANCHESの方針違反、古いDEV-CHARTER）で示す。KEEPは更新対象の`keep`を緑、
更新対象外の`skip`をグレーで示し、`local.keep-up-to-date`が未設定の場合も
実際の更新動作に合わせて`skip`と表示する。

各リポジトリの状態取得では、status・branch・upstream差分・stashを
`git status --porcelain=v2 --branch --show-stash --ahead-behind --untracked-files=all`で
一括取得する。属性、fallback設定、
ref一覧もそれぞれ1回のGit呼び出しで取得し、リポジトリ単位では並列に処理する。
並列数は環境変数`GHQ_STATUS_JOBS`で変更でき、未設定時は8とする。収集完了後に
元のリポジトリ順へ並べ直すため、並列数によって表示順は変わらない。
