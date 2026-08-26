---
name: distribute-spotify-liked-songs
description: Distribute Spotify Liked Songs into existing user-owned playlists using the local python-spotify-tools workflow, Obsidian playlist metadata, mutation guards, and post-write verification. Use when the user asks to classify, move, sort, or clean up Spotify favorites; do not use for browser-based Spotify control or for defining the playlist taxonomy itself.
---

# Spotify「お気に入り」の振り分け

Spotifyの「お気に入り」（Liked Songs）を、既存プレイリストへ安全に移動するためのシステム手順を扱う。音楽的趣向、具体的なプレイリスト名・説明・曲数・分類体系・容量規則・保護フォルダ方針は、このスキルに固定せずObsidianから取得する。

## Sources

- 操作ツール: `/Users/yuki/src/github.com/y-marui/python-spotify-tools`
- プレイリストの正本: `/Users/yuki/src/github.com/y-marui/obsidian-vault/idea_notes/spotify-playlists.md`
- ローカル保護設定: `~/.config/spotify-tools-groups.toml`

作業開始時にObsidianの正本を全文読み、Spotifyのライブ一覧と照合する。公式のObsidian MCPが利用可能なら既知のファイル名を指定してよい。公式と確認できないMCPは使わず、ローカルファイルを読む。

Spotifyの操作にブラウザUIやブラウザ自動化を使わない。OAuth認証ページをCLIがシステムブラウザで開く場合は、認証だけをユーザーに委ねる。実データの取得・編集は自作スクリプトとSpotify公式Web API経由に限定する。

## Boundaries

- 現在のプレイリストID、曲数、曲目、具体的な分類判断をスキルへ書き込まない。
- 会話メモリーをプレイリスト情報の正本にしない。永続化が必要な内容はObsidianへ反映する。
- Obsidianに記載された保護対象、将来対象、容量・命名規則を優先する。
- ユーザーが振り分けを依頼したことは、対象曲と既存の許可対象プレイリストを変更する権限を含むが、新規プレイリスト作成や分類体系変更までは含まない。

## Procedure

1. リポジトリのREADMEと利用可能なコマンドを確認する。調査・実作業では依存関係更新やコード変更を行わない。
2. 読み取り専用の `spotify-inventory` で、プレイリスト一覧、「お気に入り」の曲目、候補プレイリストの説明・曲数・既存曲目を取得する。
3. Obsidianの役割・分類・容量規則と、候補プレイリストの実際の収録傾向を照合して割り振り案を作る。趣向をスキルから推測しない。曖昧な曲は、必要に応じてアーティスト公式情報、楽曲紹介、歌詞、テンポ等を調べ、推測で断定しない。
4. 「お気に入り」の各URIが既存プレイリストに入っていないか全体照合する。既存曲は二重追加しない。
5. 書き込み前に `spotify-tools-groups.toml` を確認する。今回のソースと確定した追加先だけが変更可能になるよう、ライブ一覧から得た正確なIDで分類する。既存設定の無関係な項目は保持し、Obsidianの保護対象と未分類プレイリストは変更不可のままにする。
6. 既存の `split-playlist` を使い、追加先ごとに移動する。スクリプトの「追加成功後にソースから削除」の順序を維持する。CLIで足りる場合は独自の直接API処理を作らない。
7. 各バッチの成功を確認し、最後に読み取り専用で次を検証する。
   - 「お気に入り」の残数
   - 各予定曲が正しい追加先に存在すること
   - 欠落・二重追加がないこと
   - プレイリストの総曲数がObsidianの容量規則に適合すること
   - 保護対象のsnapshotや曲数に意図しない変化がないこと
8. 成功後、Obsidianの一覧・曲数をライブ状態に合わせて更新する。個別の振り分け履歴やプレイリスト固有情報を新しい会話メモリーへ保存しない。

## Failure Handling

- 追加後の削除失敗や通信中断では、同じ移動を無条件に再実行しない。追加先と「お気に入り」を読み直し、実際に完了した側を確定してから復旧する。
- 認証情報、OAuthキャッシュ、クライアントシークレットを出力・文書化しない。読み取り用と書き込み用のキャッシュを混同しない。
- スクリプトに必要な機能がなければ、リポジトリの `.github/` とIssueテンプレートを確認し、`y-marui/python-spotify-tools` に機能要望を作成して `y-marui` をassigneeにする。実装はSpotifyの実作業から切り離し、独立したコーディング用タスクで行う。
