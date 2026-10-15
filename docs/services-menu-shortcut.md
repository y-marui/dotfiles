# Services Menu Shortcut

macOSの前面アプリで「サービス」の一覧を開く。キーは
**Control + Option + S**（`⌃⌥S`）。押して離すと一覧を表示し、
矢印キーで選び、Returnで実行、Escapeで閉じる。

## Setup

1. Karabiner-Elementsを起動し、通常のキーボード入力に必要な権限を設定する。
2. `make links`を実行する。共有プロファイルにはルールが有効な状態で含まれる。
   独自プロファイルを使う場合はComplex Modificationsから
   `Open Services menu (Control+Option+S)`を追加する。
3. `dots shortcuts apply --no-prune`でdotfiles-privateのメニュー表示用設定も適用する。
4. 最初の実行でmacOSが求めるSystem Eventsのオートメーション権限と、実行元の
   アクセシビリティ権限を許可する。権限は各Macで必要で、dotfilesでは共有しない。
5. Finder等で`⌃⌥S`を押してすべて離し、一覧が開いた状態を保つか確認する。
   メニューのキー表示は対象アプリを終了・再起動して確認する。

## Implementation

- `karabiner/complex_modifications/services-menu.json`: インポート用ルール。
- `karabiner/karabiner.json`: 共有Default profileの有効ルール。
- `karabiner/open-services.applescript`: 前面アプリのアプリ名メニューから、
  `サービス`または`Services`を選択し、右矢印でサブメニューを展開する。
- `scripts/_links.sh`: 上記ファイルを`~/.config/karabiner/`へリンクする。
- dotfiles-privateの`macos/keyboard-shortcuts.plist`: 両方のタイトルへ`^~s`を割り当てる。

KarabinerはSのキーを離したときにAppleScriptを実行する。修飾キーもすべて離す。
新しい常駐アプリは追加しない。macOSのサービス一覧は、選択中のテキストやファイルに
応じて変わる。標準メニューバーを持たないアプリや日本語・英語以外のメニューは対象外。

メニューのショートカット表示はアプリ側の対応に依存する。
`NSUserKeyEquivalents`の指定だけでサブメニューを開けるとは保証せず、開く処理は
Karabinerが受け持つ。構文・設定整合性の検証と実機操作の確認は別であり、
初回導入時には上記手順で実機確認する。

2026-10-15にユーザーが、このMacで`⌃⌥S`からサービス一覧を開けることを確認した。
メニュー内のキー表示と他のMacでの動作は別途確認する。

## Change or Remove the Shortcut

キーを変える場合は、インポート用と有効ルールの`from.modifiers`・`from.key_code`・
`description`、privateの両メニュータイトルの値、および本文のキー表記を揃える。
KarabinerのルールはShiftなど追加修飾キーの付いた入力にはマッチしない。

無効化する場合はKarabinerのComplex Modificationsで該当ルールを削除する。
表示用設定も不要ならprivateの両エントリを除去し、`dots shortcuts apply`を実行する。
同コマンドは他の未管理ショートカットも削除するため、先に`--dry-run`で対象を確認する。
Karabinerが設定ファイルのリンクを置換した場合は`make links`で再リンクする。

## References

- [Karabiner: shell_command](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/to/shell-command/)
- [Apple: App shortcuts](https://support.apple.com/guide/mac-help/mchlp2271/mac)
