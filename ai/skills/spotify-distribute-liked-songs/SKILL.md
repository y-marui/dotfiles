---
name: spotify-distribute-liked-songs
description: Distribute Spotify Liked Songs into existing user-owned playlists using the installed python-spotify-tools commands, Obsidian playlist metadata, mutation guards, and post-write verification. Use when the user asks to classify, move, sort, or clean up Spotify favorites; do not use for browser-based Spotify control or for defining the playlist taxonomy itself.
---

# Distribute Spotify Liked Songs

Spotifyの「お気に入り」（Liked Songs）を既存プレイリストへ安全に移動するための手順を扱う。音楽的趣向、具体的なプレイリスト名・説明・曲数・分類体系・容量規則・保護フォルダ方針は、このskillに固定せずObsidianから取得する。

## Sources

- 操作ツール: PATH上の `spotify-inventory` / `split-playlist` コマンド（dotfiles の `pipxfile` により [y-marui/python-spotify-tools](https://github.com/y-marui/python-spotify-tools) から導入）
- プレイリストの正本: `$OBSIDIAN_ROOT/idea_notes/spotify-playlists.md`（`$HOME/.ai/zsh_path.local` から解決）

作業開始時に通常のシェル初期化を読まず `zsh -f` で `$HOME/.ai/zsh_path.local` だけを source し、`OBSIDIAN_ROOT` を解決する。設定ファイル・変数・上記の正本のいずれかが存在しないまたは読めない場合は作業を開始せず、欠けている項目を示してユーザーに修正を求める。同名ファイルの探索はしない。解決後にObsidianの正本を全文読み、Spotifyのライブ一覧と照合する。公式のObsidian MCPが利用可能なら既知のファイル名を指定してよい。公式と確認できないMCPは使わず、ローカルファイルを読む。

Spotifyの操作にブラウザUIやブラウザ自動化を使わない。OAuth認証ページをCLIがシステムブラウザで開く場合は、認証だけをユーザーに委ねる。実データの取得・編集は自作スクリプトとSpotify公式Web API経由に限定する。

## Boundaries

- 現在のプレイリストID、曲数、曲目、具体的な分類判断をスキルへ書き込まない。
- 会話メモリーをプレイリスト情報の正本にしない。永続化が必要な内容はObsidianへ反映する。
- Obsidianに記載された保護対象、将来対象、容量・命名規則を優先する。
- ユーザーが振り分けを依頼したことは、対象曲と既存の許可対象プレイリストを変更する権限を含むが、新規プレイリスト作成や分類体系変更までは含まない。

## Procedure

1. PATH上の `spotify-inventory` と `split-playlist` を確認し、引数を受ける `spotify-inventory` の `--help` を確認する。`split-playlist` は対話式で `--help` を受けないため、確認だけの起動はしない。調査・実作業では依存関係更新やコード変更を行わない。
2. 読み取り専用の `spotify-inventory` で、プレイリスト一覧、「お気に入り」の曲目、候補プレイリストの説明・曲数・既存曲目を取得する。
3. Obsidianの役割・分類・容量規則と、候補プレイリストの実際の収録傾向を照合して割り振り案を作る。趣向をスキルから推測しない。曖昧な曲は、必要に応じてアーティスト公式情報、楽曲紹介、歌詞、テンポ等を調べ、推測で断定しない。
4. 「お気に入り」の各URIが既存プレイリストに入っていないか全体照合する。既存曲は二重追加しない。
5. 既存の `split-playlist` を使い、追加先ごとに移動する。スクリプトの「追加成功後にソースから削除」の順序を維持する。CLIで足りる場合は独自の直接API処理を作らない。
6. 各バッチの成功を確認し、最後に読み取り専用で次を検証する。
   - 「お気に入り」の残数
   - 各予定曲が正しい追加先に存在すること
   - 欠落・二重追加がないこと
   - プレイリストの総曲数がObsidianの容量規則に適合すること
   - 保護対象のsnapshotや曲数に意図しない変化がないこと
7. 成功後、Obsidianの一覧・曲数をライブ状態に合わせて更新する。個別の振り分け履歴やプレイリスト固有情報を新しい会話メモリーへ保存しない。

## Failure Handling

- 追加後の削除失敗や通信中断では、同じ移動を無条件に再実行しない。追加先と「お気に入り」を読み直し、実際に完了した側を確定してから復旧する。
- 必要なコマンドがPATHにない場合は処理を始めず、`python-spotify-tools` の導入をユーザーに依頼する。ローカルcheckoutの探索や、別の実装への置き換えはしない。
- 認証情報、OAuthキャッシュ、クライアントシークレットを出力・文書化しない。読み取り用と書き込み用のキャッシュを混同しない。
- スクリプトに必要な機能がなければ、リポジトリの `.github/` とIssueテンプレートを確認し、`y-marui/python-spotify-tools` に機能要望を作成して `y-marui` をassigneeにする。実装はSpotifyの実作業から切り離し、独立したコーディング用タスクで行う。
