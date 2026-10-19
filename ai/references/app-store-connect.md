# App Store Connect Procedures

`AI_CONTEXT_CLI.md` から、該当する作業時だけ参照する詳細手順。
共通規約の安全制約と commit・push の承認条件は引き続き適用する。

## App Store Connect Registration

新しいアプリの登録や、バージョンの提出準備で App Store Connect に入力するときは、
`~/.identity/app-store-connect.yaml`（dotfiles-private で管理）の値を使う。App Review の連絡先、
サポート窓口、著作権の表記、サポート・プライバシーポリシー URL の規則が入っている。
値は個人情報なので、ユーザーが依頼した App Store Connect の入力以外に使わず、チャットや
リポジトリに複写しない。ファイルがない、または値が足りない場合は、推測せずユーザーに確認する。
