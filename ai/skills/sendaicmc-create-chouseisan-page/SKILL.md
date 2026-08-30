---
name: sendaicmc-create-chouseisan-page
description: Create a new 仙台室内楽の会 practice attendance page on 調整さん from its Google Calendars. Use for monthly or explicitly requested multi-month attendance pages; do not use to add calendar bookings.
---

# Create Sendai Chamber Practice Page

仙台室内楽の会の練習予定を、調整さんの出欠表として作成する。通常は1か月につき1ページにし、ユーザーが明示した場合だけ複数月を1ページにまとめる。

## Read the schedule

1. Google Calendar の次の両方を、対象月の開始から翌月初日まで `Asia/Tokyo` で検索する。
   - `仙台室内楽の会 練習`: `4195f51b88a6d4542f79584ec53d39aaf6ebed1cf8cfac4c40e7947535bef928@group.calendar.google.com`
   - `仙台室内楽の会 練習 (ピアノなし)`: `8621676421379e707a6978a47e0a529f9139afb144fea1c1bd93a3315ab7b22c@group.calendar.google.com`
2. 候補は両カレンダーを合わせて開始日時順にする。通常練習は正確に `M/D (Ddd) H:mm-H:mm、施設名／部屋名`、ピアノなし練習は正確に `M/D (Ddd) H:mm-H:mm、施設名／部屋名 (ピアノなし)` とする。曜日は `Mon`–`Sun` の英語3文字、時刻は24時間表記・先頭ゼロなしを使う。Calendar のイベント名を施設名／部屋名として使い、会場住所や説明文は候補に入れない。
3. 対象の各月に予定がないこともそのまま扱う。新規作成前に、調整さんの `/user` と最近のイベント履歴を確認し、同じ対象月・同じ候補のページがあれば作成せずURLを報告する。

## Match the established page format

- 作成前に `https://chouseisan.com/` でログイン済みであることを確認する。未ログインなら、そのブラウザでログインをユーザーに依頼する。
- イベント名は `仙台室内楽の会 YY年M月`。複数月ページは `仙台室内楽の会 YY年M・N月` のように対象月を中黒でつなぐ。
- メモは次の案内文を使う。ページ間リンクを入れる場合は、最後の空行の後に `M月: https://chouseisan.com/s?...` の形式で追加する。既存ページの更新やリンクの相互追加は、ユーザーが明示した場合だけ行う。

~~~text
もしよければ、出席調査にご協力ください。
名前の後に楽器名をつけてください。

可能であれば合奏する曲を事前にアナウンスしたいと思っていて、
その際に参考にさせていただきたいです。

ある程度参加出来そうで合奏に参加する場合には◯にしてください。
参加したいが参加できるか半々な場合、合奏に参加しない場合は△としてください。
~~~

- 参加者欄は空のままにする。候補を直接入力する場合は、フォーム既定の時刻追記を無効にし、時刻が二重にならないようにする。

## Create and verify

1. 候補一覧、タイトル、メモ、重複確認結果を照合してからフォームを入力する。
2. 調整さんで出欠表を作成する最終操作は外部サービスの新規作成に当たるため、直前にユーザーへ確認する。
3. 作成後、表示されたページでタイトル・全候補・メモ・参加者0名を読み戻して検証し、URLを報告する。作成ページはユーザーが参照できるよう保持する。

## Safety

- 元のGoogle Calendarイベントを作成・更新・削除しない。
- 対象月またはCalendarの日時が曖昧なら推測せず確認する。
- 調整さんの既存イベントは、作成のためだけに編集・削除しない。
