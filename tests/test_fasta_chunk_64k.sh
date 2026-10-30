#!/bin/bash
# E07: compare 4 KiB FASTA read blocks against opt-in 64 KiB blocks.
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: test on compute node" >&2; exit 2;;
esac
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PACK="$ROOT/scripts/fasta_to_bin8"
JACK="$ROOT/src/jackhmmer"
DB="$ROOT/data/demodb.fasta"
QUERY="$ROOT/data/query.fasta"
for f in "$PACK" "$JACK" "$DB" "$QUERY"; do test -s "$f"; done
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
# Include a header and a residue line spanning the 4K and 64K boundaries.
python3 - "$tmp/edge.fasta" <<'PY'
import sys
with open(sys.argv[1], "wb") as f:
    f.write(b">long " + b"X" * 4700 + b"\r\n")
    f.write(b"A" * 70000 + b"\r\n")
    f.write(b">star mixed\nAc D e F\nWXYZ*\n")
    f.write(b">last\nQ")
PY
for db in "$DB" "$tmp/edge.fasta"; do
  MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=1 MSA_FASTA_CHUNK_64K=0 "$PACK" "$db" "$tmp/base.bin8"
  MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=1 MSA_FASTA_CHUNK_64K=1 "$PACK" "$db" "$tmp/tuned.bin8"
  cmp "$tmp/base.bin8" "$tmp/tuned.bin8"
  echo "PASS: byte-exact digital records: $db"
done
echo "E07_ALL_DIGITIZED_RESIDUES_EXACT=PASS"
for workers in 0 2; do
  for iters in 1 3; do
    COMMON=(--cpu "$workers" --noali --F1 0.0005 --F2 5e-05 --F3 5e-07 -N "$iters" -E 0.001 -o /dev/null)
    env -u MSA_BIN8_DB -u MSA_DSQDATA_DB MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=1 MSA_FASTA_CHUNK_64K=0 "$JACK" "${COMMON[@]}" --tblout "$tmp/base.tbl" -A "$tmp/base.sto" "$QUERY" "$DB" >/dev/null
    env -u MSA_BIN8_DB -u MSA_DSQDATA_DB MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=1 MSA_FASTA_CHUNK_64K=1 "$JACK" "${COMMON[@]}" --tblout "$tmp/tuned.tbl" -A "$tmp/tuned.sto" "$QUERY" "$DB" >/dev/null
    grep -v '^#' "$tmp/base.tbl" > "$tmp/base.hits"
    grep -v '^#' "$tmp/tuned.tbl" > "$tmp/tuned.hits"
    test -s "$tmp/base.hits"
    cmp "$tmp/base.hits" "$tmp/tuned.hits"
    cmp "$tmp/base.sto" "$tmp/tuned.sto"
    echo "PASS: identical hits and MSA cpu=$workers N=$iters"
  done
done
printf '>bad\nAC-DE\n' > "$tmp/bad-gap.fa"
printf '>bad\nAB\377CD\n' > "$tmp/bad-highbit.fa"
for bad in "$tmp/bad-gap.fa" "$tmp/bad-highbit.fa"; do
  for val in 0 1; do
    if MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=1 MSA_FASTA_CHUNK_64K="$val" "$PACK" "$bad" "$tmp/bad.bin8" >/dev/null 2>&1; then
      echo "ERROR: accepted invalid FASTA under chunk64k=$val: $bad" >&2
      exit 1
    fi
  done
done
echo "E07_FASTA_CHUNK_64K_SMOKE=PASS"
