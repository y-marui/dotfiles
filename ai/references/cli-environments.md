# CLI Environment Procedures

`AI_CONTEXT_CLI.md` から、該当する作業時だけ参照する詳細手順。
共通規約の安全制約と commit・push の承認条件は引き続き適用する。

## Native App Verification

Swift/SwiftUI など Mac/iOS ネイティブアプリの変更を検証する際は、iOS Simulator の
操作ツールやスクリーンショットを使わない。ユーザー自身が実機・シミュレータで確認する。
`swift build` / `swift test` / `xcodebuild` やコンパイル・自動テストでの検証は問題ない。
UI 上の見た目確認が必要な場合は、その旨を伝えてユーザーに確認してもらう。

Alfred Workflow（`.alfredworkflow`）など、ダブルクリックで開く形式のネイティブ
macOS 成果物も同様に、実際の見た目・動作確認はユーザー自身が Alfred 上で行う。
成果物をビルドした後、`open <file>.alfredworkflow` で OS 標準のインポート
ダイアログを開くところまでは行ってよい（Finder でのダブルクリックと同義）。
オープンな PR 上で反復開発している場合は同じブランチで修正し、承認済みの範囲で
追いコミット・push と PR 本文更新を行う。再ビルド → `open` → ユーザーの再確認を繰り返す。

## iOS Simulator Moved to Device Hub

このマシンのXcodeには独立した`Simulator.app`が存在しない（`/Applications/Xcode.app/Contents/Developer/Applications/`自体がない）。シミュレータの画面は**「Device Hub」**という別アプリに統合されている（Xcodeメニューの `Open Developer Tool` → `Device Hub`、またはアプリ一覧から直接起動）。`xcrun simctl boot`/`install`/`launch` 等のCLIコマンド自体は従来どおり動作し、Device Hubを開けば起動済みのシミュレータ画面が表示される。`open -a Simulator`は失敗するので使わない。

## Warp Command Wrappers

Warp ターミナルで `ssh`・`make`・`diff` 等のラッパー由来のエラー
（例: `(eval):1: make: function definition file not found`）が発生した場合は、
`command ssh ...` / `command make ...` / `command diff ...` で回避する。
対象が安全ガードを持つ関数の場合は、その制約を維持できることを確認する。

## Zsh Word Splitting

zsh は既定で `sh_word_split` が無効なため、bash と異なりクォートなしの変数展開
（`for d in $repos; do ...`）はスペース区切りで単語分割されない。
`repos="a b c"` としても、変数全体が1つの値として渡り、ループは1回しか回らない。
複数の値は `for d in a b c; do ...` のようなリテラルか、
配列（`repos=(a b c); for d in "${repos[@]}"; do ...`）を使う。

## zsh Overwrite and noclobber

この環境の zsh は `noclobber` が有効で、`cat > file` や `echo > file` は既存ファイルの上書きに失敗する。
`>>` で存在しないファイルを新規作成する場合も失敗する。
ログ用ファイルへの `2>> log` や `2> log` のリダイレクトが失敗すると、コマンド自体が実行されず、ループが何もせずに終わることがある。
ログは先に `: >| file` で作ってから使う。
既存ファイルの更新は Write/Edit ツールで行い、シェルでは `>|` を使う。
失敗した heredoc 書き込みは、その後の処理が古い内容のまま進みやすいため、書き込み後に内容を確認する。

## zsh Interactive Prompts and Auto-ls

この環境の zsh には、Bash ツールの出力に影響する挙動が 4 つある。

- `cd` は、移動後に自動で `ls` を実行する（`dotfiles/shell/zshrc` の関数）。
  `cd` を含むコマンドの出力にディレクトリの一覧が混ざり、`grep` などの結果を読み違えやすい。
  ディレクトリを変えずに済む場合は `git -C <dir>` や絶対パスを使う
- `rm` は確認を求めることがあり（`remove <file>?`）、確認待ちのまま停止して、後続のコマンドを含む処理全体が止まる。
  非対話で削除する場合は、対象を確認したうえで `rm -f` を使う
- `cp` は `cp -i` のエイリアスで、既存ファイルの上書き時に確認を求める。
  非対話では `not overwritten` となり、終了コード 1 で上書きされない。
  `;` や改行で後続コマンドを続けると失敗を見落とし、バックアップ復元などで古い内容が残る。
  上書きが必要な場合は、対象を確認したうえで `command cp -f` を使う
- `log` は zsh の組み込みコマンドで、macOS の統合ログ（`/usr/bin/log`）を隠す。
  `log show` や `log stream` は `too many arguments` で失敗する。
  ログを見るときは `/usr/bin/log` とフルパスで呼ぶ
