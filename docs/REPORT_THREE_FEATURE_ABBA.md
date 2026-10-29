# T1/T2/T3 r02 paired performance report

This is a read-only result analysis utility kept in an **independent** branch, `perf/abba-analysis-r02`. No running experiment snapshots, results, or compiled kernels are modified.

## Usage on `ibcln01` (Python 3.6-compatible)

Copy the reporter from a local repository clone through `git archive` / `rsync`, then run:

```bash
ROOT="$HOME/WORK/dot/experiments/supermsa/probes"
python3 "$ROOT/report_three_feature_abba.py" --root "$ROOT" --revision r02
```

The reporter checks all four ABBA rows (`base, tuned, tuned, base`), 12 fresh queries, the existing ROC10/identity flags, 48 threads and one warmup each, plus that the perf job's completion marker was emitted. It refuses to calculate a result if a run is incomplete or inconsistent.

It reports *separate* average preparation, search, and end-to-end times; absolute and percentage reduction; two same-snapshot paired timing differences; and first-to-last baseline drift. It marks opposite-sign paired results as unstable. This is **screening evidence only** because there are two repeats per configuration. Historical four-format data must not be mixed into same-run paired estimates. The output field `identical_v1=YES` in the existing ABBA summaries refers to **tolerance-gated HMMER output equivalence**, not byte-exact floating-point identity.

The tool does not schedule, monitor or cancel Slurm jobs. Its input is the r02 results **after** the jobs complete.
