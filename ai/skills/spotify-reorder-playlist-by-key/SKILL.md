---
name: spotify-reorder-playlist-by-key
description: Reorder an existing Spotify playlist in-place into Camelot Wheel (harmonic-mixing) order using the installed python-spotify-tools `reorder-by-key` command, sourcing each track's Camelot key from the user since Spotify's public Web API no longer exposes track key data to new apps. Use when the user asks to sort/reorder/DJ-mix a playlist by musical key, Camelot code, or harmonic compatibility. Do not use for classifying or distributing Liked Songs (see spotify-distribute-liked-songs), and do not use browser automation or computer-use to control Spotify itself.
---

# Reorder Spotify Playlist by Key

Spotifyの既存プレイリストを、1曲目のキーを起点にCamelot Wheel(ハーモニックミキシング)順へin-placeで並べ替える。プレイリストの選択・具体的な曲順・キー値はこのスキルに固定せず、毎回ライブのSpotifyデータとユーザー提供のキー情報から組み立てる。

## Sources

- 操作ツール: PATH上の `spotify-inventory` / `reorder-by-key` コマンド（dotfiles の `pipxfile` により [y-marui/python-spotify-tools](https://github.com/y-marui/python-spotify-tools) から導入）
- キー情報: Spotify公式アプリの「Mix」機能(Premium限定)が表示するキー列。ユーザーにスクリーンショットで共有してもらう

## Background / Constraint

Spotify Web APIは2024-11-27以降、新規アプリからAudio Features(曲のキー・BPM等)エンドポイントへのアクセスを許可していない(Extended Quota Mode保持アプリのみ例外)。このため`reorder-by-key`はキーを自動取得できず、外部テキストファイルとして受け取る仕様になっている。この制約はSpotify側の意図的な仕様であり、回避しようとしない(下記Boundaries参照)。

## Boundaries

- キー情報の取得に、bot対策(CAPTCHA/Cloudflare等)のある外部サイト(Tunebat, songdata.io等)への自動アクセス・スクレイピングを行わない。bot検証の突破は明確に禁止行為。
- Spotifyデスクトップアプリをcomputer-use(OS操作)で直接操作しない。ポリシーでブロックされている。
- キー情報を、ジャンル・雰囲気・曲調からの推測で埋めない。ユーザーが提示した情報だけを使い、不足・不明な曲があれば質問する。
- 現在のプレイリストID・曲目・キー値・並べ替え結果をスキルへ書き込まない(会話ごとに変わるため)。
- 時計回り/反時計回りの選択は`reorder-by-key`が自動判定する。手動で決め打ちしない。

## Procedure

1. PATH上の`reorder-by-key --help`で、使い方(引数、キーファイル形式、`--yes`オプション)を確認する。
2. 読み取り専用の`spotify-inventory playlists`で対象プレイリストのIDを特定する。
3. 読み取り専用の`spotify-inventory tracks <playlist-id>`で現在の曲順・総曲数を取得する。これが以後のキー入力の基準順序になる。
4. ユーザーに、Spotify公式アプリで対象プレイリストの「Mix」機能を有効にしてキー列を表示し、全曲分をスクロールしながらスクリーンショットで共有してもらうよう依頼する。曲順と対応が取れるよう、手順3で取得した曲順・曲数と突き合わせる。
5. 受け取ったキー情報を、手順3の曲順と1対1で対応する1行1キーのテキストファイルに書き出す。曲数とキー行数が一致することを確認する。一致しない・読み取れない曲があれば、ユーザーに再確認する(推測で埋めない)。
6. `reorder-by-key <playlist-id> keys.txt`(引数なし、確認プロンプトあり)を実行して、選択された時計回り/反時計回りの方向と並べ替え後の順序プレビューを取得する。
7. プレビューをユーザーに提示する。曲数・キーの対応関係に不明点がなければ、承認を待たずに`--yes`付きで続けて適用する(in-placeで元の順序は失われるが、ユーザーから明示的な確認要求がない限り自動実行してよい)。曲数不一致・読み取れないキー・保護プレイリストへの抵触など不明点や懸念がある場合は、この時点で止めてユーザーに確認する。
8. コマンド末尾の検証結果(`Done` / `WARNING`)を確認する。`WARNING`の場合は再実行せず、`spotify-inventory tracks`でライブの状態を読み直してから対応する。
9. 完了後、最終順序をユーザーに報告する。個別の曲目・キー値・並べ替え結果を新しい会話メモリーへ保存しない。

## Failure Handling

- キー取得元サイトがbot対策で止まった場合、別サイトへの自動アクセスを次々試さない。ユーザーへスクリーンショット提供を依頼する経路に切り替える。
- 必要なコマンドがPATHにない場合は処理を始めず、`python-spotify-tools` の導入をユーザーに依頼する。ローカルcheckoutの探索や、別の実装への置き換えはしない。
- `reorder-by-key`実行後に`WARNING`が出た場合、同じ並べ替えを無条件に再実行しない。ライブの曲順を読み直し、実際の状態を確認してから復旧方針を決める。
- 認証情報(`.env`、OAuthキャッシュ)を出力・文書化しない。
- コマンドに必要な機能がなければ、`y-marui/python-spotify-tools`にIssueを作成し`y-marui`をassigneeにする。実装はSpotifyの実作業から切り離し、独立したコーディング用タスクで行う。
