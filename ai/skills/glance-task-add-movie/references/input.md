# Movie Input

一時JSONを`upsert --input <path>`へ渡す。文字列をシェルへ直接補間しない。
すべての情報は取得した参照先に基づく。次は架空の入力例。

```json
{
  "title": "作品名",
  "year": 2026,
  "filmarks_url": "https://filmarks.com/movies/123456",
  "release_date": "2026-10-16",
  "official_url": "https://example.com/movie",
  "checked_on": "2026-10-16",
  "screenings": [
    {
      "cinema": "フォーラム仙台",
      "start": "2026-10-23",
      "end": "2026-11-05",
      "end_status": "planned",
      "url": "https://example.com/cinema/movie"
    }
  ]
}
```

- `title`、`checked_on`は必須。製作年は`year`、国内公開日は`release_date`。
- `filmarks_url`が取得できなければ省略可。その場合は同定済みの`year`が必須で、邦題＋製作年を識別子に使う。
  既存のFilmarks IDがある場合は同じIDを再利用する。
- 日付は`YYYY-MM-DD`。不明は`null`または省略。日付不明を今日の日付で埋めない。
- `screenings`は確認できた3館のみ。`cinema`は`TOHO仙台`、`MOVIX仙台`、`フォーラム仙台`。
  各館は1回。`url`は劇場の日程の出典。上映中でも開始日不明なら`start: null`。
- `end_status`は`confirmed`（確定）、`planned`（予定）、`unknown`（未定）。
  `end`があるなら確定／予定、ないなら未定を指定する。
- 3館の上映未確認なら`screenings: []`。その場合は作品公式などの`official_url`を必須にし、
  国内公開日を並び順へ代用する。公開日も不明なら日付不明として末尾に置く。
- タイトルは`作品名 (10/23〜)`。メモは年を含む日付・映画館・出典・確認日と、
  重複確認とソート用の`cinema-data`を保存する。`cinema-data`は手で書き換えない。
- 並び順と重複確認は「映画」グループ内だけに限定し、鑑賞履歴として推薦へ転用しない。

`list --group <ID>`は読取のみ。`upsert`も`--apply`なしでは書き込まない。
