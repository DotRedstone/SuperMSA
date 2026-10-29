# T2 — BIN8 writer batching

**Status: experimental; not yet rebuilt on the HPC cluster.**
Forked independently from `perf/db-four-way` so that the in-flight
four-format study retains its exact already-tested binary.

## Change

The file `scripts/fasta_to_bin8.c` now preallocates one reusable
metadata header buffer, writes the five original little-endian u32
fields together with the three metadata strings in one `fwrite()`,
and writes the original Easel digital residues with a second
`fwrite()`. The `FILE*` uses an optional 1 MiB libc stdio buffer
(fallback to the default if `setvbuf` refuses). The wire-format
remains **exactly MSA8DB01**. No target filtering, sorting,
index reshuffling, or lossy mapping.

This is a safe, local optimization of serialisation/syscall overhead,
**not** a demonstrated reduction in the 72.5s conversion time;
the remaining major cost may be Easel's original FASTA text parser.

## Build and test (test01)

Use a new directory `probes/t2-build-r01/source` containing an
archive of `perf/bin8-batched-io-t2`:

```bash
cd ~/WORK/dot/experiments/supermsa/probes/t2-build-r01/source
bash scripts/build_huffman_candidate.sh
bash tests/test_bin8_batched_io.sh
```

Require `HUFFMAN_BUILD_AND_SMOKE=PASS` and
`BIN8_BATCHED_IO_SMOKE=PASS`. For the strongest test, point
`BIN8_REFERENCE_CONVERTER` to the old four-format snapshot's
`scripts/fasta_to_bin8`; the smoke script then compares full BIN8
output byte-for-byte in addition to testing exact query hits and MSAs:

```bash
BIN8_REFERENCE_CONVERTER="$HOME/WORK/dot/experiments/supermsa/probes/four-way-build-r01/source/scripts/fasta_to_bin8" \
  bash tests/test_bin8_batched_io.sh
```

Run independent timed prologues from original FASTA and measure
`T_prepare` and `T_search` separately. If only `T_prepare` improves,
end-to-end improvement may still be small; do not report speedups
from compression ratio or file size.
