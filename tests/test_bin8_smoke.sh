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

COMMON=(--cpu "$CPU" --noali --F1 0.0005 --F2 5e-05 --F3 5e-07 -N 3 -E 0.001 -o /dev/null)
env -u MSA_BIN8_DB "$BIN" "${COMMON[@]}" \
  --tblout "$tmp/raw.tbl" -A "$tmp/raw.sto" "$QUERY" "$DB"
MSA_BIN8_DB="$tmp/data.bin8" "$BIN" "${COMMON[@]}" \
  --tblout "$tmp/bin8.tbl" -A "$tmp/bin8.sto" "$QUERY" "$DB"

awk 'NF && $0 !~ /^#/' "$tmp/raw.tbl" > "$tmp/raw.hits"
awk 'NF && $0 !~ /^#/' "$tmp/bin8.tbl" > "$tmp/bin8.hits"
test -s "$tmp/raw.hits" || { echo "ERROR: no demo hits" >&2; exit 1; }
diff -u "$tmp/raw.hits" "$tmp/bin8.hits"
test -f "$tmp/raw.sto" && test -f "$tmp/bin8.sto"
diff -u "$tmp/raw.sto" "$tmp/bin8.sto" || {
  echo "WARNING: MSA differs in demo test" >&2
  exit 1
}

echo "PASS: bin8 and raw FASTA give identical demo hit rows and Stockholm MSA"
