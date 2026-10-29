#!/usr/bin/env python3
"""Regression tests for the across-run HMMER hit-table comparator."""
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "compare_hit_tables.py"


def row(target, score, best_e, full_e="4.2e-44", doms="1"):
    # HMMER tblout fields 0..17 plus nonempty free-form description.
    return (
        f"{target} - toy - {full_e} {score:.1f} 7.1 "
        f"{best_e} {score:.1f} 7.1 1.0 {doms} 0 0 "
        f"{doms} {doms} 1 1 a.208.1.1 |target description"
    )


def check(ref_rows, got_rows, expect_ok, label):
    with tempfile.TemporaryDirectory(prefix="hma-compare-") as root:
        path = Path(root)
        a, b = path / "a", path / "b"
        a.mkdir()
        b.mkdir()
        (path / "queries.selected").write_text("toy\n", encoding="utf-8")
        (a / "toy.tbl").write_text("# ref\n" + "\n".join(ref_rows) + "\n", encoding="utf-8")
        (b / "toy.tbl").write_text("# got\n" + "\n".join(got_rows) + "\n", encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--queries",
             str(path / "queries.selected"), str(a), str(b)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True,
        )
        if (result.returncode == 0) != expect_ok:
            raise AssertionError(
                f"{label}: unexpected result {result.returncode} "
                f"stdout={result.stdout!r} stderr={result.stderr!r}"
            )
        print(f"PASS: {label}")


def main():
    aa = row("A", 161.2, "4.8e-44")
    bb = row("B", 161.1, "4.9e-44")
    cc = row("C", 120.0, "1.1e-30", "1.0e-30")
    aa_rounded = row("A", 161.2, "4.7e-44")
    check([aa, bb, cc], [bb, aa_rounded, cc], True,
          "tied score reorder and printed E-value drift")
    check([aa, bb, cc], [aa, bb, cc], True, "exact rows")
    check([aa, bb, cc], [aa_rounded, cc, bb], False, "non-tied rank inversion")
    check([aa, bb, cc], [aa_rounded, bb], False, "dropped hit")
    check([aa, bb, cc], [aa_rounded, bb, row("D", 120.0, "1.1e-30")],
          False, "added/different hit")
    check([aa, bb, cc], [row("A", 161.2, "9.8e-40"), bb, cc],
          False, "large E-value drift")
    check([aa, bb, cc], [row("A", 160.0, "4.8e-44"), bb, cc],
          False, "large bit score drift")
    check([aa, bb, cc], [row("A", 161.2, "4.8e-44", doms="2"), bb, cc],
          False, "integer domain-count drift")
    check([], [], True, "two zero-hit files")
    print("HMMER_COMPARE_SMOKE=PASS")


if __name__ == "__main__":
    main()
