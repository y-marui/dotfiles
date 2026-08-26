# Specification

コマンド一覧は [AI_CONTEXT.md](../AI_CONTEXT.md) の「よく使うコマンド」を参照。ここでは主要コマンドの動作定義のみを記す。

## Install / Link

- `make install` / `make links` はシンボリックリンクの作成のみを行う（べき等。既存のリンクが正しい参照先を指していれば何もしない）
- リンク先が dotfiles 管理外の実ファイルとして既に存在する場合は上書きしない（`make check` で検知）
- `make check` はリンク切れ・リンク先不一致・未リンクファイルを検出するが、修復はしない（`make links` を促す）
- macOSの`make install-macos`はリンク作成後に`dots check`監視用LaunchAgentを登録する
- Windows では `mingw32-make install` が `pwsh scripts/install.ps1` を呼び、PowerShell ネイティブでシンボリックリンク（`New-Item -ItemType SymbolicLink`）を作成する

## dots update

以下を順に実行する（失敗しても後続は継続し、最後にまとめて結果を報告する）:

1. dotfiles / dotfiles-private を fast-forward 更新
2. インストーラーでリンクを再適用し、macOSでは`dots check`監視用LaunchAgentを再登録
3. zprezto をサブモジュール込みで更新
4. OS 別パッケージマネージャー（Homebrew / winget）の更新

## dots check Monitor (macOS)

- `com.y-marui.dotfiles-check`をユーザーLaunchAgentとして、ログイン時と1時間ごとに実行する
- plistとrunnerはdotfiles内で管理し、`~/Library/LaunchAgents/`と`~/.local/bin/`へリンクする
- `make install-macos`と`dots update`が各Macで自動登録し、`make launchagent`で手動再登録できる
- `dots check`の結果は`~/.cache/dots/check-summary`へ原子的に保存する
- 警告内容のハッシュが変わった場合と、警告が解消した場合だけmacOS通知を出す
- zsh起動時はキャッシュを読み取るだけで、チェック処理を同期実行しない
- 自動修復は行わない。詳細確認と手動再実行には`dots check`を使う
- `make uninstall`は確認後にLaunchAgentを解除してから管理リンクを削除する

## dots {claude|codex|gemini} diff / apply / prune

MCP・plugin・skill の「宣言（dotfiles 内の設定ファイル）」と「実状態（各ツールの実際の設定）」を比較・同期する。

- `diff`: 差分のみ表示（変更なし）
- `apply`: 宣言済みだが未反映の項目を追加・更新する（宣言にない実状態の項目には触れない）
- `prune`: 未宣言かつ dotfiles 管理境界内の項目だけを削除・退避する（管理境界外のユーザー独自設定は対象外）

## dots ai diff / apply / prune

Claude Code、Codex、Gemini の順に、各エージェントの同じ操作を一括実行する。
`--mcp-only`、`--plugin-only`、`--skill-only` を指定した場合は、同じ限定オプションを
3エージェントすべてへ渡す。途中のエージェントで `apply` または `prune` が失敗した場合は
そこで終了し、後続エージェントは処理しない。

Copilot は user scope MCP のみを管理し、対応する対象種別とオプションが異なるため含めない。
個別の `dots {claude|codex|gemini}` コマンドは引き続き利用できる。

## sync-labpc

- ジョブ定義（`~/.config/labpc/jobs.d/<job-name>.conf`）に基づき、SMB共有からこのMacへ
  読み取り専用の一方向rsyncを行う（詳細は[_sync-labpc-lib.sh](../bin/unix/_sync-labpc-lib.sh)冒頭のコメントを参照）
- 既にFinder等でマウント済みの共有があればそれを再利用し、未マウントならこの関数が
  自前でマウントして処理後にアンマウントする（macOSのsmbfsは同一サーバー・共有・
  ユーザーの二重マウントを許可しないため）
- `SMB_USER`にスペース等のURL予約文字が含まれる場合（例: `PPMS-External PC`）は、
  `_labpc_url_encode`が自動的にパーセントエンコードしてから`mount_smbfs`のURLへ
  渡す。job conf側では生のアカウント名をそのまま書けばよい
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

## ghq-status

`bin/unix/ghq-status` の BRANCHES 列・DEV-CHARTER 列・keep-up-to-date 判定ロジックは [ghq-status](../bin/unix/ghq-status) 冒頭のコメントと [DEVELOPING.md](../DEVELOPING.md) を参照。
