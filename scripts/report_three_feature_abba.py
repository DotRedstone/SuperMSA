#!/usr/bin/env python3
"""Read-only report for T1/T2/T3 four-trial ABBA SuperMSA experiments.

Works with Python 3.6 (THUSCC login node). Does not change any benchmark
outputs and never substitutes unpaired historical runs for current baseline.

Usage: python3 report_three_feature_abba.py \
         --root "$HOME/WORK/dot/experiments/supermsa/probes" --revision r02
"""
import argparse
import csv
import math
import sys
from pathlib import Path

FIELDS = ("prologue_s", "search_s", "total_s")
EXPECTED = (("01", "base"), ("02", "tuned"),
            ("03", "tuned"), ("04", "base"))
FEATURES = (("t1", "FASTA one-pass"),
            ("t2", "BIN8 batched writer"),
            ("t3", "Reader/Worker geometry"))


class InvalidData(Exception):
    pass


def load_rows(path, feature):
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        required = {"trial", "feature", "mode", "queries_run", "quality",
                    "identical_v1", "worker_threads", "warmup_runs"} | set(FIELDS)
        if not reader.fieldnames or not required.issubset(reader.fieldnames):
            raise InvalidData("missing or unexpected TSV header")
        rows = list(reader)
    if len(rows) != 4:
        return None, "INCOMPLETE ({}/4 trials)".format(len(rows))
    for index, (row, expected) in enumerate(zip(rows, EXPECTED)):
        if (row["trial"], row["mode"]) != expected:
            raise InvalidData("trial {} expected {}, got {}".format(
                index + 1, expected, (row["trial"], row["mode"])))
        if row["feature"] != feature:
            raise InvalidData("wrong feature in trial {}".format(index + 1))
        for field, desired in (("queries_run", "12"), ("quality", "PASS"),
                               ("identical_v1", "YES"), ("worker_threads", "48"),
                               ("warmup_runs", "1")):
            if row[field] != desired:
                raise InvalidData("trial {} has {}={!r}, expected {!r}".format(
                    index + 1, field, row[field], desired))
        for field in FIELDS:
            try:
                number = float(row[field])
            except (ValueError, TypeError):
                raise InvalidData("trial {} non-numeric {}".format(index + 1, field))
            if not math.isfinite(number) or number < 0:
                raise InvalidData("trial {} invalid {}".format(index + 1, field))
            row[field] = number
        if abs(row["prologue_s"] + row["search_s"] - row["total_s"]) > 0.21:
            raise InvalidData("trial {} total is not prep+search".format(index + 1))
    return rows, None


def mean(nums):
    return sum(nums) / len(nums)


def result(rows, name):
    b1, t1, t2, b2 = rows
    print("\n{}".format(name))
    print("  metric          base_mean   tuned_mean   saved_s   time_reduction")
    for field in FIELDS:
        base = mean((b1[field], b2[field]))
        tuned = mean((t1[field], t2[field]))
        saved = base - tuned
        pct = 100.0 * saved / base if base else float("nan")
        suffix = "{:7.2f}%".format(pct) if math.isfinite(pct) else "   N/A"
        print("  {:<14} {:>9.2f}s {:>10.2f}s {:>8.2f}s {:>14}".format(
            field, base, tuned, saved, suffix))
    pairs = (b1["total_s"]-t1["total_s"],
             b2["total_s"]-t2["total_s"])
    drift = b2["total_s"]-b1["total_s"]
    print("  paired total savings: first={:+.2f}s second={:+.2f}s".format(*pairs))
    print("  base first→last drift: {:+.2f}s".format(drift))
    if pairs[0] * pairs[1] <= 0:
        print("  NOTE: paired improvements have mixed/zero signs; not stable evidence")
    print("  NOTE: two repetitions are screening evidence, not significance testing")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--revision", default="r02", help="experiment revision, default r02")
    args = ap.parse_args()
    print("SuperMSA 12-query ABBA summary (base, tuned, tuned, base)")
    print("Read-only; reports only same-snapshot paired runs")
    any_invalid = False
    for feature, name in FEATURES:
        path = args.root / (feature+"-abba-"+args.revision)
        summary = path / "summary.tsv"
        if not summary.is_file():
            print("\n{}: NOT READY — {} is absent".format(feature, summary))
            continue
        try:
            rows, reason = load_rows(summary, feature)
        except (OSError, UnicodeError, InvalidData) as exc:
            print("\n{}: INVALID — {}".format(feature, exc))
            any_invalid = True
            continue
        if rows is None:
            print("\n{}: {}".format(feature, reason))
            continue
        done = False
        for log in path.glob("perf.*.out"):
            try:
                if "FEATURE_ABBA_COMPLETED=YES feature={}".format(feature) in log.read_text(
                        encoding="utf-8", errors="replace"):
                    done = True
                    break
            except OSError:
                pass
        if not done:
            print("\n{}: 4/4 rows present but completion marker absent; wait for job".format(feature))
            continue
        result(rows, "{} — {}".format(feature.upper(), name))
    print("\nNOTE: identical_v1=YES denotes tolerance-gated output equivalence,")
    print("NOT byte-identical floating point results. Same-run base/tuned")
    print("correctness and full input integrity remain separate requirements.")
    return 2 if any_invalid else 0


if __name__ == "__main__":
    sys.exit(main())
