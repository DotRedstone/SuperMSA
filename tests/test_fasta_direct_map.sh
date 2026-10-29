#!/bin/bash
# E05 correctness: compare T1 against the opt-in direct-map mode.
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: run only on a compute node" >&2; exit 2;;
esac
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PACK="$ROOT/scripts/fasta_to_bin8"
JACK="$ROOT/src/jackhmmer"
DB="$ROOT/data/demodb.fasta"
QUERY="$ROOT/data/query.fasta"
for f in "$PACK" "$JACK" "$DB" "$QUERY"; do
  test -s "$f" || { echo "ERROR: missing $f" >&2; exit 2; }
done
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

# Binary output verifies every digitized residue, sequence header and order.
printf '>alpha mixed-case with spaces\r\nAc D e F\r\nG \tHI\r\n>beta star\r\nWXYZ*\r\n>gamma stop\r\nA*\r\n>delta\r\nQ\r\n' > "$tmp/edge.fasta"
for db in "$DB" "$tmp/edge.fasta"; do
  MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=0 "$PACK" "$db" "$tmp/t1.bin8"
  MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=1 "$PACK" "$db" "$tmp/e05.bin8"
  cmp "$tmp/t1.bin8" "$tmp/e05.bin8"
  echo "PASS: byte-identical digital output for $db"
done
echo "E05_ALL_DIGITIZED_RESIDUES_EXACT=PASS"

for workers in 0 2; do
  for iterations in 1 3; do
    COMMON=(--cpu "$workers" --noali --F1 0.0005 --F2 5e-05 --F3 5e-07 -N "$iterations" -E 0.001 -o /dev/null)
    env -u MSA_BIN8_DB -u MSA_DSQDATA_DB MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=0 "$JACK" "${COMMON[@]}" --tblout "$tmp/t1.tbl" -A "$tmp/t1.sto" "$QUERY" "$DB" > /dev/null
    env -u MSA_BIN8_DB -u MSA_DSQDATA_DB MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=1 "$JACK" "${COMMON[@]}" --tblout "$tmp/e05.tbl" -A "$tmp/e05.sto" "$QUERY" "$DB" > /dev/null
    grep -v '^#' "$tmp/t1.tbl" > "$tmp/t1.hits"
    grep -v '^#' "$tmp/e05.tbl" > "$tmp/e05.hits"
    test -s "$tmp/t1.hits"
    cmp "$tmp/t1.hits" "$tmp/e05.hits"
    cmp "$tmp/t1.sto" "$tmp/e05.sto"
    echo "PASS: identical hits and MSA cpu=$workers N=$iterations"
  done
done

# Error rejection must remain the same. Both test modes reject bad alphabet.
printf '>bad\nAC-DE\n' > "$tmp/bad-gap.fa"
printf '>bad\nAB\377CD\n' > "$tmp/bad-highbit.fa"
for bad in "$tmp/bad-gap.fa" "$tmp/bad-highbit.fa"; do
  for opt in 0 1; do
    if MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP="$opt" "$PACK" "$bad" "$tmp/bad.bin8" >/dev/null 2>&1; then
      echo "ERROR: invalid FASTA accepted: $bad direct_map=$opt" >&2
      exit 1
    fi
  done
done
echo "E05_FASTA_DIRECT_MAP_SMOKE=PASS"
