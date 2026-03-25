@~/.ai/AI_CONTEXT.md
@~/.ai/AI_CONTEXT_CLI.md

## ビルド・テストコマンドの実行

ビルド・テスト・lint・pre-commit など出力が多いコマンドは `run-quiet` でラップして実行する。
エラーがなければ1行サマリーのみ出力され、コンテキストを節約できる。
warning/deprecated/note 行は自動的に抜粋表示される。

```sh
run-quiet make build
run-quiet swift build
run-quiet npm test
run-quiet pre-commit run --all-files
run-quiet git commit -m "..."
```

warning やエラーの情報が不足していて原因を特定できない場合は、
`run-quiet` を外してフル出力で再実行することをユーザーに提案する。

```sh
# フル出力で再実行
pre-commit run --all-files
make build
```
