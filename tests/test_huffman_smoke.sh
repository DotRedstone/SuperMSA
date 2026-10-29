#!/bin/bash
# Full toy-database comparison: uncompressed BIN8 vs Huffman vs raw FASTA.
# Never preprocess competition data outside a scored prologue.
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: use test01, not login node" >&2; exit 2 ;;
esac

REPO=$(cd "$(dirname "$0")/.." && pwd)
JACK="$REPO/src/jackhmmer"
PACK8="$REPO/scripts/fasta_to_bin8"
PACKH="$REPO/scripts/bin8_to_huffman"
DB="$REPO/data/demodb.fasta"
QUERY="$REPO/data/query.fasta"
for f in "$JACK" "$PACK8" "$PACKH" "$DB" "$QUERY"; do
    test -s "$f" || { echo "ERROR: missing $f" >&2; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
"$PACK8" "$DB" "$tmp/data.bin8"
"$PACKH" "$tmp/data.bin8" "$tmp/data.huf"
test -s "$tmp/data.huf"
printf 'TOY_DATA_BYTES original=%s bin8=%s huffman=%s\n' \
    "$(stat -c %s "$DB")" "$(stat -c %s "$tmp/data.bin8")" "$(stat -c %s "$tmp/data.huf")"

# Negative tests: a malformed code-length table and a truncated header
# must both be rejected rather than producing an empty/partial hit list.
cp "$tmp/data.huf" "$tmp/bad_code.huf"
printf '\377' | dd of="$tmp/bad_code.huf" bs=1 seek=8 conv=notrunc status=none
head -c 12 "$tmp/data.huf" > "$tmp/bad_short.huf"
for broken in bad_code.huf bad_short.huf; do
    if MSA_BIN8_DB="$tmp/$broken" "$JACK" \
        --cpu 0 -N 1 -o /dev/null "$QUERY" "$DB" \
        >"$tmp/error.log" 2>&1; then
        echo "FAIL: accepted malformed compressed database $broken" >&2
        exit 1
    fi
done
echo "PASS: malformed Huffman headers rejected"

for workers in 0 2; do
    for iters in 1 3; do
        prefix="$tmp/cpu${workers}-n${iters}"
        COMMON=(--cpu "$workers" --noali --F1 0.0005 --F2 5e-05 --F3 5e-07 \
                -N "$iters" -E 0.001 -o /dev/null)
        env -u MSA_BIN8_DB "$JACK" "${COMMON[@]}" \
            --tblout "$prefix.raw.tbl" -A "$prefix.raw.sto" "$QUERY" "$DB"
        MSA_BIN8_DB="$tmp/data.bin8" "$JACK" "${COMMON[@]}" \
            --tblout "$prefix.bin8.tbl" -A "$prefix.bin8.sto" "$QUERY" "$DB"
        MSA_BIN8_DB="$tmp/data.huf" "$JACK" "${COMMON[@]}" \
            --tblout "$prefix.huff.tbl" -A "$prefix.huff.sto" "$QUERY" "$DB"

        awk 'NF && $0 !~ /^#/' "$prefix.raw.tbl" > "$prefix.raw.hits"
        test -s "$prefix.raw.hits"
        for mode in bin8 huff; do
            awk 'NF && $0 !~ /^#/' "$prefix.$mode.tbl" > "$prefix.$mode.hits"
            diff -u "$prefix.raw.hits" "$prefix.$mode.hits" ||
                { echo "FAIL: hits differ for $mode cpu=$workers iterations=$iters" >&2; exit 1; }
            diff -u "$prefix.raw.sto" "$prefix.$mode.sto" ||
                { echo "FAIL: MSA differs for $mode cpu=$workers iterations=$iters" >&2; exit 1; }
        done
        echo "PASS: raw/bin8/Huffman identical, cpu=$workers iterations=$iters"
    done
done
echo "HUFFMAN_TOY_CORRECTNESS=PASS"
