#!/usr/bin/env python3
"""Preview and upsert movie tasks in Glance Task without assigning deadlines."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import asdict, dataclass, replace
from datetime import date
from pathlib import Path
from urllib.parse import urlsplit

GROUP = "映画"
CINEMAS = ("TOHO仙台", "MOVIX仙台", "フォーラム仙台")
MARKER = "[cinema-movie:v1]"
RS, FS = "\x1e", "\x1f"


class MovieError(RuntimeError):
    """Invalid input, ambiguous identity, or incomplete application operation."""


@dataclass(frozen=True)
class Task:
    task_id: str
    title: str
    notes: str
    completed: bool
    parent_id: str
    position: str
    has_deadline: bool = False


FETCH_TASKS_SCRIPT = r"""
using terms from application "/Applications/Glance Task.app"
on run argv
    if (count of argv) is not 1 then error "Expected one task group argument."
    set groupIdentifier to item 1 of argv
    tell application "/Applications/Glance Task.app"
        set fetchedTasks to fetch tasks from group groupIdentifier
    end tell

    set outputRows to {}
    repeat with taskReference in fetchedTasks
        set currentTask to contents of taskReference
        set notesText to task notes of currentTask
        if notesText is missing value then set notesText to ""
        set parentText to parent task id of currentTask
        if parentText is missing value then set parentText to ""
        set positionText to task position of currentTask
        if positionText is missing value then set positionText to ""
        set fieldValues to {(task id of currentTask), (task title of currentTask), notesText, ((task completed of currentTask) as text), parentText, positionText, (((task deadline of currentTask) is not missing value) as text)}
        repeat with fieldValue in fieldValues
            if (fieldValue as text) contains (character id 30) or (fieldValue as text) contains (character id 31) then error "A task field contains an unsupported control separator."
        end repeat
        set text item delimiters to character id 31
        set end of outputRows to fieldValues as text
    end repeat
    set text item delimiters to character id 30
    return outputRows as text
end run
end using terms from
"""

ADD_TASK_SCRIPT = r"""
using terms from application "/Applications/Glance Task.app"
on run argv
    if (count of argv) is not 4 then error "Expected group, title, notes, and previous task ID arguments."
    set groupIdentifier to item 1 of argv
    set titleText to item 2 of argv
    set notesText to item 3 of argv
    set previousTaskID to item 4 of argv
    tell application "/Applications/Glance Task.app"
        if previousTaskID is "" then
            return add task titleText to groupIdentifier notes notesText
        else
            return add task titleText to groupIdentifier notes notesText after previousTaskID
        end if
    end tell
end run
end using terms from
"""

UPDATE_TASK_SCRIPT = r"""
using terms from application "/Applications/Glance Task.app"
on run argv
    if (count of argv) is not 4 then error "Expected group, task ID, title, and notes arguments."
    set groupIdentifier to item 1 of argv
    set targetTaskID to item 2 of argv
    set titleText to item 3 of argv
    set notesText to item 4 of argv
    tell application "/Applications/Glance Task.app"
        update task targetTaskID in group groupIdentifier title titleText notes notesText deadline missing value
    end tell
    return targetTaskID
end run
end using terms from
"""

REORDER_TASK_SCRIPT = r"""
using terms from application "/Applications/Glance Task.app"
on run argv
    if (count of argv) is not 3 then error "Expected group, task ID, and previous task ID arguments."
    set groupIdentifier to item 1 of argv
    set targetTaskID to item 2 of argv
    set previousTaskID to item 3 of argv
    tell application "/Applications/Glance Task.app"
        if previousTaskID is "" then
            reorder task targetTaskID in group groupIdentifier after missing value
        else
            reorder task targetTaskID in group groupIdentifier after previousTaskID
        end if
    end tell
    return targetTaskID
