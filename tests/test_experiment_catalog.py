import csv
import tempfile
import unittest
from pathlib import Path

from tools.experiments.catalog import create_catalog


HEADER = "trial\tfeature\tmode\tprologue_s\tsearch_s\ttotal_s\tqueries_run\tquality\tidentical_v1\tworker_threads\twarmup_runs\n"


class CatalogTest(unittest.TestCase):
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
            baseline = workspace / "baselines/supermsa"
            baseline.mkdir(parents=True)
            (baseline / "stdout.16155687").write_text("original log\n")

            output, records_count, trials_count = create_catalog(workspace, "snapshot")
            self.assertEqual((records_count, trials_count), (3, 1))
            with (output / "records.tsv").open() as stream:
                records = list(csv.DictReader(stream, delimiter="\t"))
            first_record = next(row for row in records if row["run_id"] == "abba-r01")
            second_record = next(row for row in records if row["run_id"] == "abba-r02")
            baseline_record = next(row for row in records if row["record_kind"] == "BASELINE_LOG")
            self.assertEqual(first_record["summary_state"], "HEADER_ONLY")
            self.assertEqual(first_record["summary_rows"], "0")
            self.assertEqual(first_record["job_ids"], "16169715,16169716")
            self.assertEqual(second_record["summary_state"], "HAS_TRIALS")
            self.assertEqual(second_record["source_commit"], "abcdef1234567890")
            self.assertEqual(baseline_record["job_ids"], "16155687")
            self.assertEqual((first / "summary.tsv").read_text(), HEADER)
            with self.assertRaises(FileExistsError):
                create_catalog(workspace, "snapshot")


if __name__ == "__main__":
    unittest.main()
