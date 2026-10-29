#!/bin/bash
# Unit test for content-preserving FASTA line-unwrapper (run on test01).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
BIN="${1:-$ROOT/scripts/fasta_rewrap}"
test -x "$BIN" || { echo "ERROR: compile $BIN before testing" >&2; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

# Includes CRLF, multiline sequences, an empty sequence, an annotated
# header that must be preserved verbatim, and an unterminated final line.
printf '>seq1 text |x\r\nACD\r\nEFG\r\n>seq2 another header\nKLM\nN\n>seq3 empty\n>seq4\nXYZ' \
    > "$TMP/original.fasta"
printf '>seq1 text |x\nACDEFG\n>seq2 another header\nKLMN\n>seq3 empty\n\n>seq4\nXYZ\n' \
    > "$TMP/expected.fasta"

"$BIN" "$TMP/original.fasta" "$TMP/actual.fasta" > "$TMP/convert.log"
cmp "$TMP/expected.fasta" "$TMP/actual.fasta"

if printf 'NO_HEADER\nAAA\n' > "$TMP/bad.fasta" &&
   "$BIN" "$TMP/bad.fasta" "$TMP/bad.out" > /dev/null 2>&1; then
    echo "ERROR: accepted invalid input without FASTA header" >&2
    exit 1
fi

echo "PASS: FASTA rewrap preserves identifiers, raw residues, order, and empty records"
