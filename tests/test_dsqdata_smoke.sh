#!/bin/bash
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: use test01, not login node" >&2; exit 2 ;;
esac
REPO=$(cd "$(dirname "$0")/.." && pwd)
JACK="$REPO/src/jackhmmer"
PACK5="$REPO/scripts/fasta_to_dsqdata"
VERIFY5="$REPO/scripts/verify_dsqdata"
PACK8="$REPO/scripts/fasta_to_bin8"
PACKH="$REPO/scripts/bin8_to_huffman"
DB="$REPO/data/demodb.fasta"
QUERY="$REPO/data/query.fasta"
for f in "$JACK" "$PACK5" "$VERIFY5" "$PACK8" "$PACKH" "$DB" "$QUERY"; do
  test -s "$f" || { echo "ERROR: missing $f" >&2; exit 1; }
done
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
"$PACK5" "$DB" "$tmp/database"
"$VERIFY5" "$DB" "$tmp/database"
"$PACK8" "$DB" "$tmp/database.bin8"
"$PACKH" "$tmp/database.bin8" "$tmp/database.huf"
"$REPO/scripts/verify_huffman" "$tmp/database.bin8" "$tmp/database.huf"
printf 'TOY_FILE_BYTES raw=%s bin8=%s dsqdata=%s huffman=%s\n' \
  "$(stat -c %s "$DB")" \
  "$(stat -c %s "$tmp/database.bin8")" \
  "$(du -cb "$tmp/database" "$tmp/database.dsqi" "$tmp/database.dsqm" "$tmp/database.dsqs" | tail -n1 | cut -f1)" \
  "$(stat -c %s "$tmp/database.huf")"
for workers in 0 2; do
  for iters in 1 3; do
    prefix="$tmp/cpu${workers}-n${iters}"
    ARGS=(--cpu "$workers" --noali --F1 0.0005 --F2 5e-05 --F3 5e-07 \
          -N "$iters" -E 0.001 -o /dev/null)
    env -u MSA_BIN8_DB -u MSA_DSQDATA_DB "$JACK" "${ARGS[@]}" \
      --tblout "$prefix.raw.tbl" -A "$prefix.raw.sto" "$QUERY" "$DB"
    env -u MSA_DSQDATA_DB MSA_BIN8_DB="$tmp/database.huf" "$JACK" "${ARGS[@]}" \
      --tblout "$prefix.huff.tbl" -A "$prefix.huff.sto" "$QUERY" "$DB"
    env -u MSA_BIN8_DB MSA_DSQDATA_DB="$tmp/database" "$JACK" "${ARGS[@]}" \
      --tblout "$prefix.dsq.tbl" -A "$prefix.dsq.sto" "$QUERY" "$DB"
    awk 'NF && $0 !~ /^#/' "$prefix.raw.tbl" > "$prefix.raw.hits"
    test -s "$prefix.raw.hits" || {
      echo "FAIL: original FASTA produced no toy hit rows" >&2; exit 1;
    }
    for mode in huff dsq; do
      awk 'NF && $0 !~ /^#/' "$prefix.$mode.tbl" > "$prefix.$mode.hits"
      diff -u "$prefix.raw.hits" "$prefix.$mode.hits" || {
        echo "FAIL: $mode hits workers=$workers iterations=$iters" >&2
        exit 1
      }
      diff -u "$prefix.raw.sto" "$prefix.$mode.sto" || {
        echo "FAIL: $mode MSA workers=$workers iterations=$iters" >&2
        exit 1
      }
    done
    echo "PASS: raw/Huffman/DSQDATA identical workers=$workers iterations=$iters"
  done
done
echo "NEW_FORMATS_TOY_SMOKE=PASS"
