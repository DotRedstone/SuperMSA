#!/bin/bash
# Test-only smoke test: compare raw FASTA vs newly generated binary on the
# repository's toy database. This does NOT preprocess competition input.
set -euo pipefail

case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: run on test01, not login node" >&2; exit 2 ;;
esac

REPO=$(cd "$(dirname "$0")/.." && pwd)
BIN="$REPO/src/jackhmmer"
PACKER="$REPO/scripts/fasta_to_bin8"
QUERY="$REPO/data/query.fasta"
DB="$REPO/data/demodb.fasta"
: "${CPU:=2}"

for f in "$BIN" "$PACKER" "$QUERY" "$DB"; do
  test -s "$f" || { echo "ERROR: missing $f" >&2; exit 2; }
done

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
"$PACKER" "$DB" "$tmp/data.bin8"

# Cover the serial path (--cpu 0), the threaded path (--cpu 2),
# and both a single database pass and multi-iteration rewind.
for workers in 0 2; do
  for iters in 1 3; do
    prefix="$tmp/cpu${workers}-n${iters}"
    COMMON=(--cpu "$workers" --noali --F1 0.0005 --F2 5e-05 --F3 5e-07
            -N "$iters" -E 0.001 -o /dev/null)

    env -u MSA_BIN8_DB "$BIN" "${COMMON[@]}" \
      --tblout "$prefix.raw.tbl" -A "$prefix.raw.sto" "$QUERY" "$DB"
    MSA_BIN8_DB="$tmp/data.bin8" "$BIN" "${COMMON[@]}" \
      --tblout "$prefix.bin8.tbl" -A "$prefix.bin8.sto" "$QUERY" "$DB"

    awk 'NF && $0 !~ /^#/' "$prefix.raw.tbl" > "$prefix.raw.hits"
    awk 'NF && $0 !~ /^#/' "$prefix.bin8.tbl" > "$prefix.bin8.hits"
    test -s "$prefix.raw.hits" ||
      { echo "ERROR: demo FASTA produced no hits ($workers threads, $iters iterations)" >&2; exit 1; }
    diff -u "$prefix.raw.hits" "$prefix.bin8.hits" ||
      { echo "FAIL: hit-table mismatch workers=$workers iterations=$iters" >&2; exit 1; }
    test -f "$prefix.raw.sto" && test -f "$prefix.bin8.sto"
    diff -u "$prefix.raw.sto" "$prefix.bin8.sto" ||
      { echo "FAIL: Stockholm mismatch workers=$workers iterations=$iters" >&2; exit 1; }
    echo "PASS: raw/bin8 identical, workers=$workers iterations=$iters"
  done
done
echo "PASS: bin8 serial/threaded and single/multi-iteration smoke checks"
