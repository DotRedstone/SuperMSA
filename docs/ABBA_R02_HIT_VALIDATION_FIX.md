# T1/T2/T3 ABBA r01 failure: numerical ties vs strict text diff

Observed on 2026-10-29:

- T1, T2, T3: smoke passed; first 12-query **base** trial completed;
  strict byte-identical HMMER hit-table comparison against the historical
  V1 result failed for query `Q9CIV7_1`. No tuned trial was executed.
- All three new base trials produced 542 hit rows for `Q9CIV7_1`,
  as did the successful previous four-format RAW trial.
- Sample deviations: best-domain E-value printed `4.8e-44` vs
  `4.7e-44`; two target rows with indistinguishable printed total
  bit scores changed order.
- Base search times were 579.4s (T1), 471.6s (T2), 579.9s (T3);
  these are **not paired feature results**, so no feature speedup
  can be inferred.

The old `compare_rows()` demanded byte-for-byte text equality across
independent HMMER runs. This is too strict for output rounding and
near-ties and was a test-harness error, **not proof that either
optimization changed search semantics**.

`scripts/compare_hit_tables.py` now checks the full selected-query
target ID set, query and metadata, integer domain-count fields,
printed bit-score/bias distance <=0.25, E-value relative distance
<=20%, and only permits target order inversions among targets with
<=0.25 original bit-score difference. It prints diagnostic failures
for actual target, score, rank or metadata drift. It does NOT discard
hit counts or ROC10 correctness gates from `run_feature_abba.sh`.
The tolerances are explicitly a cross-run engineering criterion, not
proof of mathematical output identity.

The corrective script `scripts/requeue_three_feature_abba_r02.sh`
executes **before any sbatch**:

1. Validates the comparator with `tests/test_compare_hit_tables.py`.
2. Compares the existing `r01/results/01-base/tbl` against the
   historical original V1 files for **all 12 queries**. If ANY fail,
   stops without submitting jobs.
3. Creates new `t1-abba-r02`, `t2-abba-r02`, `t3-abba-r02` dirs.
   Copies the compiled/validated `r01/source` snapshots, overlays ONLY
   updated `scripts/run_feature_abba.sh`,
   `scripts/compare_hit_tables.py`, `tests/test_compare_hit_tables.py`,
   checks SHA-256 hashes of all compiled executables.
4. Submits three 56-CPU paired ABBA performance jobs. Original r01
   failures are preserved, not overwritten. No new compiler smoke
   jobs are needed since all three r01 smoke jobs passed.

On local warden, after `git fetch origin`, make patch tarballs:

```fish
cd ~/Projects/SuperMSA
git fetch origin
git archive --format=tar -o /tmp/supermsa-t1-validation-r02.tar \
  origin/perf/fasta-onepass-t1 \
  scripts/run_feature_abba.sh scripts/compare_hit_tables.py tests/test_compare_hit_tables.py
git archive --format=tar -o /tmp/supermsa-t2-validation-r02.tar \
  origin/perf/bin8-batched-io-t2 \
  scripts/run_feature_abba.sh scripts/compare_hit_tables.py tests/test_compare_hit_tables.py
git archive --format=tar -o /tmp/supermsa-t3-validation-r02.tar \
  origin/perf/reader-queue-t3 \
  scripts/run_feature_abba.sh scripts/compare_hit_tables.py tests/test_compare_hit_tables.py
git archive --format=tar -o /tmp/supermsa-r02-helper.tar \
  origin/perf/reader-queue-t3 scripts/requeue_three_feature_abba_r02.sh
rsync -avP /tmp/supermsa-t1-validation-r02.tar \
  /tmp/supermsa-t2-validation-r02.tar \
  /tmp/supermsa-t3-validation-r02.tar \
  /tmp/supermsa-r02-helper.tar \
  thuscc26team39@192.168.11.1:/home/thuscc26team39/WORK/dot/experiments/supermsa/probes/
```

On ibcln01:

```bash
ROOT="$HOME/WORK/dot/experiments/supermsa/probes"
cd "$ROOT"
tar -xOf supermsa-r02-helper.tar scripts/requeue_three_feature_abba_r02.sh > requeue_three_feature_abba_r02.sh
bash -n requeue_three_feature_abba_r02.sh
bash requeue_three_feature_abba_r02.sh
squeue -u "$USER"
```

The helper is packaged separately so the original full T3 archive can
remain unchanged. No new compilation or smoke test is required.
