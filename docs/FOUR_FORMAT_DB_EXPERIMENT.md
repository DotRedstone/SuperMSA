# Four-format database experiment — incremental second batch

**Status: code committed, not compiled or run on the cluster yet.** Preserve
`release/v1-query-parallel-p6t8` and the already-running/completed
`bin8-sweep-r01` snapshot. Do not merge this research branch until the
independent correctness gates and full benchmark are satisfied.

## Formats

| Mode | Input format | Preprocessing charged to prologue | Runtime target reader |
|---|---|---|---|
| raw | original FASTA | none | Easel sqio text parser |
| bin8 | 8-bit digital records | Easel digital conversion | mmap / copy |
| dsq | Easel native DSQDATA (5-bit protein) | `esl_dsqdata_Write()` | `esl_dsqdata_Open/Read/Recycle/Close` |
| huff | canonical Huffman compressed digital residues | FASTA→BIN8→Huffman (all timed) | mmap / Huffman decode |

No sequence or annotation label is used to filter, rank, skip, or
reorder targets. Native DSQDATA includes four files:
`database`, `database.dsqi`, `database.dsqm`, `database.dsqs`.
All four and all compiler outputs must be in `~/WORK`.
The prologue reads raw `preliminary/database.fasta` every trial.
Native DSQDATA packing is upstream Easel code, not a newly invented algorithm.

## 1. Build and test independently on test01

Transfer a **new archive of branch `perf/db-four-way`** into a
new source checkout, e.g.:
`~/WORK/dot/experiments/supermsa/probes/four-way-build-r01/source`.
Do not overwrite the existing BIN8 snapshot or its live Slurm job.

```bash
module load compilers/gcc/v12.2.0
cd ~/WORK/dot/experiments/supermsa/probes/four-way-build-r01/source
bash -n scripts/build_four_way_candidate.sh
bash scripts/build_four_way_candidate.sh
```

The build script builds JackHMMER, the 8-bit converter, Huffman encoder
and verifier, the DSQDATA native converter and verifier. It checks
the 15,177-record toy database against raw, BIN8, Huffman, and DSQDATA.

Required exit markers:
`BIN8_BUILD_AND_SMOKE=PASS`,
`HUFFMAN_BUILD_AND_SMOKE=PASS`,
`DSQDATA_EXACT_ROUNDTRIP=PASS`,
`NEW_FORMATS_TOY_SMOKE=PASS`,
`FOUR_WAY_BUILD_AND_SMOKE=PASS`.
The exact record/residue counts are printed by the tests.

Tests cover --cpu 0 / --cpu 2, -N 1 / -N 3, noncomment hit tables,
Stockholm MSA, and whole-file sequence/metadata identity.
Native DSQDATA writer may reject extraordinarily long individual
sequences (upstream limitation); never silently omit those records.

If a test fails, inspect:
`bin8.make.log`, `huffman.converter-build.log`,
`dsqdata.writer-build.log`, `dsqdata.verifier-build.log`,
`dsqdata.smoke.log` or `huffman.smoke.log`.
**Do not submit performance jobs if smoke validation fails.**

## 2. Run only the two missing formats

After correctness passes, on login node create an isolated Slurm snapshot:

```bash
ROOT="$HOME/WORK/dot/experiments/supermsa/probes"
BUILD="$ROOT/four-way-build-r01/source"
RUN="$ROOT/new-formats-sweep-r01"

test -f "$BUILD/four_way.binaries.sha256" || exit 1
mkdir "$RUN"
cp -a "$BUILD" "$RUN/source"
cp "$RUN/source/job_new_formats_sweep.slurm" "$RUN/job.slurm"
cd "$RUN"
sbatch job.slurm
```

Four trials use balanced order `huff → dsq → dsq → huff`.
All four use 12 queries, 6×8 parallelism, 3 JackHMMER iterations,
one warmup query (excluded from search wall time) and one dedicated
56-CPU Slurm allocation. Each trial regenerates its entire database
from original FASTA during the **scored prologue**. Evaluation requires
12/12 score criteria and exact V1 noncomment hit-table rows.
The result is `new-formats-sweep-r01/summary.tsv`.

The script defaults to the same 12 Query list and V1 hit-table directory
as the BIN8 benchmark. If those paths differ, override the environment
variables `BENCH_QUERY_LIST` or `BENCH_BASELINE_TBL` for the submission.
Verify that both batches used precisely the same query list.

## 3. Compare all four in one report

```bash
ROOT="$HOME/WORK/dot/experiments/supermsa/probes"
python3 "$ROOT/new-formats-sweep-r01/source/scripts/report_four_formats.py" \
  "$ROOT/bin8-sweep-r01/summary.tsv" \
  "$ROOT/new-formats-sweep-r01/summary.tsv"
```

The script refuses missing/incomplete/wrong-mode/incorrect samples and
prints prep, search and total means for all four formats, with change
relative to original FASTA.

**Statistical caveat:** this report combines two separate Slurm jobs,
not a four-format paired measurement. It is a useful first-stage
screening, not proof that a 1% or 2% improvement is real. For close
candidates, run an **interleaved four-format benchmark on the same node**
before making an official final comparison. Results on 12 queries also
do not establish 100-query performance.

## 2026-10-29: DSQDATA toy smoke deadlock and fix

The first `--cpu 0 -N 1` DSQDATA search passed no further output
for more than five minutes, with three sleeping threads (main, loader,
unpacker). The native converter, full 15,177-record exact-roundtrip
check, BIN8, and Huffman checks had already passed.

