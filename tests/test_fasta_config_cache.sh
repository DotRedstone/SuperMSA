#!/bin/bash
# E06 regression: opening a FASTA file caches opt-in flags without changing output.
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: test on a compute node" >&2; exit 2;;
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

# Includes CRLF, mixed case, ignored spaces/tabs, and the special * mapping.
printf '>alpha word\r\nAc D e F\r\nG \tHI\r\n>beta\r\nWXYZ*\r\n>gamma\r\nA*\r\n>delta\r\nQ\r\n' > "$tmp/edge.fasta"
for db in "$DB" "$tmp/edge.fasta"; do
  MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=1 MSA_FASTA_CACHE_FLAGS=0 "$PACK" "$db" "$tmp/base.bin8"
  MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=1 MSA_FASTA_CACHE_FLAGS=1 "$PACK" "$db" "$tmp/cached.bin8"
  cmp "$tmp/base.bin8" "$tmp/cached.bin8"
  # If E01 is disabled, cache mode must not enable the fused reader by mistake.
  MSA_FASTA_ONEPASS=0 MSA_FASTA_DIRECT_MAP=1 MSA_FASTA_CACHE_FLAGS=0 "$PACK" "$db" "$tmp/old.bin8"
  MSA_FASTA_ONEPASS=0 MSA_FASTA_DIRECT_MAP=1 MSA_FASTA_CACHE_FLAGS=1 "$PACK" "$db" "$tmp/cache-old.bin8"
  cmp "$tmp/old.bin8" "$tmp/cache-old.bin8"
  echo "PASS: byte-exact FASTA digital output (cache toggled): $db"
done
echo "E06_ALL_DIGITIZED_RESIDUES_EXACT=PASS"

for workers in 0 2; do
  for iterations in 1 3; do
    COMMON=(--cpu "$workers" --noali --F1 0.0005 --F2 5e-05 --F3 5e-07 -N "$iterations" -E 0.001 -o /dev/null)
    env -u MSA_BIN8_DB -u MSA_DSQDATA_DB MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=1 MSA_FASTA_CACHE_FLAGS=0 "$JACK" "${COMMON[@]}" --tblout "$tmp/base.tbl" -A "$tmp/base.sto" "$QUERY" "$DB" > /dev/null
    env -u MSA_BIN8_DB -u MSA_DSQDATA_DB MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=1 MSA_FASTA_CACHE_FLAGS=1 "$JACK" "${COMMON[@]}" --tblout "$tmp/cached.tbl" -A "$tmp/cached.sto" "$QUERY" "$DB" > /dev/null
    grep -v '^#' "$tmp/base.tbl" > "$tmp/base.hits"
    grep -v '^#' "$tmp/cached.tbl" > "$tmp/cached.hits"
    test -s "$tmp/base.hits"
    cmp "$tmp/base.hits" "$tmp/cached.hits"
    cmp "$tmp/base.sto" "$tmp/cached.sto"
    echo "PASS: hits and MSA equal cpu=$workers N=$iterations"
  done
done

printf '>bad\nAC-DE\n' > "$tmp/bad-gap.fa"
printf '>bad\nAB\377CD\n' > "$tmp/bad-highbit.fa"
for bad in "$tmp/bad-gap.fa" "$tmp/bad-highbit.fa"; do
  for cache in 0 1; do
    if MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=1 MSA_FASTA_CACHE_FLAGS="$cache" "$PACK" "$bad" "$tmp/bad.bin8" >/dev/null 2>&1; then
      echo "ERROR: invalid FASTA accepted with cache=$cache: $bad" >&2
      exit 1
    fi
  done
done
echo "E06_FASTA_CONFIG_CACHE_SMOKE=PASS"
