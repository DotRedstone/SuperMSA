#!/usr/bin/env python3
"""Combine existing raw/BIN8 and new Huffman/DSQDATA sweep summaries.
No fabricated performance data. Does not claim cross-job samples are paired.
Usage: report_four_formats.py OLD_BIN8_SUMMARY NEW_FORMATS_SUMMARY
"""
import csv
import statistics
import sys
from collections import defaultdict
from pathlib import Path

def load(path, accept, groups):
    with Path(path).open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    if not rows:
        raise ValueError(f"no completed trials: {path}")
    for row in rows:
        mode = row["mode"].strip()
        if mode not in accept:
            raise ValueError(f"unexpected mode {mode!r} in {path}")
        if row["queries_run"].strip() != "12" or row["skipped"].strip() != "0":
            raise ValueError(f"invalid query count/skip in {path}, trial {row['trial']}")
        if row["quality"].strip() != "PASS" or row["identical_v1"].strip() != "YES":
            raise ValueError(f"correctness not proven in {path}, trial {row['trial']}")
        trial = {
            "prep": float(row["prologue_s"]),
            "search": float(row["search_s"]),
            "total": float(row["total_s"]),
            "bytes": int(row["encoded_bytes"]),
        }
        if not all(0 <= trial[k] < 1_000_000 for k in ["prep", "search", "total"]):
            raise ValueError(f"invalid timing value in {path}")
        if abs(trial["prep"] + trial["search"] - trial["total"]) > 0.25:
            raise ValueError(f"timing columns inconsistent in {path}")
        groups[mode].append(trial)

def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: report_four_formats.py bin8-summary.tsv new-summary.tsv")
    groups = defaultdict(list)
    load(sys.argv[1], {"raw", "bin8"}, groups)
    load(sys.argv[2], {"huff", "dsq"}, groups)
    for mode in ("raw", "bin8", "huff", "dsq"):
        if len(groups[mode]) != 2:
            raise ValueError(f"expected 2 complete samples for {mode}, got {len(groups[mode])}")
    raw = statistics.mean(x["total"] for x in groups["raw"])
    print("mode      trials   prep_mean_s   search_mean_s   total_mean_s   vs_raw_pct   encoded_bytes")
    for mode in ("raw", "bin8", "dsq", "huff"):
        rows = groups[mode]
        mean = lambda field: statistics.mean(x[field] for x in rows)
        size = round(mean("bytes"))
        print(f"{mode:<9} {len(rows):>4}     {mean('prep'):>9.2f}       "
              f"{mean('search'):>9.2f}      {mean('total'):>9.2f}       "
              f"{(raw-mean('total'))/raw*100:>+8.2f}%   "
              f"{size if mode != 'raw' else 'original FASTA'}")
    print("\nNOTE: Correctness was compared with the same V1 outputs. Timing samples")
    print("come from two separate Slurm jobs, not a fully paired 4-way benchmark.")
    print("Verify same query list, CPU configuration and comparable hardware.")
    print("For close candidates, rerun all four interleaved on the same node.")
if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError) as exc:
        raise SystemExit(f"ERROR: {exc}") from exc
