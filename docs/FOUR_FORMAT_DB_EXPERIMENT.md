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
