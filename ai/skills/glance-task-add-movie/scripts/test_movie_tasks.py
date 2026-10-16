"""Exercise movie ordering, duplicate handling, and writes without a live account."""

import unittest
from dataclasses import replace
from unittest.mock import patch

import movie_tasks as m


def movie(title="A", start="2026-10-23", movie_id=1):
    return m.movie_data(
        {
            "title": title,
            "year": 2026,
            "filmarks_url": f"https://filmarks.com/movies/{movie_id}",
            "release_date": "2026-10-16",
            "checked_on": "2026-10-16",
            "screenings": [
                {
                    "cinema": "MOVIX仙台",
                    "start": start,
                    "url": "https://example.com/movie",
                }
            ],
        }
    )


def task(task_id, data, position="01", **kwargs):
    title, notes = m.render(data)
    return m.Task(task_id, title, notes, False, "", position, **kwargs)


class MovieTests(unittest.TestCase):
    def test_local_start_and_unknown_are_not_national_release(self):
        self.assertEqual(movie()["start"], "2026-10-23")
        self.assertIsNone(movie(start=None)["start"])
        data = m.movie_data(
            {
                "title": "B",
                "year": 2026,
                "release_date": "2027-01-08",
                "official_url": "https://example.com/b",
                "checked_on": "2026-10-16",
            }
        )
        self.assertEqual(data["start"], "2027-01-08")
        self.assertEqual(data["basis"], "国内公開")

    def test_roundtrip_and_earliest_cinema(self):
        raw = movie()
        raw["screenings"].append(
            {
                "cinema": "フォーラム仙台",
                "start": "2026-10-20",
                "end": "2026-11-01",
                "end_status": "planned",
                "url": "https://example.com/f",
            }
        )
        parsed = m.movie_data(raw)
        self.assertEqual(parsed["start"], "2026-10-20")
        self.assertEqual(m.stored(task("a", parsed)), parsed)
        self.assertIn("2026-11-01予定", m.render(parsed)[1])

    def test_position_order_ties_unknown_and_year_crossing(self):
        tasks = [
            task("unknown", movie("U", None, 4), "04"),
            task("later", movie("B", "2027-01-01", 2), "03"),
            task("same2", movie("C", movie_id=3), "02"),
            task("first", movie(), "01"),
        ]
        result, _ = m.plan(tasks, movie("New", movie_id=5))
        self.assertEqual(
            result["desired"], ["first", "same2", "__new__", "later", "unknown"]
        )

    def test_id_duplicate_updates_instead_of_add(self):
        old = task("a", movie(), has_deadline=True)
        result, target = m.plan([old], movie("Changed title", "2026-11-01"))
        self.assertEqual(result["action"], "update")
        self.assertEqual(target.task_id, "a")
        self.assertFalse(target.has_deadline)

    def test_user_note_suffix_is_preserved_and_edits_stop(self):
        old = task("a", movie())
        annotated = replace(old, notes=old.notes + "\n\n友人と観る")
        _, target = m.plan([annotated], movie(start="2026-11-01"))
        self.assertTrue(target.notes.endswith("\n\n友人と観る"))
        with self.assertRaises(m.MovieError):
            m.plan(
                [replace(old, notes=old.notes.replace("上映開始:", "開始:"))], movie()
            )

    def test_distinct_remakes_not_merged(self):
        result, _ = m.plan([task("a", movie())], movie(movie_id=2))
        self.assertEqual(result["action"], "add")

    def test_completed_requires_explicit_reregistration(self):
        done = replace(task("done", movie()), completed=True)
        result, target = m.plan([done], movie())
        self.assertEqual(result["action"], "completed")
        self.assertIsNone(target)
        self.assertEqual(m.plan([done], movie(), True)[0]["action"], "add")

    def test_unmanaged_and_subtask_stop(self):
        unmanaged = m.Task("old", "Other", "user notes", False, "", "01")
        with self.assertRaises(m.MovieError):
            m.plan([unmanaged], movie())
        with self.assertRaises(m.MovieError):
            m.plan([replace(task("a", movie()), parent_id="parent")], movie())
        with self.assertRaises(m.MovieError):
            m.plan([replace(task("a", movie()), position="")], movie())

    def test_invalid_screening_fails_before_write(self):
        for field, value in [
            ("start", "2026-02-30"),
            ("end", "2026-10-01"),
            ("url", "file:///tmp/a"),
        ]:
            raw = movie()
            raw["screenings"][0][field] = value
            with self.assertRaises(m.MovieError):
                m.movie_data(raw)

    def test_apply_adds_once_in_correct_position_and_verifies(self):
        before = [task("a", movie("A", "2026-10-20", 1))]
        new = movie("B", movie_id=2)
        after = before + [task("newid", new, "02")]
        with (
            patch.object(m, "run_script", return_value="newid") as run,
            patch.object(m, "fetch", return_value=after),
        ):
            result = m.apply("group-id", before, new)
        self.assertTrue(result["verified"])
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[1][-1], "a")
        self.assertNotIn("deadline", run.call_args.args[0])

    def test_update_clears_date_and_moves_with_verified_position(self):
        early = task("early", movie("Early", "2026-10-20", 2), "01")
        old = task("old", movie("Old", "2026-11-01", 1), "02", has_deadline=True)
        changed = movie("Old", "2026-10-19", 1)
        updated = task("old", changed, "02")
        moved = [replace(updated, position="00"), early]
        with (
            patch.object(m, "run_script", return_value="old") as run,
            patch.object(m, "fetch", side_effect=[[early, updated], moved, moved]),
        ):
            result = m.apply("group-id", [early, old], changed)
        self.assertTrue(result["verified"])
        self.assertIn("deadline missing value", run.call_args_list[0].args[0])
        self.assertEqual(result["desired"], ["old", "early"])

    def test_ambiguous_failure_does_not_retry_add(self):
        with (
            patch.object(m, "run_script", side_effect=m.MovieError("timeout")) as run,
            self.assertRaises(m.MovieError),
        ):
            m.apply("g", [], movie())
        self.assertEqual(run.call_count, 1)

    def test_concurrent_change_stops_after_first_write(self):
        extra = task("unrelated", movie("X", movie_id=9))
        with (
            patch.object(m, "run_script", return_value="newid") as run,
            patch.object(m, "fetch", return_value=[task("newid", movie()), extra]),
            self.assertRaises(m.MovieError),
        ):
            m.apply("g", [], movie())
        self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
