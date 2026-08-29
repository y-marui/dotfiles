#!/usr/bin/env python3

import argparse
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from datetime import date
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("museum_events.py")
SPEC = importlib.util.spec_from_file_location("museum_events", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
museum_events = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = museum_events
SPEC.loader.exec_module(museum_events)


class MuseumEventsTests(unittest.TestCase):
    def test_format_notes_uses_shortest_unambiguous_period(self):
        cases = [
            ("2026-06-04", "2026-06-15", "2026/06/04-15 会場"),
            ("2026-08-15", "2026-10-12", "2026/08/15-10/12 会場"),
            ("2026-11-14", "2027-03-28", "2026/11/14-2027/03/28 会場"),
            ("2027-01-30", "2027-01-31", "2027/01/30-31 会場"),
            ("2026-08-15", "2026-08-15", "2026/08/15 会場"),
        ]
        for start, end, expected in cases:
            with self.subTest(expected=expected):
                self.assertEqual(
                    museum_events.format_notes(
                        date.fromisoformat(start), date.fromisoformat(end), "会場"
                    ),
                    expected,
                )

    def test_parse_notes_accepts_existing_unpadded_values_and_canonicalizes(self):
        parsed = museum_events.parse_notes("2027/1/30-31 せんだいメディアテーク")
        self.assertEqual(parsed.start, date(2027, 1, 30))
        self.assertEqual(parsed.end, date(2027, 1, 31))
        self.assertEqual(parsed.notes, "2027/01/30-31 せんだいメディアテーク")

    def test_sort_uses_end_then_start_then_position(self):
        records = [
            self.task("a", "2026/07/10-08/23 A", "0002"),
            self.task("b", "2026/07/04-08/23 B", "0001"),
            self.task("c", "2026/06/13-08/30 C", "0000"),
        ]
        plan = museum_events.build_sort_plan(records)
        self.assertEqual([task.task_id for task in plan.desired], ["b", "a", "c"])

    def test_current_order_uses_position_not_fetch_order(self):
        records = [
            self.task("late-fetch", "2026/01/01-02 A", "0001"),
            self.task("early-fetch", "2026/01/01-02 B", "0000"),
        ]
        plan = museum_events.build_sort_plan(records)
        self.assertEqual(
            [task.task_id for task in plan.current], ["early-fetch", "late-fetch"]
        )
        self.assertEqual(
            [task.task_id for task in plan.desired], ["early-fetch", "late-fetch"]
        )

    def test_hierarchy_compares_positions_only_between_siblings(self):
        parent_b = self.task("parent-b", "2026/01/01 B", "0001")
        child = museum_events.TaskRecord(
            task_id="child",
            title="child",
            notes="2026/01/01 child",
            completed=False,
            parent_id="parent-b",
            position="0000",
        )
        parent_a = self.task("parent-a", "2026/01/01 A", "0000")
        ordered = museum_events.hierarchy_position_sorted([parent_b, child, parent_a])
        self.assertEqual(
            [task.task_id for task in ordered], ["parent-a", "parent-b", "child"]
        )

    def test_format_can_replace_fully_malformed_notes(self):
        task = self.task("bad", "not a period", "0000")
        updated = museum_events.resolve_format(
            task,
            title=None,
            start_text="2027/01/30",
            end_text="2027/01/31",
            venue="せんだいメディアテーク",
        )
        self.assertEqual(
            updated.notes, "2027/01/30-31 せんだいメディアテーク"
        )

    def test_preflight_audits_kanto_then_tohoku(self):
        tasks_by_group = {
            "美術展: 関東": [self.task("kanto", "2026/01/01 関東会場", "0000")],
            "美術展: 東北": [self.task("tohoku", "2026/01/02 東北会場", "0000")],
        }
        with mock.patch.object(
            museum_events,
            "fetch_tasks",
            side_effect=lambda group: tasks_by_group[group],
        ) as fetch:
            payload = museum_events.command_preflight(mock.Mock())

        self.assertEqual(
            [call.args[0] for call in fetch.call_args_list],
            ["美術展: 関東", "美術展: 東北"],
        )
        self.assertEqual(
            [group["group"] for group in payload["groups"]],
            ["美術展: 関東", "美術展: 東北"],
        )

    def test_strip_status_emoji_removes_known_trailing_emoji(self):
        for emoji in museum_events.STATUS_EMOJIS:
            with self.subTest(emoji=emoji):
                self.assertEqual(
                    museum_events.strip_status_emoji(f"タイトル {emoji}"), "タイトル"
                )
        self.assertEqual(museum_events.strip_status_emoji("タイトル"), "タイトル")

    def test_status_emoji_for_reflects_todays_date(self):
        period = museum_events.EventPeriod(
            start=date(2026, 7, 1), end=date(2026, 7, 10), venue="会場"
        )
        self.assertEqual(
            museum_events.status_emoji_for(period, date(2026, 6, 30)),
            museum_events.STATUS_EMOJI_BEFORE,
        )
        self.assertEqual(
            museum_events.status_emoji_for(period, date(2026, 7, 5)),
            museum_events.STATUS_EMOJI_ONGOING,
        )
        self.assertEqual(
            museum_events.status_emoji_for(period, date(2026, 7, 11)),
            museum_events.STATUS_EMOJI_ENDED,
        )

    def test_build_sort_plan_tolerant_sorts_format_errors_last(self):
        records = [
            self.task("bad", "not a period", "0000"),
            self.task("late", "2026/08/23 late", "0001"),
            self.task("early", "2026/07/10 early", "0002"),
        ]
        plan, error_ids = museum_events.build_sort_plan_tolerant(records)
        self.assertEqual(
            [task.task_id for task in plan.desired], ["early", "late", "bad"]
        )
        self.assertEqual(error_ids, ("bad",))

    def test_refresh_group_retitles_from_todays_date_without_reordering(self):
        today = date(2026, 7, 5)
        tasks = [
            museum_events.TaskRecord(
                task_id="a",
                title="展示A ⏳",
                notes="2026/07/01-10 会場A",
                completed=False,
                parent_id=None,
                position="0000",
            ),
            museum_events.TaskRecord(
                task_id="b",
                title="展示B ⏳",
                notes="2026/07/20-30 会場B",
                completed=False,
                parent_id=None,
                position="0001",
            ),
        ]
        with mock.patch.object(
            museum_events, "fetch_tasks", side_effect=lambda _group: tasks
        ) as fetch, mock.patch.object(
            museum_events, "run_applescript"
        ) as run_applescript:
            result = museum_events.refresh_group("美術展: 関東", today, apply=True)

        self.assertEqual(result.retitled, (("a", "展示A 🎟️"),))
        self.assertEqual(result.format_errors, ())
        self.assertFalse(result.needs_reorder)
        self.assertFalse(result.reordered)
        run_applescript.assert_called_once_with(
            museum_events.UPDATE_TASK_SCRIPT,
            ["美術展: 関東", "a", "展示A 🎟️", "2026/07/01-10 会場A"],
        )
        self.assertEqual(fetch.call_count, 2)

    def test_refresh_group_flags_format_error_without_applescript_call(self):
        today = date(2026, 7, 5)
        tasks = [
            museum_events.TaskRecord(
                task_id="bad",
                title="壊れたタスク",
                notes="not a period",
                completed=False,
                parent_id=None,
                position="0000",
            )
        ]
        with mock.patch.object(
            museum_events, "fetch_tasks", side_effect=lambda _group: tasks
        ), mock.patch.object(museum_events, "run_applescript") as run_applescript:
            result = museum_events.refresh_group("美術展: 関東", today, apply=True)

        self.assertEqual(
            result.retitled, (("bad", f"壊れたタスク {museum_events.STATUS_EMOJI_FORMAT_ERROR}"),)
        )
        self.assertEqual(len(result.format_errors), 1)
        self.assertEqual(result.format_errors[0].task_id, "bad")
        run_applescript.assert_called_once_with(
            museum_events.UPDATE_TASK_SCRIPT,
            ["美術展: 関東", "bad", f"壊れたタスク {museum_events.STATUS_EMOJI_FORMAT_ERROR}", "not a period"],
        )

    def test_command_refresh_notifies_once_on_format_errors(self):
        kanto_error = museum_events.FormatErrorInfo("k1", "関東タスク", "bad notes")
        tohoku_error = museum_events.FormatErrorInfo("t1", "東北タスク", "bad notes")
        results = {
            "美術展: 関東": museum_events.GroupRefreshResult(
                group="美術展: 関東",
                apply=True,
                retitled=(),
                format_errors=(kanto_error,),
                needs_reorder=False,
                reordered=False,
            ),
            "美術展: 東北": museum_events.GroupRefreshResult(
                group="美術展: 東北",
                apply=True,
                retitled=(),
                format_errors=(tohoku_error,),
                needs_reorder=False,
                reordered=False,
            ),
        }
        with mock.patch.object(
            museum_events, "refresh_group", side_effect=lambda group, _today, _apply: results[group]
        ), mock.patch.object(museum_events, "notify") as notify:
            args = argparse.Namespace(apply=True)
            payload = museum_events.command_refresh(args)

        self.assertEqual(len(payload["format_errors"]), 2)
        notify.assert_called_once()
        title, message = notify.call_args.args
        self.assertIn("書式エラー", title)
        self.assertIn("関東タスク", message)
        self.assertIn("ほか1件", message)

    def test_applescript_sources_compile(self):
        sources = (
            museum_events.FETCH_TASKS_SCRIPT,
            museum_events.ADD_TASK_SCRIPT,
            museum_events.UPDATE_TASK_SCRIPT,
            museum_events.REORDER_TASK_SCRIPT,
            museum_events.NOTIFY_SCRIPT,
        )
        with tempfile.TemporaryDirectory() as directory:
            for index, source in enumerate(sources):
                result = subprocess.run(
                    [
                        "osacompile",
                        "-o",
                        str(Path(directory) / f"script-{index}.scpt"),
                        "-e",
                        source,
                    ],
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

    def task(self, task_id, notes, position):
        return museum_events.TaskRecord(
            task_id=task_id,
            title=task_id,
            notes=notes,
            completed=False,
            parent_id=None,
            position=position,
        )


if __name__ == "__main__":
    unittest.main()