end run
end using terms from
"""


def text(value, label):
    if not isinstance(value, str) or not value.strip():
        raise MovieError(f"{label} must be nonempty text")
    value = value.strip()
    if any(ord(c) < 32 for c in value):
        raise MovieError(f"{label} must be a single line without control characters")
    return value


def day(value):
    if value is None:
        return None
    try:
        if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
            raise ValueError
        return date.fromisoformat(value)
    except ValueError as exc:
        raise MovieError(f"Invalid ISO date: {value!r}") from exc


def url(value):
    value = text(value, "URL")
    parsed = urlsplit(value)
    if parsed.scheme not in {"https", "http"} or not parsed.netloc or parsed.username:
        raise MovieError(f"Expected a public HTTP(S) URL: {value}")
    return value


def movie_data(data):
    if not isinstance(data, dict):
        raise MovieError("Movie input must be an object")
    title = text(data.get("title"), "title")
    year = data.get("year")
    if year is not None and (type(year) is not int or not 1880 <= year <= 2200):
        raise MovieError("year must be a four-digit production year")
    filmarks = data.get("filmarks_url")
    if filmarks:
        filmarks = url(filmarks)
        parsed = urlsplit(filmarks)
        if parsed.hostname != "filmarks.com" or not re.fullmatch(
            r"/movies/\d+/?", parsed.path
        ):
            raise MovieError("filmarks_url must identify one Filmarks movie")
        identity = "filmarks:" + parsed.path.strip("/").split("/")[-1]
        filmarks = "https://filmarks.com" + parsed.path.rstrip("/")
    else:
        if year is None:
            raise MovieError("Supply filmarks_url or a verified production year")
        identity = f"title:{title}:{year}"
    release = day(data.get("release_date"))
    checked = day(data.get("checked_on"))
    if checked is None:
        raise MovieError("checked_on is required")
    screenings = data.get("screenings", [])
    if not isinstance(screenings, list):
        raise MovieError("screenings must be an array")
    rows, seen = [], set()
    for item in screenings:
        if not isinstance(item, dict) or item.get("cinema") not in CINEMAS:
            raise MovieError("Unknown cinema in screenings")
        cinema = item["cinema"]
        if cinema in seen:
            raise MovieError(f"Duplicate cinema: {cinema}")
        seen.add(cinema)
        start, end = day(item.get("start")), day(item.get("end"))
        status = item.get("end_status", "unknown")
        if status not in {"confirmed", "planned", "unknown"}:
            raise MovieError("end_status must be confirmed, planned, or unknown")
        if (end is None) != (status == "unknown"):
            raise MovieError(
                "An end date needs confirmed/planned status; no end needs unknown"
            )
        if start and end and end < start:
            raise MovieError("Screening end precedes start")
        rows.append(
            {
                "cinema": cinema,
                "start": start.isoformat() if start else None,
                "end": end.isoformat() if end else None,
                "end_status": status,
                "url": url(item.get("url")),
            }
        )
    rows.sort(key=lambda row: CINEMAS.index(row["cinema"]))
    starts = [day(row["start"]) for row in rows if row["start"]]
    # A confirmed local screening with an unknown start must not silently use national release.
    start = min(starts) if starts else (None if rows else release)
    basis = "仙台3館" if rows else ("国内公開" if release else "未定")
    official = url(data["official_url"]) if data.get("official_url") else None
    if not official and not rows:
        raise MovieError(
            "official_url is required when local screenings are unconfirmed"
        )
    metadata = {
        "id": identity,
        "title": title,
        "year": year,
        "start": start.isoformat() if start else None,
        "basis": basis,
        "release_date": release.isoformat() if release else None,
        "filmarks_url": filmarks,
        "official_url": official,
        "checked_on": checked.isoformat(),
        "screenings": rows,
    }
    return metadata


def render(movie):
    start = day(movie["start"])
    title = movie["title"] + (f" ({start.month}/{start.day:02d}〜)" if start else "")
    lines = [
        MARKER,
        f"上映開始: {movie['start'] or '未定'} ({movie['basis']})",
        f"国内公開日: {movie['release_date'] or '未定'}",
    ]
    if not movie["screenings"]:
        lines.append("仙台3館の上映: 未確認")
    for row in movie["screenings"]:
        end = row["end"] or "終了日未定"
        if row["end_status"] == "planned":
            end += "予定"
        lines.extend(
            [f"{row['cinema']}: {row['start'] or '開始日未確認'}〜{end}", row["url"]]
        )
    if movie["filmarks_url"]:
        lines.append(movie["filmarks_url"])
    if movie["official_url"]:
        lines.append(movie["official_url"])
    lines.extend(
        [
            f"確認日: {movie['checked_on']}",
            "cinema-data: "
            + json.dumps(movie, ensure_ascii=False, separators=(",", ":")),
        ]
    )
    return title, "\n".join(lines)


def stored(task):
    lines = task.notes.splitlines()
    if not lines or lines[0] != MARKER:
        return None
    entries = [
        line[len("cinema-data: ") :]
        for line in lines
        if line.startswith("cinema-data: ")
    ]
    try:
        if len(entries) != 1:
            raise ValueError("missing or duplicated cinema-data")
        data = json.loads(entries[0])
        canonical = movie_data(data)
        if data != canonical:
            raise ValueError("inconsistent movie metadata")
        return canonical
    except (ValueError, KeyError, TypeError, MovieError) as exc:
        raise MovieError(
            f"Invalid stored movie metadata for task {task.task_id}: {exc}"
        ) from exc


def ordered(tasks):
    top = [t for t in tasks if not t.completed and not t.parent_id]
    if any(not t.position for t in top):
        raise MovieError("Missing task position; cannot infer order from fetch order")
    return sorted(top, key=lambda t: (t.position, t.task_id))


def sorted_tasks(tasks):
    current = ordered(tasks)
    keys = {}
    for task in current:
        data = stored(task)
        if data is None:
            raise MovieError(
                f"Unmanaged task in movie group: {task.task_id}; resolve its identity/date first"
            )
        keys[task.task_id] = day(data["start"]) or date.max
    return sorted(
        current, key=lambda t: keys[t.task_id]
    )  # stable ties retain position order


def same_movie(task, movie):
    old = stored(task)
    if old:
        if old["id"].startswith("filmarks:") and movie["id"].startswith("filmarks:"):
            return old["id"] == movie["id"]
        return (
            old["title"] == movie["title"]
            and old["year"] is not None
            and old["year"] == movie["year"]
        )
    # Do not auto-adopt legacy notes; surface exact title matches to the operator.
    base = re.sub(r" \(\d{1,2}/\d{2}〜\)$", "", task.title)
    if base == movie["title"]:
        raise MovieError(
            f"Possible legacy duplicate {task.task_id}; confirm identity before editing"
        )
    return False


def plan(tasks, movie, allow_completed=False):
    if len({t.task_id for t in tasks}) != len(tasks):
        raise MovieError("Duplicate task IDs returned by application")
    matches = [t for t in tasks if same_movie(t, movie)]
    if any(t.parent_id for t in matches):
        raise MovieError(
            "Matching movie is a subtask; do not move or edit it automatically"
        )
    active = [t for t in matches if not t.completed]
    if len(active) > 1:
        raise MovieError(
            "Multiple unfinished copies; resolve duplicates before writing"
        )
    title, notes = render(movie)
    if not active and matches and not allow_completed:
        return {"action": "completed", "task_ids": [t.task_id for t in matches]}, None
    if active:
        old_notes = render(stored(active[0]))[1]
        if active[0].notes != old_notes:
            if not active[0].notes.startswith(old_notes + "\n\n"):
                raise MovieError(
                    "Existing generated notes were edited; review before replacement"
                )
            notes += active[0].notes[len(old_notes) :]
    target = (
        replace(active[0], title=title, notes=notes, has_deadline=False)
        if active
        else Task("__new__", title, notes, False, "", "~")
    )
    current = ordered(tasks)
    # Parse every existing unfinished top-level entry before the first write.
    sorted_tasks(tasks)
    candidates = [target if t.task_id == target.task_id else t for t in current]
    if not active:
        candidates.append(target)
    desired = sorted_tasks(candidates)
    payload = {
        "action": "update" if active else "add",
        "task_id": target.task_id,
        "title": title,
        "notes": notes,
        "current": [t.task_id for t in current],
        "desired": [t.task_id for t in desired],
        "deadline": None,
    }
    return payload, target


GROUPS_SCRIPT = r"""
using terms from application "/Applications/Glance Task.app"
on run argv
    tell application "/Applications/Glance Task.app"
        set groupsFound to fetch task groups
    end tell
    set rows to {}
    repeat with g in groupsFound
        set valuesText to {group id of g, group name of g}
        repeat with v in valuesText
            if (v as text) contains (character id 30) or (v as text) contains (character id 31) then error "Unsupported separator in group."
        end repeat
        set text item delimiters to character id 31
        set end of rows to valuesText as text
    end repeat
    set text item delimiters to character id 30
    return rows as text
