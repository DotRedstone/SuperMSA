import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools/experiments/submit_run.sh"


class SubmitRunTest(unittest.TestCase):
    def test_dry_run_validates_path_without_creating_it(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            repo = workspace / "SuperMSA"
            (repo / ".git").mkdir(parents=True)
            (repo / "job_baseline.slurm").write_text("#!/bin/bash\n")
            result = subprocess.run(
                ["bash", str(SCRIPT), "--workspace", str(workspace), "--dry-run",
                 "DP-01", "V04-chunk-64k", "20261030T120000-job123"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("/dp/DP-01/V04-chunk-64k/20261030T120000-job123", result.stdout)
            self.assertFalse((workspace / "experiments").exists())


if __name__ == "__main__":
    unittest.main()
