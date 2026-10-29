#!/bin/bash
# Strict full-record exactness smoke for 8-bit transport.
# Optional extended check on the real database:
#   scripts/verify_bin8 "$DATA/database.fasta" "$RUN/results/XX-.../prepared/database.bin8"
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*)
    echo "ERROR: run compilation/verification on a compute/test node" >&2; exit 2;;
esac
REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"
DB="$REPO/data/demodb.fasta"
PACKER="$REPO/scripts/fasta_to_bin8"
VERIFY="$REPO/scripts/verify_bin8"
for f in "$DB" "$PACKER"; do
  test -s "$f" || { echo "missing required test input: $f" >&2; exit 2; }
done
command -v gcc
command -v truncate
command -v dd
gcc -O2 -std=c99 -Wall -Wextra -I easel -o "$VERIFY" \
  scripts/verify_bin8.c -L easel -leasel -pthread -lm

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
"$PACKER" "$DB" "$tmp/toy.bin8"
"$VERIFY" "$DB" "$tmp/toy.bin8"

cp "$tmp/toy.bin8" "$tmp/truncated.bin8"
truncate -s -1 "$tmp/truncated.bin8"
if "$VERIFY" "$DB" "$tmp/truncated.bin8" > "$tmp/trunc.log" 2>&1; then
  echo "ERROR: verifier accepted truncated BIN8" >&2; exit 1
fi
echo "PASS: truncated payload rejected"

cp "$tmp/toy.bin8" "$tmp/bad-magic.bin8"
printf 'Z' | dd of="$tmp/bad-magic.bin8" bs=1 seek=0 conv=notrunc status=none
if "$VERIFY" "$DB" "$tmp/bad-magic.bin8" > "$tmp/magic.log" 2>&1; then
  echo "ERROR: verifier accepted invalid magic" >&2; exit 1
fi
echo "PASS: invalid header rejected"

cp "$tmp/toy.bin8" "$tmp/bad-residue.bin8"
size=$(stat -c '%s' "$tmp/bad-residue.bin8")
printf '\377' | dd of="$tmp/bad-residue.bin8" bs=1 seek="$((size - 1))" conv=notrunc status=none
if "$VERIFY" "$DB" "$tmp/bad-residue.bin8" > "$tmp/residue.log" 2>&1; then
  echo "ERROR: verifier accepted altered residue" >&2; exit 1
fi
echo "PASS: altered digital residue rejected"
echo "BIN8_FULL_RECORD_SMOKE=PASS"
