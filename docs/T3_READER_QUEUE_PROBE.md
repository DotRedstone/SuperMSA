# T3 — Reader/Worker scheduling probe and queue geometry

**Status: experimental instrumentation and tunable geometry only.**
No claim yet that the reader is a proven bottleneck.

## Opt-in control knobs

In `src/jackhmmer.c`, with the original behavior preserved when the
variables are unset:

- `MSA_BLOCK_SEQS` (default 1000, permitted 128..4096): number of
  sequences allocated in each `ESL_SQ_BLOCK`.
- `MSA_QUEUE_FACTOR` (default 2, permitted 2..8): queue block count =
  search workers × factor, affecting prefetched work buffers.
- `MSA_QUEUE_CONFIG_LOG=1`: emit actual configuration to stderr.

No additional loader thread is created; the same Reader and
Worker threads use the existing Easel work queue. For native
DSQDATA, loader/unpacker threads remain separately budgeted.

`scripts/probe_worker_stalls.py` can sample Linux scheduler states and
`/proc/PID/task/TID/wchan` for a child JackHMMER process, without
requiring privileged perf events. Sampling thread states is **not
a direct measurement of idle time due to an empty work queue**:
threads may sleep on barriers, locks or other synchronization.

## Build/test (test01)

Use a fresh `perf/reader-queue-t3` checkout under
`probes/t3-build-r01/source`.

```bash
cd ~/WORK/dot/experiments/supermsa/probes/t3-build-r01/source
bash scripts/build_bin8_candidate.sh
bash tests/test_queue_geometry.sh
```

Require `QUEUE_GEOMETRY_SMOKE=PASS`: raw FASTA outputs and MSA must
match exactly across multiple block sizes, queue depths and 1/3
iterations.

## Preliminary stall probe (toy data only)

```bash
MSA_QUEUE_CONFIG_LOG=1 MSA_BLOCK_SEQS=256 MSA_QUEUE_FACTOR=4 \
  python3 scripts/probe_worker_stalls.py /tmp/msa-t3-wchan.tsv -- \
  ./src/jackhmmer --cpu 2 -N 3 --noali -o /dev/null \
  data/query.fasta data/demodb.fasta
```

Use the report to identify suspicious persistent waiting channels,
then confirm with proper timing or `perf sched` where permitted.
Do not increase Reader parallelism until profiling demonstrates
workers are frequently blocked on data supply.

For comparative performance on the official 12-query workload,
retain the same 56-CPU node, allocation, 6 query processes,
and *total* worker count; vary one parameter at a time.
Never change the in-flight four-format Slurm snapshot.
