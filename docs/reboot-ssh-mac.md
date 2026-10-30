---
description: FileVault を事前認証して SSH 接続中の Mac を再起動する手順と制約
---

# SSH 接続中の Mac の再起動

FileVault が有効な Mac では、通常の `reboot` 後にディスクの解除待ちになり、
通常の SSH に再接続できないことがある。代わりに接続先で `reboot-ssh-mac` を使う。

```bash
reboot-ssh-mac --check  # 状態確認のみ（sudo の認証が必要になる場合がある）
reboot-ssh-mac          # FileVault の認証後、直ちに再起動
```

接続元から直接呼ぶ場合は `ssh -t HOST reboot-ssh-mac` とする。
SSH ラッパーがある環境では `command ssh -t HOST reboot-ssh-mac` で直接接続できる。
sudo のパスワードと、fdesetup が要求する FileVault ユーザーの認証情報を端末で入力する。
SSH 鍵の認証だけでは FileVault の事前認証を代替できない。
コマンド自体はパスワードを引数・ファイル・環境変数に保存しない。

`fdesetup isactive` と `supportsauthrestart` が両方 `true` の場合のみ、
`sudo fdesetup authrestart -delayminutes 0` を実行する。
無効・非対応・確認エラー時は停止し、通常の `reboot` へのフォールバックはしない。
`--check` は認証の成功や再接続を保証しない。再起動の実行には対話端末が必要。

これは次の起動時だけの解除で、FileVault を無効化しない。
Apple の `man fdesetup` によると、認証付き再起動中は解除用キーを一時保持するため
FileVault の保護が低下する。停電や後日の通常起動にも適用される恒久設定ではない。
ネットワークや SSH サービスの復旧は別途必要で、初回は現地で復旧できる状況で確認する。

Apple silicon の macOS 26 以降では、Remote Login が有効でネットワーク接続がある場合、
再起動後に SSH で FileVault を解除できる機能もある。
接続に必要なネットワークの条件は環境ごとに確認する（OS 起動後の VPN 等は前提にできない）。
参照: [Apple Platform Security: Managing FileVault](https://support.apple.com/guide/security/sec8447f5049/web)。

既存の `reboot` は置き換えない。導入の取り消しは `reboot-ssh-mac` の使用をやめればよい。
