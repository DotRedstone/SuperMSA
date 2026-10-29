# T1/T2/T3 — 12-query ABBA r02 results (2026-10-29)

## Provenance and scope

These results are transcribed from the operator's `ibcln01` terminal
`sacct -X` and `summary.tsv` output. Source of truth remains the immutable
`$HOME/WORK/dot/experiments/supermsa/probes/{t1,t2,t3}-abba-r02/`
job artifacts; the repository copy is a convenience summary, not a forged
official log. Raw trial values are preserved in
`docs/data/T1_T2_T3_ABBA_R02_2026-10-29.tsv`.

| Candidate | Slurm JobID | Node | State | Elapsed | Exit | 4/4 trial completion |
|---|---:|---|---|---|---|---|
| T1 | 16170657 | ibc11b04n19 | COMPLETED | 00:52:58 | 0:0 | YES |
| T2 | 16170658 | ibc11b07n15 | COMPLETED | 00:42:29 | 0:0 | YES |
| T3 | 16170659 | ibc11b04n11 | COMPLETED | 00:53:19 | 0:0 | YES |

All 12 queries in every trial passed the recorded ROC10 quality check
and the cross-build **tolerance-gated** historical V1 hit comparison.
`identical_v1=YES` is an existing experiment label; it does NOT mean
byte-identical output, and the scope is the selected 12 queries.

## Mean results (seconds; smaller is better)

| Feature | Base prep | Tuned prep | Base search | Tuned search | Base total | Tuned total | Saved total | Relative time reduction |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| T1 FASTA one-pass | 0.00 | 0.00 | 581.50 | 561.05 | 581.50 | 561.05 | **20.45** | **+3.517%** |
| T2 BIN8 writer batching | 75.05 | 74.95 | 479.90 | 478.50 | 554.95 | 553.45 | +1.50 | +0.270% |
| T3 256-block/4x queue | 0.00 | 0.00 | 569.60 | 572.65 | 569.60 | 572.65 | -3.05 | -0.535% |

Formula: `saved = mean(base1, base4) - mean(tuned2, tuned3)`;
`relative_time_reduction = saved / mean(base1, base4)`. These values
are time reductions, not the conventional speedup factor `base/tuned`.

## ABBA local consistency

| Feature | Base1 minus Tuned1 | Base4 minus Tuned2 | Base4 minus Base1 | Readout |
|---|---:|---:|---:|---|
| T1 | +18.4 s | +22.5 s | +3.6 s | Both paired comparisons improve; strong candidate for retention |
| T2 | -12.6 s | +15.6 s | +15.5 s | Opposite signs, strong run-to-run drift; **no demonstrated T2 win** |
| T3 | -3.2 s | -2.9 s | +5.0 s | Both tuned trials slower by ~0.5%; do not select this geometry |

The two pairings here are descriptive; `ABBA` is primarily intended to
balance time ordering and does not provide inferential statistical power
from just two observations per condition. For strict time-trend matching,
the equivalent linear-drift-corrected mean effect is the difference
of the two group means shown above. T2's 0.1 s apparent prep saving is
much smaller than observed preparation and search fluctuations.

## What to keep, and what NOT to conclude

1. **Keep T1** as the provisional best raw-FASTA path; revalidate against
   the competition's full 100-query workload. The zero-prep figures mean
   there was no separately timed conversion stage, NOT that FASTA reading
   itself is free; FASTA processing is inside `search_s`.
2. **Do not merge T2 writer batching as a claimed speedup.** This measures
   the effect of *batched BIN8 serialization* versus reference BIN8
   serialization; it does NOT measure BIN8 versus raw FASTA overall.
   Keep the BIN8 format implementation available for separate evaluation.
3. **Do not select T3's 256-sequence/4x queue configuration** based on
   this run. Other geometries would require fresh, independent tests.
4. T1 and T2/T3 were on different nodes and use different data paths;
   DO NOT compare their mean times across separate Slurm jobs as a
   randomized direct head-to-head measurement.
5. T1 is an optimized ordinary FASTA digital reader. BIN8 bypasses
   the ordinary FASTA reader during its search; do not assume T1 and
   BIN8 format throughput improvements add together.
6. T4 single-worker wakeup and T5 profiling are separate independent
   candidates and remain **unvalidated on the cluster** until tests
   and Slurm logs say otherwise. T5 is a diagnostic, never official score.

## Next experiment

After T4/T5 smoke tests succeed, choose between the T1 raw FASTA path
and BIN8/huffman/DSQDATA via a fresh same-node ABBA comparison of
**complete prologue + search**, ideally both representative 12-query
and full 100-query runs. Preserve data-integrity checks and the
official scoring window, and record each candidate's immutable commit
and binary hashes. No unverified feature branch is merged here.
