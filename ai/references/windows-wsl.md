# Windows and WSL Procedures

`AI_CONTEXT_CLI.md` から、該当する作業時だけ参照する詳細手順。
共通規約の安全制約と commit・push の承認条件は引き続き適用する。

## Empty stdin to `python -` on Windows

Windows の Git Bash 等で、標準入力が空のまま `python -` / `python3 -`（本文が空の heredoc、
`</dev/null` を含む）を実行しない。Windows は NUL を端末とみなすため、Python 3.14 が REPL
を起動し、非 tty でエラーを無限に出力して終了しない。バックグラウンドに回されたタスクの出力は
上限がなく、数百 GB に膨らんで C: を埋め、WSL を入出力エラーにした実績がある。スクリプトは
ファイルに置くか `python -c` で渡す。`PYTHON_BASIC_REPL=1` を設定すると、空入力でも正常終了する。
バックグラウンドに回ったコマンドが止まらないときは、`%TEMP%\claude\...\tasks\*.output` の
サイズを確認して停止する。

## Inline Scripts to `wsl.exe` from Git Bash

Git Bash から `wsl.exe -d <distro> -- bash -lc '...'` に渡した文字列は、WSL 側の前段シェルで
`$VAR`・`$1`・`$(...)` が先に展開されて空になる（単一引用符で囲んでも同じ）。変数や
コマンド置換を使った処理が、エラーを出さずに空文字で進み、`backup-.db` のような
名前のファイルができた実績がある。また `/mnt/c/...` のような絶対パスの引数は MSYS の
パス変換で `C:/Program Files/Git/mnt/...` に書き換わる。変数・コマンド置換・複数行を含む
処理はスクリプトファイルに書き、`MSYS_NO_PATHCONV=1 wsl.exe -d <distro> -u root -- bash <script>`
で実行する。Windows 側のリポジトリは root から見ると所有者が違うため、WSL 内の
`git rev-parse` は空を返すことがある。その値は Windows 側で取得して渡す。

## Running Commands in WSL over SSH from the Mac

Mac から `ssh <windows-host>` で入った Windows の既定シェルは PowerShell なので、`uname` などの
Unix コマンドは使えない。WSL の中の処理は `wsl.exe -d <distro> -- bash -c "..."` で実行するが、
ssh・PowerShell・`wsl.exe`・`bash` と引用符が重なるため、`$`・引用符・Docker の `{{...}}` が
壊れる。スクリプトは Mac 側で base64 にして渡す（base64 には空白も記号もないので、引用符が崩れない）。

~~~sh
b=$(base64 </tmp/script.sh | tr -d '\n')
ssh <windows-host> "wsl.exe -d <distro> -- bash -c \"echo $b | base64 -d | bash\""
~~~

- 出力に `your 131072x1 screen size is bogus. expect trouble` が混ざるが無害。`grep -v` で除く
- 既定ユーザーが root の distro では `~` は `/root`。処理は何のユーザーで動くかを先に確認する
- スクリプトに秘密情報を埋め込まない。トークンなどはファイルで渡し、値は出力しない
- 待ち時間の長い処理（数十秒以上のループなど）は、出力が途中で切れたことがあった。分割して実行し、
  切れたら状態（`docker ps` など）を確認し直す。「出力がない」を「失敗」と決めつけない
