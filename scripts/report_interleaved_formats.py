#!/usr/bin/env python3
"""Read one *same-node* eight-trial four-format summary.
Fail closed on correctness failures, inconsistent budgets, and missing trials.
Usage: report_interleaved_formats.py path/to/summary.tsv
"""
import csv
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

MODES = ("raw", "bin8", "dsq", "huff")
EXPECTED = ["raw", "bin8", "dsq", "huff", "huff", "dsq", "bin8", "raw"]


def main() -> None:
    if len(sys.argv) != 2:
        raise ValueError("usage: report_interleaved_formats.py summary.tsv")
    path = Path(sys.argv[1])
    with path.open(encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    if [row.get("mode", "") for row in rows] != EXPECTED:
        raise ValueError("missing trials or changed balanced order")
    per_mode: dict[str, list[dict[str, float]]] = defaultdict(list)
    for row in rows:
        if row["queries_run"] != "12" or row["skipped"] != "0":
            raise ValueError(f"incorrect query count on trial {row['trial']}")
        if row["quality"] != "PASS" or row["identical_v1"] != "YES":
            raise ValueError(f"failed correctness on trial {row['trial']}")
        budget = int(row["budget_threads"])
        unpackers = int(row["unpackers_per_query"])
        workers = int(row["workers_per_query"])
        if budget != 48:
            raise ValueError(f"mismatched CPU budget on trial {row['trial']}")
        if row["mode"] == "dsq":
            if (workers, unpackers) != (5, 1):
                raise ValueError("unexpected DSQDATA worker/unpacker budget")
        elif (workers, unpackers) != (7, 0):
            raise ValueError(f"unexpected raw/bin8/Huffman budget: {row['mode']}")
        observed = int(row["observed_peak_threads"])
        if observed <= 0 or observed > 56:
            raise ValueError(f"thread sample missing or exceeding budget on {row['trial']}")
        item = {
            "prep": float(row["prologue_s"]),
            "search": float(row["search_s"]),
            "total": float(row["total_s"]),
            "bytes": float(row["encoded_bytes"]),
            "peak": float(observed),
            "processes": float(row["observed_peak_processes"]),
        }
        if abs(item["prep"] + item["search"] - item["total"]) > 0.25:
            raise ValueError(f"timing columns inconsistent on trial {row['trial']}")
        if min(item["prep"], item["search"], item["total"]) < 0:
            raise ValueError(f"negative timing on trial {row['trial']}")
        per_mode[row["mode"]].append(item)
    means = {
        mode: statistics.mean(row["total"] for row in per_mode[mode])
        for mode in MODES
    }
    baseline = means["raw"]
    print("One exclusive-node Slurm job. All four formats use the same 12 queries,")
    print("6 concurrent searches, 48 counted search/loader threads and 56 allocated CPUs.")
    print("mode      prep_s    search_s    total_s    vs_raw     peak_observed   file_bytes")
    for mode in sorted(MODES, key=means.get):
        rows = per_mode[mode]
        avg = lambda key: statistics.mean(row[key] for row in rows)
        size = int(avg("bytes"))
        print(f"{mode:<8} {avg('prep'):>8.2f} {avg('search'):>10.2f} "
              f"{avg('total'):>10.2f} {100*(baseline-means[mode])/baseline:>+8.2f}% "
              f"{max(int(r['peak']) for r in rows):>13d}   "
              f"{size if mode != 'raw' else 'original FASTA'}")
    print("\nCaveat: 1-second /proc sampling estimates thread peaks and can miss short bursts.")
    print("The DSQDATA mode uses 5 search workers plus 2 I/O threads per query;")
    print("other modes use 7 search workers. Equal overall thread budget does not")
    print("isolate the effect of encoding alone; this is a resource-fair comparison.")
    print("These 12-query results are screening data, not 100-query submission results.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, ZeroDivisionError) as error:
        raise SystemExit(f"ERROR: {error}") from error
