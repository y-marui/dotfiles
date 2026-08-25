# Karabiner-Elements: Windows App (RDP) JIS キー設定

Mac (JIS 配列) から Windows App (旧 Microsoft Remote Desktop) 経由で Windows PC に
接続する際、記号ズレと IME 切り替えを解消するための設定と経緯。

## Managed Files

| リポジトリ内 | リンク先 | 内容 |
|---|---|---|
| `karabiner/karabiner.json` | `~/.config/karabiner/karabiner.json` | Karabiner-Elements 本体設定（プロファイル・有効ルール） |
| `karabiner/complex_modifications/rdp-jis.json` | `~/.config/karabiner/assets/complex_modifications/rdp-jis.json` | Complex Modifications のルール定義（Add rule で選択する候補） |

`karabiner.json` は Karabiner-Elements が Preferences 保存やデバイス接続のたびに
atomic rename で書き換える。シンボリックリンクが実ファイルに置き換わり dotfiles との
同期が切れることがあるため、`karabiner.json` の内容が古いと感じたら
[`make check`](../AI_CONTEXT.md) で確認し、`make links` で再リンクする。

## Environment

- クライアント: macOS / Windows App (旧 Microsoft Remote Desktop)
- Bundle ID: `com.microsoft.rdc.macos`
- キーボードモード: **Scancode**（既定。Unicode モードは変換動作が不安定なため不採用）
- 接続先: 自宅/社内の Windows PC
- Mac 側キーボード: JIS 配列

## Symptom and Cause

| 症状 | 原因 |
|---|---|
| `` ` `` を打つと `{` が入る | Windows 側が US 101 レイアウトとして解釈。JIS の `@` 位置が US の `[` になるため |
| 英数/かなキーで IME が切り替わらない | 無変換/変換キーが Windows に到達しない（下記「`not_to` について」参照） |

## Fix 1: Switch the Windows-Side Layout to 106 (Resolves Symbol Mismatch)

`enable-jis106.reg` を適用し、**Windows を再起動**する。
レジストリはキーボードドライバのロード時にしか読まれないため、再起動しないと反映されない。

```
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Keyboard Layouts\00000411
  Layout File = kbd106.dll
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\i8042prt\Parameters
  LayerDriver JPN            = kbd106.dll
  OverrideKeyboardIdentifier = PCAT_106KEY
  OverrideKeyboardSubtype    = 2 (dword)
  OverrideKeyboardType       = 7 (dword)
```

適用前に regedit の「ファイル > エクスポート」でバックアップを取る。
影響範囲はこの Windows 機のキーボードレイアウト全体（ローカル利用時も含む）。
確認: `` ` ``（Shift+@）が正しく入力されれば成功。

## Fix 2: IME Switching (Karabiner-Elements)

### Adopted Approach: Send the Hankaku/Zenkaku Key

`karabiner/complex_modifications/rdp-jis.json`（Complex Modifications）を有効化する。
英数/かな → `grave_accent_and_tilde`（HID 0x35）に変換。
Windows JIS 106 ではこれが半角/全角キー（scancode 0x29）にあたる。

- 動作: IME オン/オフのトグル
- Windows 側の追加設定は不要
- `frontmost_application_if` で Windows App 内に限定しているため、他アプリでは通常どおり英数/かなが機能する

### Rejected Approaches and Why

| 案 | 理由 |
|---|---|
| Unicode モード | 日本語変換が不安定 |
| 英数/かな → 無変換/変換 | Windows 側に到達しない（`not_to` 参照） |

### About `not_to`

Karabiner の `simple_modifications.json` には一部キーに `"not_to": true` が付く。

| キー | `not_to` | 到達実績 |
|---|---|---|
| `international4` | あり | 届かない |
| `international5` | あり | 届かない |
| `japanese_pc_nfer`（無変換） | あり | 届かない |
| `japanese_pc_xfer`（変換） | あり | 届かない |
| `grave_accent_and_tilde`（半角/全角） | なし | 届く |
| `f13` 〜 `f20` | なし | 届く見込み |

`not_to` の有無と到達実績が一致するため、Karabiner が `to` として送出していないと考えられる。
ただし `simple_modifications.json` は Simple Modifications の UI 用リストであり、
UI 表示フィルタにすぎない可能性も理屈上は残る。断定するには EventViewer での確認が必要。
実務上は **`not_to` のないキーを選べばよい**。

## Unresolved / Future Options

半角/全角はトグル動作のため、「英数=必ずオフ / かな=必ずオン」という明示切り替えにはならない。
明示切り替えが必要な場合:

1. Karabiner で 英数 → `f13`、かな → `f14` に変換（`rdp-jis.json` 内の
   「英数 → F13 / かな → F14」ルールで到達確認済み）
2. Windows に Google 日本語入力を導入
3. キー設定エディタで割り当て

| モード | 入力キー | コマンド |
|---|---|---|
| 直接入力 | F14 | IME を有効化 |
| 入力文字なし | F13 | IME を無効化 |
| 変換前入力中 | F13 | IME を無効化 |
| 変換中 | F13 | IME を無効化 |

Microsoft IME 標準の「キーとタッチのカスタマイズ」では F13 を割り当てられないため、
Google 日本語入力（またはキー設定を自由に編集できる IME）が必要。

## Karabiner JSON Format Differences

| 用途 | トップレベル構造 |
|---|---|
| `Add your own rule` に貼り付け | `description` + `manipulators` |
| `~/.config/karabiner/assets/complex_modifications/` に配置 | `title` + `rules: [...]` |

混同すると `manipulators is missing or empty` エラーになる。
このエラーはキーコードとは無関係で、階層の問題のみが原因。

## Diagnostic Steps (If It Recurs)

1. Windows App 内でブラウザを開き keycode.info でキーの到達を確認
2. Karabiner の EventViewer で Mac 側の送出を確認
3. 両方確認することで「送っていない」か「受け取れていない」かを切り分ける
