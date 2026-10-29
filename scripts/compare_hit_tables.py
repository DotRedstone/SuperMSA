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
        # Fenwick tree over reversed original ranks. Earlier candidates
        # with original rank > current rank are inversions. Their
        # minimum/maximum scores must be within tie tolerance.
        n = len(ref_order)
        min_tree = [math.inf] * (n + 1)
        max_tree = [-math.inf] * (n + 1)
        moved = 0
        for i, target in enumerate(got_order):
            rank = n - original_position[target]
            score = float(ref[target][5])
            idx = rank - 1
            min_prev, max_prev = math.inf, -math.inf
            while idx:
                min_prev = min(min_prev, min_tree[idx])
                max_prev = max(max_prev, max_tree[idx])
                idx -= idx & -idx
            if min_prev != math.inf and (
                abs(min_prev-score) > SCORE_ABS_TOL + 1e-9 or
                abs(max_prev-score) > SCORE_ABS_TOL + 1e-9
            ):
                raise Difference(
                    f"{sid}: non-tie rank inversion involving "
                    f"{target} (ref bit score {score}, prior inverted "
                    f"score range {min_prev}..{max_prev})"
                )
            if original_position[target] != i:
                moved += 1
            idx = rank
            while idx <= n:
                min_tree[idx] = min(min_tree[idx], score)
                max_tree[idx] = max(max_tree[idx], score)
                idx += idx & -idx
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
    # The historical reference directory may contain extra unrelated
    # queries. Compare exactly the selected 12; never accept missing
    # reference files or unexpected current-run output files.
    reference_files = {p.stem for p in args.reference.glob("*.tbl")}
    candidate_files = {p.stem for p in args.candidate.glob("*.tbl")}
    if not expected.issubset(reference_files):
        raise Difference(
            f"{args.reference}: missing reference queries="
            f"{sorted(expected-reference_files)[:5]}"
        )
    if candidate_files != expected:
        raise Difference(
            f"{args.candidate}: missing={sorted(expected-candidate_files)[:5]} "
            f"unexpected={sorted(candidate_files-expected)[:5]}"
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
