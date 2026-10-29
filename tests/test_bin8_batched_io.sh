#!/bin/bash
# Verify T2's batched writer emits a logically identical database.
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: run on test01" >&2; exit 2;;
esac
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DB="$ROOT/data/demodb.fasta"
QUERY="$ROOT/data/query.fasta"
PACK="$ROOT/scripts/fasta_to_bin8"
JACK="$ROOT/src/jackhmmer"
VERIFY="$ROOT/scripts/verify_huffman"
HUFF="$ROOT/scripts/bin8_to_huffman"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
for f in "$DB" "$QUERY" "$PACK" "$JACK" "$VERIFY" "$HUFF"; do test -s "$f"; done
"$PACK" "$DB" "$tmp/batched.bin8"
"$HUFF" "$tmp/batched.bin8" "$tmp/huffman.huf"
"$VERIFY" "$tmp/batched.bin8" "$tmp/huffman.huf"

# Reference converter, if supplied from an independent baseline snapshot:
# compare the binary file itself, not just query hits.
if [ -n "${BIN8_REFERENCE_CONVERTER:-}" ]; then
  test -x "$BIN8_REFERENCE_CONVERTER"
  "$BIN8_REFERENCE_CONVERTER" "$DB" "$tmp/reference.bin8"
  cmp "$tmp/reference.bin8" "$tmp/batched.bin8"
  echo "BIN8_BULK_WRITE_BYTE_IDENTICAL=PASS"
fi

for iters in 1 3; do
  for cpu in 0 2; do
    args=(--cpu "$cpu" --noali --F1 0.0005 --F2 5e-05 --F3 5e-07 -N "$iters" -E 0.001 -o /dev/null)
    env -u MSA_BIN8_DB -u MSA_DSQDATA_DB "$JACK" "${args[@]}" \
      --tblout "$tmp/raw.tbl" -A "$tmp/raw.sto" "$QUERY" "$DB"
    env -u MSA_DSQDATA_DB MSA_BIN8_DB="$tmp/batched.bin8" "$JACK" "${args[@]}" \
      --tblout "$tmp/bin8.tbl" -A "$tmp/bin8.sto" "$QUERY" "$DB"
    diff -u <(grep -v '^#' "$tmp/raw.tbl") <(grep -v '^#' "$tmp/bin8.tbl")
    cmp "$tmp/raw.sto" "$tmp/bin8.sto"
    echo "PASS: batched bin8 matches FASTA cpu=$cpu iterations=$iters"
  done
done
echo "BIN8_BATCHED_IO_SMOKE=PASS"
