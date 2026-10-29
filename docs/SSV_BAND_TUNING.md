# SSV SIMD band-width experiment

## Motivation

The first `perf record -e cycles:u` on query P59819_1 (job 16167044)
showed `calc_band_12` at 38.62% self cycles, with `addbuf`,
`seebuf`, and `header_fasta` also substantial. Inside `calc_band_12`,
the hot instructions include SSE2 scoring operations, address calculation,
and some XMM stack loads/stores. Those stack accesses are *consistent with*
register spills, but are not proof that spills dominate runtime.

## Design

Keep the existing `MAX_BANDS` and all `calc_band_N` implementations.
Introduce `SSV_BAND_LIMIT` (compile-time default = `MAX_BANDS`).
The limit only changes how many score-vector stripes are processed per
pass in `get_xE()`. It must be between 1 and `MAX_BANDS`.

Do not change filter thresholds, score arithmetic, query selection,
or official evaluation. This is a performance experiment, not a proven
speedup.

Candidates: `SSV_BAND_LIMIT` = 14 (original), 12, 10, and 8.
Compile into **distinct** source/build directories, with identical
compiler settings, and retain the binaries and build logs.

The original `MAX_BANDS` value should not be changed directly:
the function pointer table conditionally includes groups of generated
functions for band widths 1..6, 7..14, and 15..18. Merely replacing
14 with 8 or 10 changes that table's size without changing its list
of initializers, causing compilation warnings and confusing the test.

## Correctness and comparison

1. Build each candidate on a test node (never on login node), using
   separate source copies under
   `~/WORK/dot/experiments/supermsa/probes/ssv-band-sweep-r01/`.
2. Smoke-test all binaries and compare the same 12 queries on the same
   allocated compute node. Prefer balanced or rotated ordering to reduce
   warm-cache/order effects.
3. Compare all non-comment hit-table data lines (and MSA results when
   possible) against `band14`; any discrepancy blocks promotion.
4. Re-test promising configurations with repeated runs, including
   different query lengths. `P59819_1` alone is not representative.
5. Only then schedule a new 100-query full benchmark, with an independent
   output directory and `incorrect=0/100` verification.

The original full 100-query result is **3518.5 s** (6×8, ROC10 0.7231,
0 incorrect). Keep its source and binary snapshots immutable. Sampling
costs are not comparable to ordinary benchmark runtime.

## Source

`src/impl_sse/ssvfilter.c`, function `get_xE()`, controls number of
band sweeps. `calc_band_N` functions are macro-generated and perform
saturated 8-bit SIMD subtraction and vector maximum.

This test does not prove a memory-bandwidth bottleneck. The CPU cycles
sample says nothing directly about disk wait time.
