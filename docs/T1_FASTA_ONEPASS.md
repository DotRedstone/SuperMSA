# T1 — FASTA single-pass digital parser

**Status: experimental, opt-in, not compiled or benchmarked on the HPC cluster yet.**
This branch starts from `perf/db-four-way` and must remain separate from the
ongoing eight-trial comparison.

## Change

`easel/esl_sqio_ascii.c` now contains `fasta_readbuf_onepass()`,
which combines validation, ASCII-to-Easel digital mapping, residue
counting, and line/SSI bookkeeping in **one scan** of each buffer.

Activation: `MSA_FASTA_ONEPASS=1`.

It applies only to ordinary FASTA in digital `sqascii_Read()`, which
is also used by normal threaded FASTA `sqascii_ReadBlock()`. Other
Easel formats and `ReadInfo/ReadWindow/ReadSequence` keep their
existing paths. The default, with no environment variable, is exactly
the original two-pass `seebuf()+addbuf()` pipeline.

No database conversion or new format is involved. Error handling,
EOD/EOF, CRLF, whitespace, line counts, record offsets and
output ordering must match the original parser.

## Build and correctness test (test01 only)

Make a fresh checkout/archive of `perf/fasta-onepass-t1` under
`probes/t1-build-r01/source`, independently of the running four-format
Slurm job. Load GCC v12.2.0, then:

```bash
cd ~/WORK/dot/experiments/supermsa/probes/t1-build-r01/source
bash scripts/build_bin8_candidate.sh
bash tests/test_fasta_onepass.sh
```

Require both `BIN8_BUILD_AND_SMOKE=PASS` and
`FASTA_ONEPASS_SMOKE=PASS`. The test compares *every digitized
residue* of 15,177 toy records by byte-for-byte BIN8 conversion,
compares raw FASTA hit rows and MSA in single/threaded and 1/3
iteration modes, and verifies illegal input rejection.

## Profiling experiment

Use independent trial directories; do not overwrite historical results.
For a fair A/B comparison from raw FASTA, keep
`CPU/PARALLEL/ITERS/WARMUP` identical and change only:

- A: `env -u MSA_FASTA_ONEPASS`
- B: `MSA_FASTA_ONEPASS=1`

Check prologue=0, per-query ROC10, exact hit tables, and official
`wall_time.tsv`. Profile `seebuf`, `addbuf`,
`fasta_readbuf_onepass` to confirm that the new path is actually used.
If total search time does not improve on multiple repeated runs,
do not merge this experimental branch.
