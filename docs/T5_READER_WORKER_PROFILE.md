# T5 — Opt-in Reader/Worker timing and accounting

## Mechanism

This branch changes only `src/jackhmmer.c`, based on the unmodified
`perf/db-four-way` snapshot. No queue scheduling or algorithmic logic
is changed. The default environment does not measure or log anything.

Setting `MSA_RW_PROFILE=1` makes each threaded search iteration print
machine-parseable `MSA_RW_PROFILE` rows on stderr. One Reader row reports
reading/decode time, queue handoff/wait time, block count, sequences,
and residues. A row per Worker reports time inside queue's `WorkerUpdate`
(includes synchronization AND waiting, not pure stall time), time
processing sequence blocks (includes pipeline setup/reuse), block
count, sequences and residues. Each worker writes only its own counters.
Main thread prints after joining all workers.

All durations use `gettimeofday` (wall clock, not CPU time or monotonic
performance cycles). Each worker's compute/wait seconds must NOT be
added directly to the Reader elapsed seconds: workers run concurrently.
Timing calls are per block, not per residue. Even with profiling
enabled, measurement overhead must be evaluated experimentally.

## Test and evaluation

Test on a compute node (not on ibcln01):

```bash
bash scripts/build_bin8_candidate.sh
bash tests/test_reader_worker_profile.sh
```

Smoke checks no `MSA_RW_PROFILE` output when disabled, verifies exact
hit rows and Stockholm output with profiling on/off at 2/6 workers,
one/three iterations, and uses `check_reader_worker_profile.py` to
assert per-round Reader counts equal the sum over all Workers.

For full-database signal, `job_reader_profile_smoke.slurm` (8 CPUs)
followed by dependent `job_reader_profile_probe.slurm` (8 CPUs)
runs `Q9CIV7_1` against the original FASTA with seven workers,
then repeats with profiling enabled, comparing the result exactly.
Per-iteration timing data is written in `probe/timing-summary.txt`.

**Status:** repository candidate only; not compiled on HPC yet.
No stall or bottleneck claim until we inspect the profile numbers.
No existing T1/T2/T3/T4 result or submitted source snapshot is modified.

## Manual Slurm setup

Local fish shell:

```fish
cd ~/Projects/SuperMSA
git fetch origin
git archive --format=tar -o /tmp/supermsa-t5.tar origin/perf/reader-worker-profile-t5
rsync -avP /tmp/supermsa-t5.tar \
  thuscc26team39@192.168.11.1:/home/thuscc26team39/WORK/dot/experiments/supermsa/probes/
```

Login node Bash:

```bash
ROOT="$HOME/WORK/dot/experiments/supermsa/probes"
RUN="$ROOT/t5-profile-r01"
test ! -e "$RUN" || { echo "T5 directory exists; refusing overwrite"; exit 1; }
mkdir -p "$RUN/source"
tar -xf "$ROOT/supermsa-t5.tar" -C "$RUN/source"
cp "$RUN/source/job_reader_profile_smoke.slurm" "$RUN/smoke.slurm"
cp "$RUN/source/job_reader_profile_probe.slurm" "$RUN/probe.slurm"
cd "$RUN"
smoke=$(sbatch --parsable smoke.slurm)
smoke="${smoke%%;*}"
probe=$(sbatch --parsable --dependency="afterok:$smoke" --kill-on-invalid-dep=yes probe.slurm)
probe="${probe%%;*}"
printf 'smoke_job=%s\nprobe_job=%s\n' "$smoke" "$probe" | tee job_ids.txt
```

## THUSCC26 competition timing compliance — development-only

THUSCC26 SuperMSA official scoring is `prologue time + search time` for all
100 queries; one-off preprocessing belongs to prologue, and only the
specified warmup is excluded. Submitted stdout must be the complete
unaltered log from one run. References:

- https://lab.cs.tsinghua.edu.cn/scc/Applications/SuperMSA/
- https://lab.cs.tsinghua.edu.cn/scc/

**T5 is never a score submission.** `job_reader_profile_probe.slurm`
runs one query twice solely for diagnostics. It is not a full 100-query
competition job and must not be sent to the scoring server. The internal
`gettimeofday` instrumentation only reports read, queue, and worker
subcomponent durations to stderr; it must never replace or subtract from
`prologue time` or `search time`, shift startup/preprocessing outside the
measured interval, or retroactively modify submitted logs.

Measured profiling overhead is part of elapsed wall time whenever profiling
is enabled. For competitive timing use the uninstrumented performance
build/branch (preferred), not a profiled run. Keep this T5 branch separate
from the final scoring branch and document that profiling was used only
during development. The no-profiling default is not a substitute for
rebuilding the final submission from audited sources.
