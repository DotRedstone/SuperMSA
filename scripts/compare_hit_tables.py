#!/usr/bin/env python3
"""Compare independent HMMER --tblout runs without demanding byte identity.

The strict comparator in the initial feature ABBA script incorrectly rejected
normal tiny E-value rounding and score ties even in its UNMODIFIED base trial.
This comparator is deliberately conservative:
* All expected query files and target ID sets must be identical (no dropped hits).
* Target metadata, accession, query, and integer domain counts must match.
* Printed scores and E-values may move only within explicit bounded tolerances.
* Reorderings are accepted ONLY within effectively tied total bit scores.
* ROC10 quality is checked separately by run_queries.sh.

This is a cross-run reproducibility guard, not evidence that floating-point
results are mathematically identical.

Usage: compare_hit_tables.py --queries queries.selected reference/tbl candidate/tbl
"""
import argparse
import math
import sys
from pathlib import Path

SCORE_ABS_TOL = 0.25  # HMMER renders these values to 1 decimal place
EVALUE_REL_TOL = 0.20  # protects against coarse scientific notation rounding
SCORE_COLUMNS = (5, 6, 8, 9, 10)
EVALUE_COLUMNS = (4, 7)
INTEGER_COLUMNS = tuple(range(11, 18))


class Difference(ValueError):
    pass


def load_table(path: Path, query_id: str):
    records = {}
    order = []
    with path.open(encoding="utf-8") as stream:
        for lineno, line in enumerate(stream, 1):
            if not line.strip() or line.startswith("#"):
                continue
            tokens = line.split(maxsplit=18)
            if len(tokens) < 18:
                raise Difference(f"{path}:{lineno}: fewer than 18 HMMER fields")
            if tokens[2] != query_id:
                raise Difference(f"{path}:{lineno}: query {tokens[2]} != {query_id}")
            target = tokens[0]
            if target in records:
                raise Difference(f"{path}:{lineno}: duplicate target {target}")
            records[target] = tokens
            order.append(target)
    return records, order


def validate_pair(reference: Path, candidate: Path, sid: str):
    ref, ref_order = load_table(reference, sid)
    got, got_order = load_table(candidate, sid)
    a, b = set(ref), set(got)
    if a != b:
        raise Difference(
            f"{sid}: different target sets: missing={sorted(a-b)[:5]} "
            f"added={sorted(b-a)[:5]} (total ref={len(a)} got={len(b)})"
        )
    checked_evalue_deltas = 0
    for target in ref:
        left, right = ref[target], got[target]
        for idx in (1, 3, 18):
            x = left[idx] if idx < len(left) else ""
            y = right[idx] if idx < len(right) else ""
            if x != y:
                raise Difference(f"{sid}/{target}: metadata column {idx} differs")
        for idx in INTEGER_COLUMNS:
            if left[idx] != right[idx]:
                raise Difference(
                    f"{sid}/{target}: integer field {idx} differs: "
                    f"{left[idx]} vs {right[idx]}"
                )
        for idx in SCORE_COLUMNS + EVALUE_COLUMNS:
            try:
                x, y = float(left[idx]), float(right[idx])
            except ValueError as exc:
                raise Difference(f"{sid}/{target}: malformed numeric col {idx}") from exc
            if not math.isfinite(x) or not math.isfinite(y):
                raise Difference(f"{sid}/{target}: non-finite numeric col {idx}")
            if idx in SCORE_COLUMNS:
                if abs(x-y) > SCORE_ABS_TOL + 1e-9:
                    raise Difference(
                        f"{sid}/{target}: score/bias col {idx} drift: {x} vs {y}"
                    )
            elif (x == 0.0) != (y == 0.0) or (
                x != 0.0 and abs(x-y) > EVALUE_REL_TOL*max(abs(x), abs(y))
            ):
                raise Difference(
                    f"{sid}/{target}: E-value col {idx} drift: {x} vs {y}"
                )
            elif x != y:
                checked_evalue_deltas += 1

    # A new order is acceptable only if it never reverses targets whose
    # original score differs by more than the permitted tie margin.
    # The reference order itself may have minor rounded nonmonotonicities.
    # Compare pairs through a running best future score, O(n), rather
    # than doing O(n^2) pairwise inversions.
    if got_order != ref_order:
        original_position = {name: i for i, name in enumerate(ref_order)}
        # Any candidate target that jumps ahead of a reference-earlier
        # target must have a reference bit score within the tie margin.
        # Descending minimum score among reference-earlier targets:
        moved = 0
        for i, target in enumerate(got_order):
            if original_position[target] == i:
                continue
            moved += 1
        # Reject rank inversions except between near-equal bit scores.
        for i in range(len(got_order) - 1):
            earlier = got_order[i]
            for later in got_order[i+1:]:
                if original_position[earlier] > original_position[later]:
                    x = float(ref[earlier][5])
                    y = float(ref[later][5])
                    if abs(x-y) > SCORE_ABS_TOL + 1e-9:
                        raise Difference(
                            f"{sid}: non-tie rank inversion {earlier}({x}) "
                            f"vs {later}({y})"
                        )
        return len(ref), moved, checked_evalue_deltas
    return len(ref), 0, checked_evalue_deltas


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--queries", required=True, type=Path)
    parser.add_argument("reference", type=Path)
    parser.add_argument("candidate", type=Path)
    args = parser.parse_args()
    query_ids = [
        line.strip() for line in args.queries.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if not query_ids or len(query_ids) != len(set(query_ids)):
        raise Difference("missing or duplicate queries")
    expected = set(query_ids)
    for directory in (args.reference, args.candidate):
        actual = {p.stem for p in directory.glob("*.tbl")}
        if actual != expected:
            raise Difference(
                f"{directory}: missing={sorted(expected-actual)[:5]} "
                f"unexpected={sorted(actual-expected)[:5]}"
            )
    hits = moved = deltas = 0
    for sid in query_ids:
        count, order_changes, e_delta = validate_pair(
            args.reference / f"{sid}.tbl",
            args.candidate / f"{sid}.tbl",
            sid,
        )
        hits += count
        moved += order_changes
        deltas += e_delta
    print(
        f"HMMER_HITS_EQUIVALENT=PASS queries={len(query_ids)} "
        f"targets={hits} tie_order_changes={moved} "
        f"bounded_evalue_deltas={deltas}"
    )


if __name__ == "__main__":
    try:
        main()
    except (Difference, OSError) as exc:
        print(f"HMMER_HITS_EQUIVALENT=FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
