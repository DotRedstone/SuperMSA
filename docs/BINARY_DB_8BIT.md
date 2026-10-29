# 8-bit digital database: first end-to-end prototype

**State:** implementation committed; NOT YET compiled on the cluster and NOT benchmarked.
Never merge this branch into the submitted 6×8 baseline until correctness
and independent full-run evaluation pass.

## Why

P59819_1 profile found FASTA processing hotspots
`addbuf` (~24.8%), `seebuf` (~14.95%), `header_fasta` (~11.10%)
of user-space CPU cycle samples. Rewrapping FASTA on 12 queries cost
~34.7 s to prepare and yielded almost no search benefit; total time rose
from 552.45 s (raw) to 585.40 s (rewrap). SSV band sweep (8/10/12/14)
did not show reliable improvement.

Unlike rewrapping, this prototype **actually avoids repeated text
parsing of the target database**. The preprocessor calls Easel's own
digital FASTA reader, serializes all records in the original sequence
order, and preserves name/accession/description and taxid. No sequence
ID or annotation is used to filter or reorder any target.

## Implementation

- `scripts/fasta_to_bin8.c`: convert raw database FASTA into a
  little-endian, mmap-friendly 8-bit digital file.
- `src/msa_bin8.h`: mmap read-only digital database into each search
  process; fill Easel `ESL_SQ` / `ESL_SQ_BLOCK` objects. On Linux,
  the file-backed page cache can be shared by the six search processes;
  decoded output objects remain worker-private.
- `src/jackhmmer.c`: when `MSA_BIN8_DB` is set, replace only target
  reads / rewinds with the binary reader. Normal FASTA behavior is
  unchanged when the variable is absent. Query FASTA, iteration,
  search/scoring, worker scheduling, outputs remain unchanged.
- `prologue.sh`: `BIN8_PREPROCESS=1` opt-in, convert from original
  `$DATA/database.fasta` only within the measured `prepare()`.
  Output: `$OUT/prepared/database.bin8`.
- `run_queries.sh`: routes to the current run's artifact by exporting
  `MSA_BIN8_DB`. The `DB` CLI argument remains the original FASTA
  for result metadata. Fail closed if the artifact is absent.

The binary reader is currently **designed only for jackhmmer's non-MPI
serial/threaded search**, which is the configuration used by the
competition 6×8 run. No claim is made for MPI code paths.

It is a dedicated *experimental* format, not the upstream Easel DSQDATA
format. Once the uncompressed digital baseline is measured, next try
`esl_dsqdata` 5-bit packing in a separate branch; then consider Huffman
only if memory/I/O evidence warrants it.

## Format

Eight-byte signature `MSA8DB01`; then a stream of records. Each
record stores little-endian 32-bit lengths of name/acc/desc/digital
residues and a 32-bit taxid, followed by those four byte fields.
Exactly one digitized byte per residue, no sentinels stored on disk.
No labels or synthetic search answers are stored.

The writer and reader operate on the same node CPU architecture; the
binary representation remains an internal transient dataset, not an
external interchange standard.

## Build: on test01, inside an isolated source snapshot

The repository does not track generated `configure`; it is created by
`autoconf`. Required tools: gcc 12.2, make, autoconf, rsync, bash.

```bash
module load compilers/gcc/v12.2.0
cd ~/WORK/dot/experiments/supermsa/probes/bin8-build-r01/source
bash scripts/build_bin8_candidate.sh
```

The script runs `autoconf`, `./configure`, `make -j8`, builds
`fasta_to_bin8`, and runs
`tests/test_bin8_smoke.sh` on the *toy* database. It writes
`bin8.smoke.log`, `bin8.make.log`, and the binary hashes.

**Never create a binary from the competition's raw database before a
measured prologue**, even for convenience; this would invalidate
the end-to-end comparison.

## 12-query test on Slurm

After a successful smoke test, make a fresh copy of the built source
snapshot at `.../probes/bin8-sweep-r01/source`, copy the job script
to the new run's `job.slurm`, and submit:

```bash
cd ~/WORK/dot/experiments/supermsa/probes/bin8-sweep-r01
sbatch job.slurm
```

`scripts/run_bin8_sweep.sh` creates a 12-query dataset view from
`parallel-scan-20261028_230525/queries.txt` and runs:

| Trial | Data | Included time |
|---|---|---|
| 01 | raw | prologue + search |
| 02 | bin8 | timed conversion + search |
| 03 | bin8 | timed conversion + search |
| 04 | raw | prologue + search |

All trials use 6 concurrent JackHMMER searches, 8 threads/query,
3 iterations, and the same F1/F2/F3/E-value. Warm-up=1 per trial,
outside the recorded search time. Every binary target file is newly
generated from the original FASTA within its trial's timed prologue.
No output is reused.

Strict gates:
- 12 fresh queries / zero skipped;
- baseline ROC10 check on all 12;
- noncomment hit-table rows identical to 6×8 V1 on all 12;
- each trial identical to raw trial 01;
- compare **mean(prologue + search)**, not search alone.

Inspect `summary.tsv` and `bin8.<jobid>.out`. This is a screening
experiment; it does **not** establish correctness over all 100 queries
or stability across nodes.

## Open technical risks

1. Cannot prove ABI/build compatibility until built on test01.
2. Binary reader copies digital sequence residues into work queue
   objects; it avoids ASCII parsing but not copy/allocation cost.
3. Worker block sizes and cache access can change compared with
   Easel's FASTA reader, potentially changing load balance.
4. Mapped binary file may be larger than raw FASTA; disk, memory
   pressure and page-cache effects require measurement.
5. Preprocessing cost may outweigh savings for 12 queries, but
   amortization over 100 queries could differ.
6. A full 100-query correctness and throughput run is mandatory before
   any submission change.
