# Project Home: no mapping (exit code 3)

`3`（なし）の場合は、Step 1〜3の作業を終えたあとに`obsidian-project-home ensure --repo <repository-root>`を実行して作る（作業開始時の解決は読み取り専用のまま作らない）。作成が許されるのはresolver設定の`auto_create_owners`に挙げたオーナーのリポジトリだけで、それ以外は`ensure`が何も作らず終了コード`3`を返すので、そのまま「Project Homeなし」として報告する。作成できた場合は、出力されたパスの雛形（`（未記入）`の箇所）を、Step 2の基準でこのセッションの内容から埋める。`--description`には、リポジトリの目的を1行で渡してよい。`ensure`はcommitもpushもしない。
