import csv
import json
import tempfile
import unittest
from pathlib import Path

from tools.experiments.catalog import create_catalog


HEADER = "trial\tfeature\tmode\tprologue_s\tsearch_s\ttotal_s\tqueries_run\tquality\tidentical_v1\tworker_threads\twarmup_runs\n"


class CatalogTest(unittest.TestCase):
    def test_migrated_logs_and_legacy_script_links_are_indexed(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            root = workspace / "experiments/supermsa"
            run = root / "ck/CK-01/V01-band-limit/sweep-r01"
            run.mkdir(parents=True)
            (run / "band.16167175.out").write_text("completed\n")
            (run / "scan.16158805_0.out").write_text("completed\n")
            config = run / "p6-t8"
            config.mkdir()
            (config / "summary.tsv").write_text("config\tseconds\np6-t8\t567.8\n")
            script = root / "assets/legacy-scripts/catalog-old.py"
            script.parent.mkdir(parents=True)
            script.write_text("# old version\n")
            alias = root / "scripts/catalog-old.py"
            alias.parent.mkdir()
            alias.symlink_to("../assets/legacy-scripts/catalog-old.py")

            output, records_count, trials_count = create_catalog(workspace, "migrated")
            self.assertEqual((records_count, trials_count), (1, 1))
            with (output / "records.tsv").open() as stream:
                record = next(csv.DictReader(stream, delimiter="\t"))
            with (output / "trials.tsv").open() as stream:
                trial = next(csv.DictReader(stream, delimiter="\t"))
            with (output / "aliases.tsv").open() as stream:
                aliases = list(csv.DictReader(stream, delimiter="\t"))
            with (output / "supporting.tsv").open() as stream:
                supporting = list(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual(record["job_ids"], "16158805,16167175")
            self.assertEqual(record["summary_state"], "HAS_TRIALS")
            self.assertEqual(trial["summary_path"], (config / "summary.tsv").relative_to(workspace).as_posix())
            self.assertEqual(trial["seconds"], "567.8")
            self.assertEqual(len(record["raw_log_paths"].split(",")), 2)
            self.assertEqual(aliases, [{"alias_path": alias.relative_to(workspace).as_posix(),
                                        "canonical_path": script.relative_to(workspace).as_posix()}])
            self.assertEqual(next(row for row in supporting if row["file_path"].endswith("catalog-old.py"))["role"], "SCRIPT")

    def test_empty_and_completed_summaries_remain_distinct(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            base = workspace / "experiments/supermsa/probes/experiments/e01-fasta-onepass"
            first = base / "abba-r01"
            second = base / "abba-r02"
            first.mkdir(parents=True)
            second.mkdir()
            (first / "summary.tsv").write_text(HEADER)
            (first / "job_ids.txt").write_text("smoke=16169715\nperf=16169716\n")
            (second / "summary.tsv").write_text(HEADER + "1\tonepass\ttuned\t2\t10\t12\t12\tPASS\ttrue\t8\t1\n")
            (second / "source-commit.txt").write_text("abcdef1234567890\n")
            (workspace / "experiments/supermsa/probes/t1-abba-r02").symlink_to("experiments/e01-fasta-onepass/abba-r02")
            alternate = workspace / "experiments/supermsa/probes/ssv-band-sweep-r01"
            alternate.mkdir(parents=True)
            (alternate / "summary.tsv").write_text("trial\tband\tseconds\tmatching_original\n1\t14\t3.5\ttrue\n")
            baseline = workspace / "baselines/supermsa"
            baseline.mkdir(parents=True)
            (baseline / "stdout.16155687").write_text("original log\n")
            (workspace / "experiments/supermsa/probes/source.tar").write_text("archive")

            output, records_count, trials_count = create_catalog(workspace, "snapshot")
            self.assertEqual((records_count, trials_count), (4, 2))
            with (output / "records.tsv").open() as stream:
                records = list(csv.DictReader(stream, delimiter="\t"))
            with (output / "trials.tsv").open() as stream:
                trials = list(csv.DictReader(stream, delimiter="\t"))
            with (output / "aliases.tsv").open() as stream:
                aliases = list(csv.DictReader(stream, delimiter="\t"))
            with (output / "supporting.tsv").open() as stream:
                supporting = list(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual(json.loads((output / "manifest.json").read_text())["path_base"], "workspace_root")
            first_record = next(row for row in records if row["run_id"] == "abba-r01")
            second_record = next(row for row in records if row["run_id"] == "abba-r02")
            baseline_record = next(row for row in records if row["record_kind"] == "BASELINE_LOG")
            self.assertEqual(first_record["summary_state"], "HEADER_ONLY")
            self.assertEqual(first_record["summary_rows"], "0")
            self.assertEqual(first_record["job_ids"], "16169715,16169716")
            self.assertEqual(second_record["summary_state"], "HAS_TRIALS")
            self.assertEqual(second_record["source_commit"], "abcdef1234567890")
            self.assertEqual(baseline_record["job_ids"], "16155687")
            alternate_record = next(row for row in records if row["variant"] == "ssv-band-sweep-r01")
            self.assertEqual(alternate_record["summary_state"], "HAS_TRIALS")
            self.assertEqual(next(row for row in trials if row["record_path"] == alternate_record["record_path"])["seconds"], "3.5")
            self.assertEqual(len(aliases), 1)
            self.assertEqual(aliases[0]["canonical_path"], second_record["record_path"])
            self.assertEqual((output / "by-task/DP-01/e01-fasta-onepass/abba-r02").resolve(), second)
            self.assertEqual(next(row for row in supporting if row["file_path"].endswith("source.tar"))["role"], "SOURCE_ARCHIVE")
            self.assertEqual((first / "summary.tsv").read_text(), HEADER)
            with self.assertRaises(FileExistsError):
                create_catalog(workspace, "snapshot")


if __name__ == "__main__":
    unittest.main()
