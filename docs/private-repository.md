# dotfiles-private Repository

`dotfiles-private` は、公開できない設定データと宣言的なリンク対応表だけを保持する。
リンクの作成・検査・削除を含む実行ロジックは `dotfiles` が所有する。

## Creating a Repository

新規作成時は `dotfiles` の隣に安全な雛形を生成する。

~~~bash
make private-scaffold
~~~

標準の生成先は `../dotfiles-private`。別の場所で内容を確認する場合は次のように指定できる。

~~~bash
make private-scaffold PRIVATE_SCAFFOLD_DIR=/path/to/dotfiles-private
~~~

既存のパスは上書きしない。コマンドは `.example`、README、`.gitignore` をコピーし、
main ブランチの空の Git リポジトリを初期化する。生成直後は
`.dotfiles-private-scaffold` があり、`links.conf` は存在しないため、プレースホルダーが
ホームディレクトリへリンクされることはない。

既存の remote repository を取得する場合は、従来どおり `make private` を使う。

## Configuration Files

| Example | Configured path | Purpose |
|---|---|---|
| `links.conf.example` | `links.conf` | `platform\|source\|destination` のリンク対応表 |
| `gitconfig.d/includes.example` | `gitconfig.d/includes` | リポジトリパス別の Git include |
| `gitconfig.d/{private,public,overleaf}.example` | 同名から `.example` を除いたファイル | Git の user・URL 設定 |
| `gitconfig.d/local.example` | `gitconfig.d/local` | 任意のローカル専用 Git 設定。実ファイルは gitignore 対象 |
| `ssh/config.example` | `ssh/config` | 共通 SSH 設定 |
| `ssh/config.d/*.example` | 同名から `.example` を除いたファイル | OS 別 SSH 設定 |
| `identity/accounts.yaml.example` | `identity/accounts.yaml` | GitHub・著者名等の対応表。認証情報は保存しない |
| `macos/dockfile.example` | `macos/dockfile` | Dock・Finder sidebar の宣言 |
| `macos/menubarfile.example` | `macos/menubarfile` | メニューバーの宣言 |
| `labpc/jobs.d/job.conf.example` | `labpc/jobs.d/<job-name>.conf` | `sync-labpc` のジョブ設定 |

実設定を作成・編集し、リンク元がすべて存在することを確認してから、最後に次を行う。

~~~bash
cp links.conf.example links.conf
rm .dotfiles-private-scaffold
make -C ../dotfiles private-validate
make -C ../dotfiles links
~~~

`.example` は削除せず、安全な記入例として保持する。秘密情報、実在するホスト名・IP、
個人のメールアドレス、端末固有の絶対パスを `.example` に書かない。

## Structure Contract

正本は `templates/dotfiles-private/` と `templates/dotfiles-private.contract` にある。
`make private-validate` は次を検証する。

- private 側の `.example` が公開側の雛形と完全一致すること
- 有効化済みなら contract の必須ファイルと `labpc/jobs.d/*.conf` が存在すること
- `links.conf` が `links.conf.example` と一致すること
- private 側に `Makefile` や実行用 `.sh` / `.ps1` が残っていないこと

public 側の pre-commit でも同じ検証を常時実行する。ただし、同じ親ディレクトリに
Git リポジトリとしての `dotfiles-private` がない場合は成功扱いでスキップするため、
public repository 単独の cloud CI checkout では失敗しない。

構成を増やす場合は、public 側の `.example` と contract を先に更新し、private 側へ
同じ `.example` と実設定を追加する。リンク対象なら `links.conf.example` と
private 側の `links.conf` も同時に更新する。
