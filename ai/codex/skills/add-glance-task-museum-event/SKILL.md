---
name: add-glance-task-museum-event
description: "Add a new exhibition task to Glance Task's 「美術展: 関東」 or 「美術展: 東北」 group through AppleScript, format its period and venue, and create it directly in unfinished-task position order with add task's optional after parameter. Use only for creating a new museum or art exhibition task; use format-glance-task-museum-events for existing-task formatting and order repair."
---

# Add a Glance Task Museum Event

Use the bundled CLI to create exactly one new exhibition through Glance Task's AppleScript commands. Treat `task position`, never `fetch tasks` array order, as display order.

## Collect the Event

- Resolve the target group to exactly `美術展: 関東` or `美術展: 東北`. Ask if the region is unclear.
- Require an exhibition title, start date, end date, and venue. Treat an omitted end date as a one-day event only when that is clearly intended.
- Do not invent a status emoji.
- Check for an exact-title duplicate. If one exists, do not add another task; hand the request to `$format-glance-task-museum-events` with the existing stable task ID.

## Format

Put the exhibition name in the title. Put exactly `<period> <venue>` in notes, using one ASCII space and two-digit month/day values.

```text
one day         YYYY/MM/DD 会場
same month      YYYY/MM/DD-DD 会場
same year       YYYY/MM/DD-MM/DD 会場
different years YYYY/MM/DD-YYYY/MM/DD 会場
```

Reject an end date before its start date. Ask when a date or venue is ambiguous.

## Add

Resolve the script relative to this `SKILL.md`. Run the preview first:

```bash
python3 <skill-dir>/scripts/museum_events.py add \
  --group "美術展: 関東" \
  --title "展示名" --start 2026/08/15 --end 2026/10/12 \
  --venue "根津美術館"
```

Review the canonical notes and desired order. If the user has authorized creation and the preview is unambiguous, apply the identical command with `--apply`:

```bash
python3 <skill-dir>/scripts/museum_events.py add \
  --group "美術展: 関東" \
  --title "展示名" --start 2026/08/15 --end 2026/10/12 \
  --venue "根津美術館" --apply
```

The CLI preflights every unfinished top-level task before writing. If existing notes are unparseable or the group is already out of position order, stop without creating the new task and use the formatting skill to repair it first.

## Position the Event

- Sort unfinished top-level tasks by end date, then start date, ascending.
- Preserve existing relative order for equal dates using `task position` as the tie-breaker, placing the new task after existing equal-date tasks.
- Determine the stable ID of the unfinished task immediately preceding the new event in desired order.
- Create once with `add task ... after <previous-task-id>`. Omit `after` when the new event belongs at the beginning.
- Do not call `reorder task` after creation. Fetch again and verify the complete unfinished order by lexically sorting `task position`.
- Leave completed tasks and subtasks unedited.
- Stop if `task position` is unavailable; never fall back to fetch order.

Report the created task ID, final title and notes, the preceding task ID or beginning placement, and the verified final position.
