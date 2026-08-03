#!/usr/bin/env python3

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

    def test_previous_task_id_returns_desired_predecessor(self):
        records = [
            self.task("a", "2026/01/01 A", "0000"),
            self.task("new", "2026/01/02 B", "~new"),
            self.task("c", "2026/01/03 C", "0001"),
        ]
        plan = museum_events.build_sort_plan(records)
        self.assertEqual(museum_events.previous_task_id(plan, "new"), "a")

    def test_previous_task_id_returns_none_for_desired_beginning(self):
        records = [
            self.task("new", "2026/01/01 A", "~new"),
            self.task("after", "2026/01/02 B", "0000"),
        ]
        plan = museum_events.build_sort_plan(records)
        self.assertIsNone(museum_events.previous_task_id(plan, "new"))

    def test_add_applies_one_direct_insert_without_reordering(self):
        group = "美術展: 関東"
        existing = [
            self.task("before", "2026/01/01-10 A", "0000"),
            self.task("after", "2026/01/01-30 C", "0001"),
        ]
        created = museum_events.TaskRecord(
            task_id="created",
            title="New exhibition",
            notes="2026/01/01-20 B",
            completed=False,
            parent_id=None,
            position="0001",
        )
        after_insert = [
            self.task("before", "2026/01/01-10 A", "0000"),
            created,
            self.task("after", "2026/01/01-30 C", "0002"),
        ]
        args = mock.Mock(
            group=group,
            title="New exhibition",
            start="2026/01/01",
            end="2026/01/20",
            venue="B",
            apply=True,
        )

        with mock.patch.object(
            museum_events, "fetch_tasks", side_effect=[existing, after_insert]
        ), mock.patch.object(
            museum_events, "run_applescript", return_value="created"
        ) as run_applescript:
            payload = museum_events.command_add(args)

        run_applescript.assert_called_once_with(
            museum_events.ADD_TASK_SCRIPT,
            [group, "New exhibition", "2026/01/01-20 B", "before"],
        )
        self.assertEqual(payload["insert_after_task_id"], "before")
        self.assertTrue(payload["inserted_in_position"])
        self.assertNotIn("reordered", payload)

    def test_add_refuses_existing_out_of_order_tasks_before_creating(self):
        args = mock.Mock(
            group="美術展: 関東",
            title="New exhibition",
            start="2026/01/01",
            end="2026/01/20",
            venue="B",
            apply=True,
        )
        existing = [
            self.task("later", "2026/01/01-30 C", "0000"),
            self.task("earlier", "2026/01/01-10 A", "0001"),
        ]

        with mock.patch.object(
            museum_events, "fetch_tasks", return_value=existing
        ), mock.patch.object(museum_events, "run_applescript") as run_applescript:
            with self.assertRaisesRegex(
                museum_events.MuseumEventError, "out of position order"
            ):
                museum_events.command_add(args)

        run_applescript.assert_not_called()

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

    def test_applescript_sources_compile(self):
        sources = (
            museum_events.FETCH_TASKS_SCRIPT,
            museum_events.ADD_TASK_SCRIPT,
            museum_events.UPDATE_TASK_SCRIPT,
            museum_events.REORDER_TASK_SCRIPT,
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
