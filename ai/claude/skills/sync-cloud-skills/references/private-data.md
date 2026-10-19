# Private Data: When Local and Cloud May Diverge

[Private Dataパターン](../../../../skills/README.md#private-data)を使うskillのうち、`scheduled_tasks`
が非空でcloud側の無人実行が必須なものは、本文中に実値を散らさず、ファイル末尾にまとめる。

- ローカル（`ai/skills/<name>/SKILL.md`、gitで公開管理）は `~/.identity/<name>.yaml` への
  参照文言のまま保つ。
- cloud側は、本文中でその参照文言が現れる箇所だけを「本SKILL末尾の『Private Data』節にある
  〜を使う」という趣旨の1文に置き換え、ファイル末尾に次の形式でセクションを追加する:

  ~~~markdown
  ## Private Data (cloud-only)

  このセクションはclaude.aiのcloud Skillにのみ存在する。dotfiles（公開リポジトリ）には
  反映しない — dotfiles側は `~/.identity/<name>.yaml` を読む設計のまま維持する。

  ```yaml
  <~/.identity/<name>.yaml と同じスキーマの実データ>
  ```
  ~~~

- cloud側のSkill本体はアカウント個人のプライベート設定でgitに乗らないため、実値を保持する
  ことを許容する。
- この形式なら、本文は（末尾セクションの有無と、参照文言1文を除いて）ローカルとcloudで
  同一に保てるため、次回同期時の差分比較で「意図した私有データ差分」と「本当の内容変更」を
  区別しやすい。
- cloud→localへ反映する場合（親の `SKILL.md` の「Reconcile per skill」4番）は、末尾の「Private Data (cloud-only)」
  節をローカル側にコピーせず、参照文言も `~/.identity/<name>.yaml` へ戻す。
