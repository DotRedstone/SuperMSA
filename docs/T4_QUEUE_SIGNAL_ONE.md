# T4 — Wake exactly one waiting worker per sequence block

## Why this candidate exists

`esl_workqueue_ReaderUpdate()` publishes one buffer under the queue mutex,
then uses `pthread_cond_broadcast()` if any Worker is waiting. Broadcasting
can wake multiple blocked threads although only one new item exists. Those
threads compete for the same mutex; most go back to sleep. This is a concrete
producer/consumer contention hypothesis, not a demonstrated bottleneck.

## Isolated mechanism

The default code path and all other queue operations remain unchanged.
Set `MSA_WQ_SIGNAL_ONE=1` before launching `jackhmmer` to replace that one
broadcast with `pthread_cond_signal()`. The mode is cached at queue creation.
No sequence data, scoring algorithm, parallel-worker count or output thresholds
are changed. The reader can still publish multiple blocks, signaling once
per newly published item. Shutdown uses one end-of-work block per worker.

## Correctness and performance gates

Run on a test/compute node:

```bash
bash scripts/build_bin8_candidate.sh
python3 tests/test_compare_hit_tables.py
bash tests/test_queue_signal_one.sh
```

The smoke compares default and signal-one hit tables and Stockholm alignments
over two worker counts (2,6), one/three iterations and three fresh repetitions;
each process has a 120-second timeout to detect likely deadlocks.

Formal pilot: `job_queue_signal_smoke.slurm` (8 CPUs) then
`job_queue_signal_perf.slurm` (56 CPUs) with `afterok` dependency.
`scripts/run_queue_signal_abba.sh` performs **base → tuned → tuned → base**
on 12 fixed queries and 6 concurrent searches. It checks target identity,
bounded score/bias/E-value drift, ranking constraints, ROC10, and paired
output against the first base, then records prep/search/total.

**Status:** GitHub-only candidate. Not yet compiled/tested on the HPC nodes;
no speedup claimed. Do not merge into T1/T2/T3 or any current r02 snapshot.

## Deployment, fish local → login-node Bash

```fish
cd ~/Projects/SuperMSA
git fetch origin
git archive --format=tar -o /tmp/supermsa-t4.tar origin/perf/queue-signal-one-t4
rsync -avP /tmp/supermsa-t4.tar \
  thuscc26team39@192.168.11.1:/home/thuscc26team39/WORK/dot/experiments/supermsa/probes/
```

On `ibcln01` use a **fresh immutable directory** and submit two jobs:

```bash
ROOT="$HOME/WORK/dot/experiments/supermsa/probes"
RUN="$ROOT/t4-abba-r01"
test ! -e "$RUN" || { echo "T4 directory exists; refusing overwrite"; exit 1; }
mkdir -p "$RUN/source"
tar -xf "$ROOT/supermsa-t4.tar" -C "$RUN/source"
cp "$RUN/source/job_queue_signal_smoke.slurm" "$RUN/smoke.slurm"
cp "$RUN/source/job_queue_signal_perf.slurm" "$RUN/perf.slurm"
cd "$RUN"
smoke=$(sbatch --parsable smoke.slurm)
smoke="${smoke%%;*}"
perf=$(sbatch --parsable --dependency="afterok:$smoke" --kill-on-invalid-dep=yes perf.slurm)
perf="${perf%%;*}"
printf 'smoke_job=%s\nperf_job=%s\n' "$smoke" "$perf" | tee job_ids.txt
```

Do not schedule T4 if a previous T4 snapshot is already running.
Time spent in warmup is omitted from `search_s` but counted in Slurm elapsed.