end run
end using terms from
"""


def app_path():
    candidates = (
        [Path(os.environ["GLANCE_TASK_APP"])]
        if os.environ.get("GLANCE_TASK_APP")
        else [
            Path("/Applications/Glance Task.app"),
            Path.home() / "Applications/Glance Task.app",
        ]
    )
    for path in candidates:
        if path.is_dir():
            return path.resolve()
    raise MovieError(
        "Glance Task.app is not installed; set GLANCE_TASK_APP to its actual path"
    )


def run_script(source, arguments):
    app = str(app_path()).replace("\\", "\\\\").replace('"', '\\"')
    source = source.replace("/Applications/Glance Task.app", app)
    try:
        result = subprocess.run(
            ["osascript", "-e", source, "--", *arguments],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        raise MovieError(
            "AppleScript failed or timed out; inspect live state before retrying"
        ) from exc
    if result.returncode:
        raise MovieError(result.stderr.strip() or "AppleScript failed")
    return result.stdout.rstrip("\n")


def fetch(group):
    raw = run_script(FETCH_TASKS_SCRIPT, [group])
    tasks = []
    for row in raw.split(RS) if raw else []:
        fields = row.split(FS)
        if (
            len(fields) != 7
            or fields[3] not in {"true", "false"}
            or fields[6] not in {"true", "false"}
        ):
            raise MovieError("Unexpected AppleScript task record")
        tasks.append(
            Task(
                fields[0],
                fields[1],
                fields[2],
                fields[3] == "true",
                fields[4],
                fields[5],
                fields[6] == "true",
            )
        )
    return tasks


def apply(group, tasks, movie, allow_completed=False):
    preview, target = plan(tasks, movie, allow_completed)
    if target is None:
        return preview
    expected = preview["desired"]
    if preview["action"] == "add":
        index = expected.index("__new__")
        previous = expected[index - 1] if index else ""
        created_id = run_script(
            ADD_TASK_SCRIPT, [group, target.title, target.notes, previous]
        ).strip()
        if not created_id or created_id in {t.task_id for t in tasks}:
            raise MovieError(
                "Add returned an invalid ID; inspect live state before retrying"
            )
        target = replace(target, task_id=created_id)
        expected = [created_id if item == "__new__" else item for item in expected]
    else:
        run_script(
            UPDATE_TASK_SCRIPT, [group, target.task_id, target.title, target.notes]
        )
    # Re-fetch after each write. Never retry add/update on an ambiguous response.
    live = fetch(group)
    actual = [t.task_id for t in ordered(live)]
    baseline = {t.task_id: t for t in tasks}

    def check_snapshot(records):
        found = {t.task_id: t for t in records}
        if set(found) != set(baseline) | {target.task_id}:
            raise MovieError(
                "Task membership changed during apply; stop and inspect live state"
            )
        for task_id, old in baseline.items():
            if task_id == target.task_id:
                continue
            now = found[task_id]
            if replace(now, position=old.position) != old:
                raise MovieError(
                    "Another task changed during apply; stop and inspect live state"
                )
        saved = found[target.task_id]
        if (
            saved.title,
            saved.notes,
            saved.completed,
            saved.parent_id,
            saved.has_deadline,
        ) != (target.title, target.notes, False, "", False):
            raise MovieError("Saved movie does not match request; inspect live state")

    check_snapshot(live)
    if set(actual) != set(expected):
        raise MovieError("Unfinished task membership changed during apply")
    previous = ""
    for task_id in expected:
        index = actual.index(task_id)
        predecessor = actual[index - 1] if index else ""
        if predecessor != previous:
            run_script(REORDER_TASK_SCRIPT, [group, task_id, previous])
            live = fetch(group)
            check_snapshot(live)
            actual = [t.task_id for t in ordered(live)]
        previous = task_id
    live = fetch(group)
    check_snapshot(live)
    if [t.task_id for t in ordered(live)] != expected:
        raise MovieError("Final position verification failed; inspect live state")
    return {**preview, "task_id": target.task_id, "desired": expected, "verified": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["groups", "list", "upsert"])
    parser.add_argument(
        "--group",
        default=GROUP,
        help="Resolved stable ID of the 映画 group, or its unique name",
    )
    parser.add_argument(
        "--input", type=Path, help="Movie JSON file; see references/input.md"
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply the reviewed operation (default: preview only)",
    )
    parser.add_argument(
        "--allow-completed",
        action="store_true",
        help="Explicitly authorized re-registration only",
    )
    args = parser.parse_args()
    try:
        if args.command == "groups":
            if args.apply:
                raise MovieError("groups does not accept --apply")
            raw = run_script(GROUPS_SCRIPT, [])
            groups = []
            for row in raw.split(RS) if raw else []:
                fields = row.split(FS)
                if len(fields) != 2:
                    raise MovieError("Unexpected group record")
                groups.append({"id": fields[0], "name": fields[1]})
            print(json.dumps(groups, ensure_ascii=False, indent=2))
        elif args.command == "list":
            if args.apply:
                raise MovieError("list does not accept --apply")
            print(
                json.dumps(
                    [asdict(t) for t in fetch(args.group)], ensure_ascii=False, indent=2
                )
            )
        else:
            if args.input is None:
                raise MovieError("upsert requires --input")
            movie = movie_data(json.loads(args.input.read_text()))
            tasks = fetch(args.group)
            result = (
                apply(args.group, tasks, movie, args.allow_completed)
                if args.apply
                else plan(tasks, movie, args.allow_completed)[0]
            )
            print(json.dumps(result, ensure_ascii=False, indent=2))
    except (MovieError, OSError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
