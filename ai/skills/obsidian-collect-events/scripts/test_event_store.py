"""Behavioral checks in disposable collections; no network or actual vault writes."""

import copy
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

import event_store as store


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fields = {
            "record_id": str(uuid.uuid4()),
            "record_kind": "event",
            "name": "Concert",
            "description": "Discovery",
            "category": "music",
            "date": "2027-01-01",
            "source_url": "https://example.org/event",
            "verification": "source_only",
            "discovery_urls": ["https://example.org/list"],
        }

    def save(self, fields=None, revision=0, **kw):
        return store.put(
            self.root,
            fields or self.fields,
            revision,
            "Observed on the cited page",
            "2026-11-05",
            **kw,
        )

    def test_repeated_discovery_does_not_increment_revision(self):
        first = self.save()
        second = self.save(revision=1)
        self.assertEqual(first["record_id"], second["record_id"])
        self.assertEqual(second["revision"], 1)
        self.assertFalse(second["material_change"])

    def test_reschedule_retains_identity_and_history(self):
        first = self.save()
        update = {"record_id": first["record_id"], "date": "2027-01-02"}
        result = self.save(update, revision=1)
        data, body, _ = store.load(Path(result["path"]))
        self.assertEqual(data["revision"], 2)
        self.assertEqual(data["first_seen"], "2026-11-05")
        self.assertIn("2027-01-01", body)
        self.assertIn("2027-01-02", body)

    def test_stale_writer_cannot_overwrite(self):
        result = self.save()
        before = Path(result["path"]).read_bytes()
        with self.assertRaises(store.StoreError):
            self.save({**self.fields, "name": "Overwrite"}, revision=0)
        self.assertEqual(before, Path(result["path"]).read_bytes())

    def test_lock_refuses_second_writer(self):
        with store.locked(self.root), self.assertRaises(store.StoreError):
            self.save()
        self.assertFalse((self.root / ".event-store.lock").exists())

    def test_dry_run_does_not_write(self):
        self.assertTrue(self.save(dry_run=True)["dry_run"])
        self.assertEqual(list(self.root.iterdir()), [])

    def test_duplicate_new_id_refused(self):
        self.save()
        with self.assertRaises(store.StoreError):
            self.save({**self.fields, "record_id": str(uuid.uuid4())})

    def test_discovery_url_union_without_material_change(self):
        result = self.save()
        update = {
            "record_id": result["record_id"],
            "discovery_urls": ["https://other.example/list"],
        }
        second = self.save(update, revision=1)
        data, _, _ = store.load(Path(second["path"]))
        self.assertEqual(len(data["discovery_urls"]), 2)
        self.assertEqual(second["revision"], 1)

    def test_official_state_needs_evidence_fields(self):
        with self.assertRaises(store.StoreError):
            self.save({**self.fields, "verification": "official"})
        self.assertFalse((self.root / "candidates").exists())

    def test_unknown_private_field_rejected(self):
        with self.assertRaises(store.StoreError):
            self.save({**self.fields, "recipient": "private@example.org"})

    def test_symlink_directory_refused(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.root / "candidates").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(store.StoreError):
            self.save()
        self.assertEqual(list(outside.iterdir()), [])

    def test_failed_replace_keeps_old_file(self):
        result = self.save()
        path = Path(result["path"])
        before = path.read_bytes()
        with patch.object(store.os, "replace", side_effect=OSError("failed")):
            with self.assertRaises(OSError):
                self.save({"record_id": result["record_id"], "name": "Changed"}, 1)
        self.assertEqual(before, path.read_bytes())
        self.assertEqual(len(list(path.parent.iterdir())), 1)

    def test_existing_slug_and_body_are_preserved(self):
        first = self.save()
        original = Path(first["path"])
        slug = original.with_name("existing-slug.md")
        original.rename(slug)
        with slug.open("a", encoding="utf-8") as file:
            file.write("\n## Prior evidence\nDo not discard\n")
        result = self.save({"record_id": first["record_id"], "venue": "New venue"}, 1)
        self.assertEqual(Path(result["path"]), slug)
        self.assertIn("Do not discard", slug.read_text(encoding="utf-8"))

    def test_unknown_values_can_be_removed_explicitly(self):
        first = self.save({**self.fields, "venue": "Old venue"})
        result = self.save({"record_id": first["record_id"], "venue": None}, 1)
        data, body, _ = store.load(Path(result["path"]))
        self.assertNotIn("venue", data)
        self.assertIn("Old venue", body)
        self.assertEqual(result["revision"], 2)

    def test_ambiguous_identity_does_not_merge_distinct_times(self):
        self.save({**self.fields, "time_text": "11:00"})
        second = self.save(
            {**self.fields, "record_id": str(uuid.uuid4()), "time_text": "15:00"}
        )
        self.assertEqual(second["revision"], 1)
        self.assertEqual(len(list((self.root / "candidates").glob("*.md"))), 2)

    def test_older_observation_refused(self):
        self.save()
        with self.assertRaises(store.StoreError):
            store.put(self.root, copy.deepcopy(self.fields), 1, "Old", "2026-11-04")


if __name__ == "__main__":
    unittest.main()
