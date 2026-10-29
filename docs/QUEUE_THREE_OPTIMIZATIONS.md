# Queue T1, T2, T3 on THUSCC Slurm

**This is a submission procedure, not proof that jobs have been submitted.**
The three isolated branches are `perf/fasta-onepass-t1`,
`perf/bin8-batched-io-t2`, and `perf/reader-queue-t3`.
All are unverified experimental code. Do not merge them into the
already queued/running `perf/db-four-way` snapshot.

## 1. Local warden (fish)

```fish
cd ~/Projects/SuperMSA
git fetch origin

git archive --format=tar -o /tmp/supermsa-t1.tar origin/perf/fasta-onepass-t1
git archive --format=tar -o /tmp/supermsa-t2.tar origin/perf/bin8-batched-io-t2
git archive --format=tar -o /tmp/supermsa-t3.tar origin/perf/reader-queue-t3

ls -lh /tmp/supermsa-t1.tar /tmp/supermsa-t2.tar /tmp/supermsa-t3.tar

rsync -avP /tmp/supermsa-t1.tar /tmp/supermsa-t2.tar /tmp/supermsa-t3.tar \
  thuscc26team39@192.168.11.1:/home/thuscc26team39/WORK/dot/experiments/supermsa/probes/
```

## 2. Login node (ibcln01)

```bash
ROOT="$HOME/WORK/dot/experiments/supermsa/probes"
cd "$ROOT"

# Inspect contents before executing the submission helper:
tar -xOf supermsa-t3.tar scripts/submit_three_optimizations.sh \
  > submit_three_optimizations.sh
bash -n submit_three_optimizations.sh

# This is the command that actually invokes six sbatch submissions:
bash submit_three_optimizations.sh

squeue -u "$USER"
```

The helper performs preflight archive checks, creates
`t1-abba-r01`, `t2-abba-r01` and `t3-abba-r01` (fresh, no overwrite),
copies the original `four-way-build-r01` BIN8 converter into the
T2 snapshot, and submits for each feature:

1. 8-CPU build + correctness `smoke.slurm` on `cnall`.
2. Dependent 56-CPU `perf.slurm` with `afterok:<smoke_job>`.
   If smoke fails, the performance job is automatically canceled by
   `--kill-on-invalid-dep=yes`.

On success the helper prints `ALL_THREE_FEATURES_QUEUED=YES`.
It stores the returned JobIDs in `t1-abba-r01/job_ids.txt`, etc.

All performance jobs run four independent trials in balanced order
`base → tuned → tuned → base`, on one exclusive node, using 12
fixed queries, six concurrent JackHMMER processes with seven worker
threads each, plus main thread (=48 search threads), same
`WARMUP=1`, same search parameters and baseline ROC10 checks.

- T1 changes only `MSA_FASTA_ONEPASS` between 0 and 1.
- T2 changes only the `BIN8_CONVERTER` between an **immutable copy**
  of the four-format baseline binary and the newly batched writer.
  Both modes regenerate BIN8 from original FASTA in measured prologue.
- T3 changes only queue geometry: baseline (1000,2) vs tuned (256,4).
  This is a probe of *one* geometry, not evidence it is optimal.

Per-trial `prologue_s`, `search_s`, `total_s` and correctness checks
appear in each `summary.tsv`. Warmup is outside the scored
`search_s` (one full query each trial), and all four trials
use the same treatment. Actual Slurm elapsed time includes warmup.

**Preflight requirements:** user must have the existing
`~/WORK/dot/preliminary` dataset, old V1 hit tables, the known 12-query
selection, and the `four-way-build-r01/source/scripts/fasta_to_bin8`
reference converter from the successful four-format build.
The helper fails before scheduling if any tar or base converter is absent.

## Monitor

```bash
squeue -u "$USER"
for x in t1 t2 t3; do
  cat "$HOME/WORK/dot/experiments/supermsa/probes/$x-abba-r01/job_ids.txt"
done
```

If a smoke test fails, read its `smoke.<jobid>.out` and relevant
`source/*.log`. The dependent performance job **must not** be
submitted without a passing smoke test.

The script does not inspect, cancel, or modify the existing
`msa_4formats` job or any HPL benchmark.