Root cause identified in the JackHMMER adapter: after every iteration
JackHMMER rewinds its target database, and after every query it rewinds
again. Our original DSQDATA implementation did a **close + immediate
asynchronous reopen** at the first rewind. The second rewind then
called `esl_dsqdata_Close()` on a reader whose prefetch chunks had
never been consumed or recycled; Easel's close joins a loader that
waits for all outstanding chunks to be recycled. This can deadlock.

The corrected reader creates its async pipeline **lazily on first
target read**, and `msa_dsq_rewind()` only closes the fully consumed
reader. If already closed, rewind is a no-op; the next actual read
opens a fresh reader. `jackhmmer.c` tests the logical active
basename, not whether an async reader object is currently open.
The smoke script uses `MSA_DSQ_UNPACKERS=1` (the official comparison's
budget) and enforces a 120-second timeout per toy search. The code
change must be rebuilt and rerun on test01; it is not automatically
applied to copies already uploaded to the cluster.

## Design limitations

The DSQDATA bridge copies each unpacked sequence into a JackHMMER
owned `ESL_SQ`; it avoids repeated ASCII parsing but adds conversion
and multiple decode threads. Every iteration closes and reopens
Easel's asynchronous packed reader because that API does not expose
a seek-to-start method. This reopening cost is included in measured
search time and may reduce gains. The code does not change scoring,
filtering, query input, or sequence processing order.

Huffman is exactly reversible but its bit-by-bit branching may
be slower than 5-bit fixed decoding. Compare **prologue + search**
rather than only compressed file size.


## Preferred plan when the old BIN8 Slurm job has not started

If `squeue` reports `msa_bin8` as `PD`, cancel **only that one
job ID** and run one same-node comparison across all four formats:

```bash
scancel 16167899
```

This job ID was observed pending on 2026-10-29; confirm `squeue`
before executing, and never cancel the independent HPL array.

**Important: the four-format benchmark replaces rather than combines
the two older batch-specific scripts.** The original
`run_new_formats_sweep.sh` remains in GitHub for earlier experiment
history but should not be used for the new fair run.

### Thread budget (fixed by the new run script)

The earlier prototype assigned 8 search workers to each of six
JackHMMER processes and allowed native DSQDATA to create 1 loader + 4
unpackers per process. Including the main search-thread reader, this
could reach approximately `6 * (8 + 1 + 1 + 4) = 84` JackHMMER
threads; counting only workers+DSQDATA I/O gives `78`. This is
unfair when a node allocation has only 56 logical CPUs.

The experimental Easel API `esl_dsqdata_OpenWithUnpackers()` preserves
the original `esl_dsqdata_Open()` default but permits 1..4 unpackers.
The integration uses `MSA_DSQ_UNPACKERS=1` by default and reuses the
same worker count when it reopens the reader each iteration.

The preferred new configuration targets **48 threads** per phase:

| Format | Query processes | Search workers / process | Main / process | Loader / process | Unpackers / process | Total |
|---|---:|---:|---:|---:|---:|---:|
| raw | 6 | 7 | 1 | 0 | 0 | 48 |
| bin8 | 6 | 7 | 1 | 0 | 0 | 48 |
| huff | 6 | 7 | 1 | 0 | 0 | 48 |
| dsq | 6 | 5 | 1 | 1 | 1 | 48 |

This leaves 8 CPUs in the 56-CPU Slurm allocation for xargs, shells,
Python sampling, and operating-system activity. This is **equal
overall thread budget**, not identical search-worker counts.
DSQDATA makes a deliberate trade: 2 search workers for 2 background
I/O/decoding threads. The `/proc/<pid>/task` sampler runs every
second and records `*.threads.tsv` per trial, as well as peak
processes and thread count in the overall summary. Sampling may
underestimate short thread spikes; it is an observability check, not
a hard-enforced cgroup guarantee.

### One-node, eight-trial experimental batch

After **`FOUR_WAY_BUILD_AND_SMOKE=PASS`** on `ibtest01`, use a
fresh snapshot from this **updated** branch:

```bash
ROOT="$HOME/WORK/dot/experiments/supermsa/probes"
BUILD="$ROOT/four-way-build-r01/source"
RUN="$ROOT/four-formats-sweep-r01"
test -s "$BUILD/four_way.binaries.sha256" || exit 1
test -s "$BUILD/scripts/run_four_formats_sweep.sh" || exit 1
test ! -e "$RUN" || exit 1
mkdir "$RUN"
cp -a "$BUILD" "$RUN/source"
cp "$RUN/source/job_four_formats_sweep.slurm" "$RUN/job.slurm"
cd "$RUN"
bash -n job.slurm
bash -n source/scripts/run_four_formats_sweep.sh
sbatch job.slurm
```

Balanced order, with two complete trials per format:
`raw, bin8, dsq, huff, huff, dsq, bin8, raw`.

In all trials, prologue begins with the original FASTA; the full
cost of digital conversion/compression is in the scored
`prologue_s`. For correctness every query is compared to v1's
original noncomment hit-table rows. No prior trial's prepared
database or results are reused.

Output:

```bash
cat "$RUN/summary.tsv"
python3 "$RUN/source/scripts/report_interleaved_formats.py" "$RUN/summary.tsv"
```

End marker: `ALL_EIGHT_FOUR_FORMAT_TRIALS_COMPLETED=YES`.

**Do not append these measurements to the old p6-t8 baseline as
identical configuration**: raw, bin8, and huff use p6-t7 here;
DSQDATA uses p6-t5 + native unpacking. The entire new experiment
holds the total thread budget constant. Any promising candidate
should also be measured on the 100-query official workload.
