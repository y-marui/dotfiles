"""Exercise private skill manifests against isolated homes, caches and dotfiles."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "ai/skills"


class PrivateSkillsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.dot = self.base / "dotfiles"
        self.skills = self.dot / "ai/skills"
        self.skills.mkdir(parents=True)
        for name in ["apply.sh", "diff.sh", "prune.sh", "external_manifest.py"]:
            shutil.copy2(SOURCE / name, self.skills / name)
        self.private = self.base / "dotfiles-private/ai/skills/external.json"
        self.private.parent.mkdir(parents=True)
        self.public = self.skills / "external.json"
        self.public.write_text('{"skills": []}')
        self.private.write_text('{"skills": []}')
        self.home = self.base / "home"
        self.home.mkdir()
        self.cache = self.base / "data/dotfiles/skills"
        self.env = dict(
            os.environ,
            HOME=str(self.home),
            XDG_DATA_HOME=str(self.base / "data"),
            DOTFILES_DIR=str(self.dot),
        )
        for key in [
            "DOTFILES_EXTERNAL_FILE",
            "DOTFILES_PRIVATE_EXTERNAL_FILE",
            "SKILL_SELECT_FILE",
        ]:
            self.env.pop(key, None)

    def run_script(self, script, agent="codex", expected=0):
        result = subprocess.run(
            ["bash", str(self.skills / f"{script}.sh"), agent],
            env=self.env,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def seed(self, name, targets=None):
        entry = {
            "name": name,
            "repo": "example/private-skills",
            "ref": "a" * 40,
            "path": f"skills/{name}",
        }
        if targets is not None:
            entry["targets"] = targets
        source = self.cache / name
        source.mkdir(parents=True)
        (source / "SKILL.md").write_text(f"---\nname: {name}\ndescription: test\n---\n")
        state = self.cache / ".sources" / name
        state.parent.mkdir(exist_ok=True)
        state.write_text(f"{entry['repo']}\t{entry['ref']}\t{entry['path']}\n")
        return entry

    def test_private_apply_diff_and_prune_keep_unmanaged(self):
        entry = self.seed("private-example")
        self.private.write_text(json.dumps({"skills": [entry]}))
        for agent, directory in [("codex", ".agents"), ("claude", ".claude")]:
            self.run_script("apply", agent)
            self.assertTrue(
                (self.home / directory / "skills/private-example").is_symlink()
            )
            self.run_script("diff", agent)
            self.run_script("prune", agent)
            self.assertTrue((self.cache / "private-example").is_dir())
        unmanaged = self.home / ".agents/skills/untouched"
        unmanaged.mkdir()
        (unmanaged / "SKILL.md").write_text("user owned")
        self.private.write_text('{"skills": []}')
        self.run_script("prune")
        self.assertFalse((self.home / ".agents/skills/private-example").exists())
        self.assertTrue(
            (self.cache / "private-example").exists()
        )  # Claude still references it
        self.run_script("prune", "claude")
        self.assertFalse((self.cache / "private-example").exists())
        self.assertTrue(unmanaged.is_dir())

    def test_updated_revision_is_detected_with_existing_links(self):
        entry = self.seed("private-example")
        self.private.write_text(json.dumps({"skills": [entry]}))
        self.run_script("apply")
        self.run_script("diff")
        entry["ref"] = "b" * 40
        self.private.write_text(json.dumps({"skills": [entry]}))
        result = self.run_script("diff", expected=1)
        self.assertIn("[~source]", result.stdout)
        self.assertNotIn("[~link]", result.stdout)

    def test_duplicate_or_malformed_manifest_stops_before_mutation(self):
        entry = self.seed("duplicate")
        self.public.write_text(json.dumps({"skills": [entry]}))
        self.private.write_text(json.dumps({"skills": [entry]}))
        self.run_script("apply", expected=1)
        self.assertFalse((self.home / ".agents").exists())
        self.private.write_text("{broken")
        self.run_script("prune", expected=1)
        self.assertTrue((self.cache / "duplicate").exists())

    def test_missing_private_and_explicit_override(self):
        self.private.unlink()
        self.run_script("apply")
        entry = self.seed("private-example", ["claude"])
        self.private.write_text(json.dumps({"skills": [entry]}))
        self.env["DOTFILES_EXTERNAL_FILE"] = str(self.public)
        self.run_script("apply", "claude")
        self.assertFalse((self.home / ".claude/skills/private-example").exists())
        self.env["DOTFILES_PRIVATE_EXTERNAL_FILE"] = str(self.private)
        self.run_script("apply", "claude")
        self.assertTrue((self.home / ".claude/skills/private-example").is_symlink())
        self.run_script("diff", "claude")


if __name__ == "__main__":
    unittest.main()
