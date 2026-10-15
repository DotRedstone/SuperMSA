#!/bin/bash
set -u

ROOT=$(dirname "$0")
QUERY=${QUERY:-$ROOT/data/query.fasta}
DB=${DB:-$ROOT/data/demodb.fasta}
BIN=$ROOT/src/jackhmmer
CPU=${CPU:-8}
FILTERS=${FILTERS:---noali --F1 0.0005 --F2 5e-05 --F3 5e-07}
TBL=$(mktemp)
trap 'rm -f "$TBL"' EXIT

if ! "$BIN" --cpu "$CPU" $FILTERS -N 3 -E 0.001 --tblout "$TBL" -o /dev/null "$QUERY" "$DB"; then
    echo "FAIL: jackhmmer exited non-zero"; exit 1
fi
hits=$(grep -vc '^#' "$TBL")
if [ "$hits" -lt 5 ]; then
    echo "FAIL: only $hits hits (expected >= 5)"; exit 1
fi
echo "PASS: $hits hits"
