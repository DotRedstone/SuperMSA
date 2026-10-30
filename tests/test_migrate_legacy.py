import tempfile
import unittest
from pathlib import Path

from tools.experiments.catalog import collect, collect_aliases, create_catalog
from tools.experiments.migrate_legacy import apply, moves, plan, rollback, verify


class LegacyMigrationTest(unittest.TestCase):
    def test_apply_and_rollback_preserve_objects_and_old_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            for old, _ in moves():
                path = workspace / old
                path.parent.mkdir(parents=True, exist_ok=True)
                if str(old).startswith("baselines/") or old.suffix in (".tar", ".commit", ".py", ".sh", ".txt", ".out", ".slurm", ".tsv"):
                    path.write_text("original\n")
                else:
                    path.mkdir()
                    (path / "sentinel.txt").write_text("original\n")
            source = workspace / "experiments/supermsa/probes/four-formats-sweep-r01/source/src"
            (source / "impl_sse").mkdir(parents=True)
            (source / "impl").symlink_to("../src/impl_sse")
            rows = plan(workspace)
            (workspace / "experiments/supermsa/probes/t1-abba-r01").symlink_to(
                "experiments/e01-fasta-onepass/abba-r01")
            manifest = workspace / "experiments/supermsa/migrations/legacy-test/manifest.json"
            applied = apply(workspace, manifest)
            self.assertEqual(len(applied), len(rows))
            verify(workspace, applied)
            self.assertTrue((workspace / "experiments/supermsa/ev/EV-01/V01-four-formats/sweep-r01/source/src/impl").exists())
            records, _ = collect(workspace)
            self.assertEqual(len(records), 24)
            aliases = collect_aliases(workspace, records)
            self.assertEqual(len(aliases), len(moves()) + 1)
            catalog, count, _ = create_catalog(workspace, "synthetic")
            self.assertEqual(count, 24)
            self.assertTrue((catalog / "by-task/DP-01/V01-onepass/abba-r01").exists())
            for row in rows:
                old, new = workspace / row["old"], workspace / row["new"]
                self.assertTrue(old.is_symlink())
                self.assertEqual(old.resolve(), new)
            rollback(workspace, manifest)
            for row in rows:
                old, new = workspace / row["old"], workspace / row["new"]
                self.assertTrue(old.exists())
                self.assertFalse(old.is_symlink())
                self.assertFalse(new.exists())


if __name__ == "__main__":
    unittest.main()
