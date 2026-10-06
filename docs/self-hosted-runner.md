# Self-hosted GitHub Actions Runner (macOS)

private リポジトリの macOS ジョブ（`xcodebuild`・`swift test`）を、自分の Mac で実行するための
ネイティブ runner の構成・立ち上げ手順・運用をまとめる。GitHub-hosted の macOS runner は
Linux の実質約 10 倍の単価で、無料枠をすぐ使い切るため（dev-charter の
[CI_POLICY](https://github.com/y-marui/dev-charter/blob/full/topics/CI_POLICY.md#runner-billing)
の Runner Billing 参照）、macOS ジョブだけを手元の Mac に逃がす。self-hosted runner の実行は無料。

進捗・TODO は Issue（y-marui/dev-charter#152）で管理し、ここには書かない。

## Overview

~~~text
PR / push ─► hosted の Linux ジョブ（changes・security・lint・gate）
          └► macOS ジョブ（Build & Test） ── vars.MACOS_RUNNER が設定されていれば ──► 自分の Mac（label: macos-sh）
                                            └─ 未設定・fork の PR なら ────────────► GitHub-hosted の macos-latest
~~~

- runner は **リポジトリごと**に登録する（個人アカウントにはアカウント単位の runner がない）。
  1 台の Mac に、対象リポジトリの数だけ runner が常駐する
- runner は専用の標準ユーザー（既定 `ghrunner`、管理者権限なし）で、**LaunchDaemon** として動く。
  ログインセッションは不要で、Mac が起動していれば常に待ち受ける
- CI の `runs-on` は、リポジトリ変数 `MACOS_RUNNER`（値は runner のラベル `macos-sh`）で切り替える。
  変数を外せば、GitHub-hosted に戻る（runner が全台停止したときのフォールバック）
- 登録・解除は `macos/setup_actions_runner.sh` で行う（冪等。`--dry-run` で実行内容だけ表示できる）

### Design decisions

| 判断 | 理由 |
|---|---|
| Docker ではなくネイティブ | コンテナの中で macOS は動かず、`xcodebuild` に macOS が要る |
| LaunchAgent ではなく LaunchDaemon | 公式の `svc.sh` は実行ユーザーの LaunchAgent（ログインセッション前提）を作る。ログインなしで常駐させるため、`UserName` つきの LaunchDaemon を自作する（公式の plist テンプレートが `UserName` に対応している） |
| 専用の標準ユーザー | CI のジョブが、普段使いのアカウントのファイル・キーチェーンに触れないようにする |
| private リポジトリだけに登録 | public では fork の PR が runner 上で任意のコードを実行できる。スクリプトは public を拒否する |
| Xcode を `DEVELOPER_DIR` で固定 | hosted の `macos-latest`（macOS 26）の既定の Xcode に合わせ、どちらの runner でも同じ結果にする |
| CI は署名なしビルド | 署名鍵・シークレットを runner に渡さない |

## Prerequisites

Mac ごとに、次を用意する。

| 項目 | 内容 |
|---|---|
| 専用ユーザー | 管理者権限のない標準ユーザー（既定名 `ghrunner`）。ホームディレクトリあり |
| Xcode | hosted の `macos-latest` の既定と同じバージョンを `/Applications/Xcode-<version>.app` に**並べて**入れる（`Xcode.app` は上書きしない）。確認: https://github.com/actions/runner-images の macOS イメージの一覧 |
| `gh` | 管理者権限のあるアカウントで認証済み（runner の登録トークンの取得に使う） |
| Homebrew の `xcodegen` | CI の `command -v xcodegen \|\| brew install xcodegen` が、導入済みなら `brew` を呼ばない。runner ユーザーは Homebrew に書き込めないため、事前に入れておく |
| ディスクの空き | Xcode の展開と、runner ごとの DerivedData に、40GiB 以上あると安心 |
| スリープ | CI を受ける時間帯にスリープしない設定にする（`sudo pmset -a sleep 0` など。システム設定の変更なので手動で行う） |

## Bring up a new Mac

別の Mac（自宅・職場など）で立ち上げる手順。**職場の Mac を使う場合は、職場の規程とネットワーク制限
（GitHub Actions への通信）を事前に確認する。**

### 1. Create the runner user

管理者権限のない標準ユーザーを作る（`sudo` のパスワードが要る。パスワードはプロンプトで入力する）。

~~~sh
sudo sysadminctl -addUser ghrunner -fullName "GitHub Runner" -password -
~~~

ログイン画面に出さない（任意）:

~~~sh
sudo dscl . create /Users/ghrunner IsHidden 1
~~~

### 2. Install Xcode side by side

1. Apple Developer の Downloads から、対象バージョンの Xcode の `.xip` をダウンロードする
2. iCloud Drive の外（ローカルのディスク）で展開し、`/Applications/Xcode-<version>.app` に置く。
   iCloud Drive の中で展開すると、12 万個のファイルが同期の対象になり、あとからオフロードされるおそれがある
3. 動作を確認する:

~~~sh
DEVELOPER_DIR=/Applications/Xcode-26.6.app/Contents/Developer xcodebuild -version
~~~

ライセンスの同意・初回セットアップが済んでいない場合のみ（確認: `xcodebuild -license check`、
`xcodebuild -checkFirstLaunchStatus`）:

~~~sh
sudo DEVELOPER_DIR=/Applications/Xcode-26.6.app/Contents/Developer xcodebuild -license accept
~~~

~~~sh
sudo DEVELOPER_DIR=/Applications/Xcode-26.6.app/Contents/Developer xcodebuild -runFirstLaunch
~~~

### 3. Register the runners

dotfiles を取得して（[setup-mac.md](setup-mac.md) 参照）、リポジトリを指定して実行する。
先に `--dry-run` で内容を確認する。

~~~sh
bash macos/setup_actions_runner.sh install --dry-run OWNER/REPO
~~~

~~~sh
bash macos/setup_actions_runner.sh install OWNER/REPO...
~~~

環境変数で既定値を変えられる: `RUNNER_USER`（`ghrunner`）、`RUNNER_LABEL`（`macos-sh`）、
`XCODE_APP`（`/Applications/Xcode-26.6.app`）、`RUNNER_VERSION`（最新）。
`XCODE_APP` は、手順 2 で入れた Xcode に合わせる。

スクリプトがすること:

1. リポジトリが private であることを確認する（public は拒否）
2. runner のアーカイブを取得し、公式の sha256 と照合する
3. `~ghrunner/actions-runner/<repo>` に展開し、登録トークンで `config.sh` を実行する
   （トークンはファイルに残さない。ラベルは `macos-sh`、名前は `<LocalHostName>-<repo>`）
4. `.env` に `DEVELOPER_DIR` を、`.path` に PATH（`/opt/homebrew/bin` を含む）を書く
5. `/Library/LaunchDaemons/com.y-marui.actions-runner.<repo>.plist` を作り、`launchctl bootstrap system` で常駐させる
6. GitHub 上で runner が `online` になるまで待つ

### 4. Private dependencies (deploy key)

CI が private の SwiftPM 依存（`ssh://git@github.com/<owner>/<repo>.git`）を解決する場合、
runner ユーザーに**読み取り専用のデプロイキー**が要る。ない場合、`swift package resolve` が
`Host key verification failed` で失敗する。

- デプロイキーは **1 つのリポジトリにしか登録できない**。依存先のリポジトリごとに、別の鍵を作る
- 鍵は **Mac ごとに別に作る**（Mac ごとに別の鍵を、同じ依存先のデプロイキーに複数登録してよい）
- 鍵は `ghrunner` のホームに置く。`ghrunner` で動くすべての runner（全リポジトリ分）が使える。
  そのため、依存先を使う側のリポジトリごとの追加設定は不要
- 鍵の名前は `ghrunner-<依存先のリポジトリ名>`

以下は `<dep>`（依存先のリポジトリ名）と `<owner>` を置き換える。

~~~sh
sudo -u ghrunner -H mkdir -p -m 700 /Users/ghrunner/.ssh
~~~

~~~sh
sudo -u ghrunner -H ssh-keygen -t ed25519 -N "" -C "ghrunner@$(scutil --get LocalHostName) <dep> read-only" -f /Users/ghrunner/.ssh/ghrunner-<dep>
~~~

GitHub が公開しているホスト鍵を `known_hosts` に入れる（初回接続の信用に頼らない）:

~~~sh
gh api meta --jq '.ssh_keys[]' | sed 's/^/github.com /' | sudo -u ghrunner -H tee /Users/ghrunner/.ssh/known_hosts >/dev/null
~~~

`~ghrunner/.ssh/config` に、鍵を指定する。**依存先が 1 つの間は次のとおり**:

~~~sh
printf 'Host github.com\n  IdentityFile /Users/ghrunner/.ssh/ghrunner-<dep>\n  IdentitiesOnly yes\n' | sudo -u ghrunner -H tee /Users/ghrunner/.ssh/config >/dev/null
~~~

公開鍵を、依存先のリポジトリに**読み取り専用**で登録する:

~~~sh
gh api -X POST repos/<owner>/<dep>/keys -f title="ghrunner@$(scutil --get LocalHostName) (read-only)" -f key="$(sudo -u ghrunner -H cat /Users/ghrunner/.ssh/ghrunner-<dep>.pub)" -F read_only=true --jq '"registered: \(.title) read_only=\(.read_only)"'
~~~

接続を確認する（`Hi <owner>/<dep>! You've successfully authenticated` と出れば成功）:

~~~sh
sudo -u ghrunner -H ssh -T git@github.com
~~~

> **依存先が 2 つ以上になったら:** 1 つの `Host github.com` に複数の `IdentityFile` を並べると、
> GitHub は最初に認証できた鍵のリポジトリだけを返す。依存先ごとに `Host` のエイリアス
> （例: `github-<dep>`）を `config` に作り、依存の URL をそのエイリアスにする必要がある
> （または、依存先を使う側のリポジトリを、依存先のコラボレーターにした machine user に切り替える）。
> 設計が必要なので、その時点で見直す。

### 5. Enable it per repository

runner が `online` になったら、リポジトリ変数を設定して、`ci.yml` の macOS ジョブを切り替える
（private リポジトリだけ。public には設定しない）。

~~~sh
gh variable set MACOS_RUNNER --body macos-sh -R OWNER/REPO
~~~

最初の PR で、`Build & Test` のログの `Runner name: '<LocalHostName>-<repo>'` で、自分の Mac で
実行されたことを確認する。

## Operations

### Status

~~~sh
bash macos/setup_actions_runner.sh status OWNER/REPO...
~~~

GitHub 側の一覧: `gh api repos/OWNER/REPO/actions/runners --jq '.runners[]|"\(.name) \(.status)"'`

### Add a repository

手順 3（`install`）と手順 5（変数の設定）を、そのリポジトリに対して行う。`ci.yml` が、
dev-charter の Swift 向けの構成（`runs-on: ${{ vars.MACOS_RUNNER ... }}`）になっている必要がある。

### Fall back to GitHub-hosted

Mac を止める・runner を直す間は、変数を外す。すべての runner が停止していると、ジョブは待機のままになり、
hosted には自動で落ちない。

~~~sh
gh variable delete MACOS_RUNNER -R OWNER/REPO
~~~

### Remove

~~~sh
bash macos/setup_actions_runner.sh uninstall OWNER/REPO
~~~

LaunchDaemon の削除、GitHub 上の runner の登録解除、runner のディレクトリの削除を行う。
あわせて `gh variable delete MACOS_RUNNER` で変数を外す。

### Update the runner

runner はジョブの開始時に、必要なら自分で更新される。手動で新しいバージョンにしたい場合は、
`RUNNER_VERSION` を指定して、いったん `uninstall` してから `install` する。

### Logs

~~~text
/Users/ghrunner/Library/Logs/com.y-marui.actions-runner.<repo>/stdout.log
/Users/ghrunner/Library/Logs/com.y-marui.actions-runner.<repo>/stderr.log
~~~

## Known behaviors

- **同時実行**: 1 つの runner は同時に 1 ジョブだけ処理する。複数のリポジトリが同時にビルドすると、
  runner が並列に動き、1 台の Mac の負荷が上がって各ジョブが遅くなる（6 リポジトリの同時実行で
  1〜2 分のジョブが 4〜7 分）。課金は発生しない。dev-charter の更新を複数のアプリに一斉に
  マージするときに起きやすい
- **フォールバックの制限**: private の SwiftPM 依存を持つリポジトリは、デプロイキーが `ghrunner` にだけあるため、
  hosted では依存を解決できない。self-hosted 専用になる
- **OS・ツールチェーンの差**: Mac の OS と Xcode が hosted と違うと、結果が食い違う。Xcode を固定していても、
  OS は hosted より新しい場合がある（確認済みの実例: Swift 6.3 の SwiftPM は `swift test` で `.xcstrings` を
  `.lproj` にコンパイルしないため、`.lproj` を前提にするテストは Xcode 26.6 で失敗し、Xcode 27 で成功した）

## Troubleshooting

| 症状 | 原因と対処 |
|---|---|
| ジョブが queued のまま進まない | runner が offline、または `MACOS_RUNNER` のラベルと runner のラベルが違う。`status` で確認する |
| `Host key verification failed` | `~ghrunner/.ssh/known_hosts` がない。手順 4 の `known_hosts` を入れる |
| `Permission denied (publickey)` | デプロイキーが未登録、または `config` の `IdentityFile` が違う。手順 4 の接続確認で切り分ける |
| `Error: /opt/homebrew/Cellar is not writable` | runner ユーザーは Homebrew に書き込めない。`xcodegen` を事前に入れ、CI を `command -v xcodegen \|\| brew install xcodegen` にする |
| Xcode のバージョンが想定と違う | `~ghrunner/actions-runner/<repo>/.env` の `DEVELOPER_DIR` を確認する。CI のログの `xcodebuild -version` で確かめる |
| `launchctl` の登録に失敗する | `plutil -lint /Library/LaunchDaemons/<plist>`、`sudo launchctl print system/<label>`。plist の所有者は `root:wheel`、権限は 644 |

## Security notes

- 登録するのは **private リポジトリだけ**。public には登録しない（スクリプトも拒否する）
- runner は管理者権限のない専用ユーザーで動く。CI の署名なしビルドは、署名鍵・シークレットを必要としない
- `ghrunner` で動く**すべての runner が同じデプロイキーを読める**。どれかのリポジトリのワークフローが
  書き換えられると、デプロイキーで読める依存先のソースを読めてしまう。読み取り専用・同じ所有者のリポジトリに
  限る前提で許容している
- 登録トークンは 1 時間で失効する登録専用の値で、ファイルには残さない。`config.sh` の実行中だけ、
  プロセスの引数に載る
- fork の PR は、`runs-on` の式が常に GitHub-hosted に回す

## Linux runner (Docker)

private リポジトリの Linux ジョブ（`security`・`changes`・`lint`・`gate`・`dev-charter-check` 等）を、
Docker 上の Linux runner で実行するための構成。GitHub-hosted の Linux も、1 job ごとに分単位で
切り上げて課金されるため、リポジトリと PR が増えると無料枠を使い切る。self-hosted は無料。

- イメージ・登録スクリプト: `docker/actions-runner/`（`Dockerfile`・`entrypoint.sh`・`setup.sh`）
- runner は **リポジトリごとに 1 コンテナ**（macOS と同じ理由）。登録状態は Docker volume `ar-<repo>`、
  pre-commit や uv のキャッシュは共有 volume `ar-cache` に置く
- CI の `runs-on` は、リポジトリ変数 `LINUX_RUNNER`（値は既定でラベル `linux-sh`）で切り替える。
  変数を外せば GitHub-hosted に戻る（runner が止まったときのフォールバック）
- **private リポジトリだけ**に登録する。`setup.sh` は public を拒否する
- コンテナは非 root で、ホストの docker ソケットはマウントしない。SwiftLint はイメージに入れ、
  docker を使わない
- `pull_request_target` で特権トークンを使う job（assign）と、OIDC を使う release job は載せない

~~~sh
bash docker/actions-runner/setup.sh build
bash docker/actions-runner/setup.sh install [--dry-run] OWNER/REPO...
bash docker/actions-runner/setup.sh status OWNER/REPO...
gh variable set LINUX_RUNNER --body linux-sh -R OWNER/REPO   # runner を登録してから設定する
~~~

どのホストにどのリポジトリを登録したかは、公開しない台帳（dotfiles-private）で管理する。

## Windows (native)

private リポジトリの Windows ジョブ（`dotnet format`・`dotnet publish`・MSI のビルド等）を、自分の
Windows PC で実行するためのネイティブ runner。macOS 版と同じ設計で、`windows/setup_actions_runner.ps1` が
登録・解除する。Linux runner（`docker/actions-runner/`）とは別物で、同じ PC に併存できる。

### Design decisions

| 判断 | 理由 |
|---|---|
| Docker ではなくネイティブ | Windows コンテナは Windows ネイティブのコンテナエンジンが要り、WSL2 の Docker（Linux コンテナ）では動かない。ホストとコンテナの OS バージョンを合わせる必要があり、イメージも大きいため、まずネイティブにする |
| Windows サービス | ログオン不要で常駐する。macOS の LaunchDaemon に相当 |
| 専用の標準ユーザー（既定 `ghrunner`） | macOS 版と同じ名前。管理者権限なしで動かし、CI のジョブが普段使いのアカウントのファイルに触れないようにする |
| 展開先は `C:\actions-runner\<repo>` | MAX_PATH を避ける短い絶対パス。継承を切った ACL で、Administrators / SYSTEM / `ghrunner` だけが触れる |
| ラベルは `windows-sh` | macOS（`macos-sh`）・Linux（`linux-sh`）に揃える。macOS 版との違いはラベルだけ |
| runner 名は `<ホスト名>-<repo>-win` | 同じ PC の Linux runner（`<ホスト名>-<repo>`）と同名にならないようにする（`--replace` で互いを置き換えてしまうため） |
| private リポジトリだけに登録 | public では fork の PR が runner 上で任意のコードを実行できる。スクリプトは public を拒否する |

### Bring up

**1. 専用ユーザーを作る**（管理者の PowerShell。パスワードはプロンプトで入力する）:

~~~powershell
$pw = Read-Host "ghrunner password" -AsSecureString
New-LocalUser -Name ghrunner -Password $pw -PasswordNeverExpires -UserMayNotChangePassword -Description "GitHub Actions runner"
Add-LocalGroupMember -SID S-1-5-32-545 -Member ghrunner
~~~

**2. 前提のツール**: `git` と `dotnet`（SDK）をシステム全体の PATH に入れておく（runner のサービスが見られるように、
ユーザー単位ではなくマシン単位でインストールする）。

**3. 登録する**（管理者の PowerShell。先に `-DryRun` で内容を確認する）:

~~~powershell
pwsh windows/setup_actions_runner.ps1 install -DryRun OWNER/REPO
~~~

~~~powershell
pwsh windows/setup_actions_runner.ps1 install OWNER/REPO
~~~

パスワードのプロンプトには、手順 1 で決めた `ghrunner` のパスワードを入力する（サービスのログオンにだけ使い、保存しない）。
runner が `online` になるまで待つ。

**4. 有効にする**（runner が `online` になってから。private リポジトリだけ）:

~~~sh
gh variable set WINDOWS_RUNNER --body windows-sh -R OWNER/REPO
~~~

`ci.yml` が `runs-on: ${{ vars.WINDOWS_RUNNER && !github.event.pull_request.head.repo.fork && vars.WINDOWS_RUNNER || 'windows-latest' }}`
になっている必要がある（dev-charter の `LINUX_RUNNER` の方式を Windows に広げたもの）。

### Operations

~~~powershell
pwsh windows/setup_actions_runner.ps1 status OWNER/REPO
~~~

~~~powershell
pwsh windows/setup_actions_runner.ps1 uninstall OWNER/REPO
~~~

- サービスの確認: `Get-Service 'actions.runner.*'`
- ログ: `C:\actions-runner\<repo>\_diag\`
- 止めるときは `gh variable delete WINDOWS_RUNNER -R OWNER/REPO` で hosted に戻す
  （runner が停止していると、ジョブは待機のままになり、hosted には自動で落ちない）

### Security notes

- 登録するのは **private リポジトリだけ**。public には登録しない
- self-hosted runner は、GitHub-hosted のようにジョブごとにきれいな環境にならない。ジョブの変更が次のジョブに残る
- CI にシークレットを渡さない。`ghrunner` のホームに鍵を置かない
- `ghrunner` のパスワードはサービスの設定にだけ使われ、このスクリプトは保存しない
