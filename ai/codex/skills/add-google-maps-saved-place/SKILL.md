---
name: add-google-maps-saved-place
description: Search Google Maps from place information supplied as text or an image, classify the result, and add it to the user's appropriate saved list. Use when the user asks to save, add, or register a restaurant, cafe, bar, scenic spot, attraction, or retail shop in Google Maps; route dining places to the regional 食べたい list or 食べたいけど夜のみ, and route scenic or retail places to 行ってみたい.
---

# Add a Google Maps Saved Place

Use the user's signed-in external browser state. Open a new tab, search with Google Maps account `authuser=2`, and add the verified place to exactly the intended list. After recording the result details, close a completed tab unless it must remain open for user handoff.

## Extract and verify the place

1. Read the place name and location from the supplied text or image. Use image understanding when the source is an image.
2. If the information does not uniquely identify a place, ask for the missing name, city, address, or branch before changing Google Maps.
3. Use the Chrome/browser-control skill because this workflow depends on the user's signed-in Google Maps state. Before browser work, check for a purpose-built Google Maps connector; use the browser when no connector can edit saved lists.
4. Create a new browser tab. Do not claim, reuse, or navigate an existing user tab.
5. Search in Google Maps with `authuser=2` explicitly present in the URL, for example `https://www.google.com/maps/search/<encoded query>?authuser=2`.
6. Verify the result against the supplied name and address or locality. Do not save a merely similar branch or namesake.

## Choose the destination list

First decide whether the place is a dining place or a scenic/retail place. Use the user's wording when explicit; otherwise use the verified Maps category, overview, hours, and official site if needed.

- Treat restaurants, cafes, bars, and other places primarily offering on-site food or drink as dining places.
- Treat scenic places, attractions, museums, parks, temples, shrines, viewpoints, and retail shops primarily selling goods as scenic/retail places. Save these to `行ってみたい`.
- Treat a food retailer without on-site dining as retail. Save it to `行ってみたい`.
- If the category remains genuinely ambiguous and would change the destination, ask the user before saving.

For a dining place, inspect the full weekly business hours before choosing a regional list:

- Save to `食べたいけど夜のみ` only when every day on which the business opens has no daytime service and every opening interval starts at 17:00 or later.
- If any day has an opening interval before 17:00, use the regional `食べたい` list.
- Ignore closed days when applying the every-open-day test.
- If weekly hours are missing, temporary, or too ambiguous to establish night-only operation, use the regional list unless the user explicitly identifies the place as night-only.

Choose the regional list from the verified address:

| List | Prefectures |
|---|---|
| `北海道の食べたい` | 北海道 |
| `東北の食べたい` | 青森、岩手、宮城、秋田、山形、福島 |
| `関東の食べたい` | 茨城、栃木、群馬、埼玉、千葉、東京、神奈川 |
| `中部の食べたい` | 新潟、富山、石川、福井、山梨、長野、岐阜、静岡、愛知 |
| `関西の食べたい` | 三重、滋賀、京都、大阪、兵庫、奈良、和歌山 |
| `中国の食べたい` | 鳥取、島根、岡山、広島、山口 |
| `四国の食べたい` | 徳島、香川、愛媛、高知 |
| `九州の食べたい` | 福岡、佐賀、長崎、熊本、大分、宮崎、鹿児島、沖縄 |

Do not infer a region from the user's current location or search viewport.

## Save without changing other lists

1. Open the place's `保存` or `保存済み` list picker.
2. Before inspecting the destination list, inspect the checked state of the exact system lists `スター付き` and `お気に入り` when present.
3. If either `スター付き` or `お気に入り` is checked, stop without changing any list. Report which of those lists already contains the place and that the requested save was skipped. Do not continue to the destination-list checks.
4. Locate the exact destination list name. Do not substitute a similarly named list.
5. If the exact destination list is absent, stop without changing anything. Never create a replacement list. Keep the new Maps tab open as a handoff and ask the user to confirm that Google Maps is showing the correct `authuser=2` account, naming the missing destination list in the message.
6. If more than one exact match appears, stop without changing anything and ask the user to verify the account and duplicate lists.
7. Inspect the checked state of the single exact destination list.
8. If the destination is already checked, make no change and report that it was already saved.
9. If it is unchecked, click only that destination list.
10. Never uncheck, toggle, or otherwise modify any other list, even if the place is already saved elsewhere.
11. Do not add a note, create a list, edit list metadata, or alter sharing.
12. Confirm success from the authoritative Maps alert or saved-place region naming the exact destination list.

## Close completed tabs and report

For each verified place, record these details before closing its tab:

- The exact place name shown by Google Maps.
- The full verified address shown by Google Maps.
- The Google Maps place-page URL. Use the current canonical place URL, not a search-results URL, and preserve `authuser=2` when present.
- The outcome and exact list name: newly added, already present in the destination list, or skipped because it was already in `スター付き` or `お気に入り`.

After success, an already-present destination result, or a skip caused by `スター付き` or `お気に入り`, make no further page interaction except recording the details above and closing the newly created tab. When processing multiple places, close every completed tab.

In the final response, report every place in a compact table or list containing the exact place name, full address, linked Google Maps place page, and outcome with the exact list name. Clearly distinguish `追加` from `登録済みのため変更なし` and `スター付き` or `お気に入り`によるスキップ.

If saving stops because the destination list is missing or duplicated, do not close that tab. Preserve it as a handoff, clearly state that no list was changed or created, include the same place name, address, and Google Maps link when available, and prompt the user to confirm the active Google Maps account before continuing.
