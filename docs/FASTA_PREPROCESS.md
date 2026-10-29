# Timed FASTA preprocessing experiment

## What is and is not allowed

`prologue.sh` is the official preprocessing hook. It must **read the original
`preliminary/database.fasta` during the timed Slurm job**, produce its
intermediate under `~/WORK`, and report `prologue time = ...`. The total
performance metric is **prologue time + search time**. A prepared artifact
created before the job is not valid.

The existing README prohibits exploiting sequence IDs, annotations, SCOP
labels, or the `annotated_` prefix to choose, reorder, or omit targets.
This experiment retains **every input record in its original order**, preserves
each header verbatim apart from CRLF newline normalization, and preserves
all non-line-ending sequence bytes. No labels are read or interpreted.

## Why this first prototype is conservative

The measured P59819_1 `perf cycles:u` sample had ~24.8% in
`addbuf`, ~14.95% in `seebuf`, ~11.10% in `header_fasta`. These
are CPU-cycle percentages for **one query**, not known end-to-end time fractions.
Easel's parser scans sequence text and digitizes into `ESL_DSQ`.
Simply unwrapping FASTA does not remove digitization or header parsing,
so a substantial speedup is **not** guaranteed.

A more ambitious follow-up is to use the native `easel/esl_dsqdata.[ch]`
pre-digitized binary format, which provides `esl_dsqdata_Write()`,
`esl_dsqdata_Open()`, `esl_dsqdata_Read()`, but currently `jackhmmer.c`
reads its database via `esl_sqfile_OpenDigital()`, so integrating DSQDATA
requires real C changes to the search data path and repeated-iteration handling.
Do not merely write binary files in prologue and call it optimized.

## How the prototype works

- `scripts/fasta_rewrap.c` converts sequence lines to one line/record,
  retaining their order and bytes (except CRLF line endings).
- `prologue.sh` has `FASTA_PREPROCESS=1` opt-in and creates
  `$OUT/prepared/database.fasta` **during** the prologue timer.
- `run_queries.sh` uses prepared FASTA iff `FASTA_PREPROCESS=1`,
  otherwise the original raw database. It fails if the requested prepared
  file is absent.
- The reference V1 binary and quality-scoring code stay unchanged.

### Build on test01

```bash
module load compilers/gcc/v12.2.0
cd ~/WORK/dot/SuperMSA
gcc -O3 -std=c99 -Wall -Wextra -o scripts/fasta_rewrap scripts/fasta_rewrap.c
bash tests/test_fasta_rewrap.sh
```

The `scripts/fasta_rewrap` binary is **code**, not preprocessed dataset
content. Building it before the benchmark is allowed; the data conversion
must occur during the timed prologue.

### 12-query comparison

Prepare a clean `~/WORK/dot/experiments/supermsa/probes/fasta-preprocess-r01`
run directory. Snapshot:

- `prologue.sh`, `run_queries.sh`, `score.py`
- `scripts/query_worker.sh`, `scripts/fasta_rewrap`
- `scripts/run_fasta_preprocess_sweep.sh`
- Original V1 `src/jackhmmer` binary from
  `experiments/supermsa/runs/query-parallel-p6-t8-r01/source/src/jackhmmer`.
- Job script `job_fasta_preprocess_sweep.slurm`.

Submit the job script from the new run directory with `sbatch`.
It runs raw / rewrap / rewrap / raw, each with 12 official query IDs,
6 processes x 8 threads, 1 warm-up per trial. The comparison script
creates fresh outputs and verifies 12/12 ROC10 correctness and full
hit-row equality to V1.

Read `summary.tsv` (prologue, search and **total** times). Compare repeated
paired times. A 12-query result is for screening only; even a 12-query net
win is not proof of a 100-query win.

### Kill conditions

- Missing or corrupted database, query, or converter: stop.
- Any query output/ROC10 mismatch vs V1: stop.
- Converter cost exceeds search savings even after a plausible 100-query
  amortization: deprioritize this approach.
- Never reuse preprocessed files from older runs for a scored benchmark.

### Next deeper design

Native binary DSQDATA is a candidate for eliminating **repeated text
parsing**, as opposed to line rewrapping. It will need its own feature branch,
dedicated query/search reader integration, a correctness suite and measured
end-to-end comparison. It is intentionally **not** bundled into this low-risk
experiment.
