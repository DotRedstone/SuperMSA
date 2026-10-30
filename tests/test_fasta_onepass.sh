#!/usr/bin/env bash
# Verify byte-for-byte equivalent digital FASTA targets and search output.
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: run on test01" >&2; exit 2;;
esac
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PACK="$ROOT/tests/fasta_dump"
JACK="$ROOT/src/jackhmmer"
DB="$ROOT/data/demodb.fasta"
QUERY="$ROOT/data/query.fasta"
for f in "$PACK" "$JACK" "$DB" "$QUERY"; do test -s "$f"; done
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

for fixture in "$DB" "$tmp/small.fasta"; do
  if [ "$fixture" != "$DB" ]; then
    printf '>alpha short description\nac D e F\nG \tHI\n>beta\nWXYZ*\n' > "$fixture"
  fi
  env -u MSA_FASTA_ONEPASS "$PACK" "$fixture" "$tmp/default.dump"
  MSA_FASTA_ONEPASS=1 "$PACK" "$fixture" "$tmp/onepass.dump"
  cmp "$tmp/default.dump" "$tmp/onepass.dump"
done
echo "FASTA_ONEPASS_ALL_RESIDUES_EXACT=PASS"

for workers in 0 2; do
  for iters in 1 3; do
    COMMON=(--cpu "$workers" --noali --F1 0.0005 --F2 5e-05 --F3 5e-07 \
            -N "$iters" -E 0.001 -o /dev/null)
    env -u MSA_FASTA_ONEPASS "$JACK" "${COMMON[@]}" \
      --tblout "$tmp/default.tbl" -A "$tmp/default.sto" "$QUERY" "$DB"
    env MSA_FASTA_ONEPASS=1 "$JACK" "${COMMON[@]}" \
      --tblout "$tmp/onepass.tbl" -A "$tmp/onepass.sto" "$QUERY" "$DB"
    awk 'NF && $0 !~ /^#/' "$tmp/default.tbl" > "$tmp/default.hits"
    awk 'NF && $0 !~ /^#/' "$tmp/onepass.tbl" > "$tmp/onepass.hits"
    test -s "$tmp/default.hits"
    cmp "$tmp/default.hits" "$tmp/onepass.hits"
    cmp "$tmp/default.sto" "$tmp/onepass.sto"
    echo "PASS: default/onepass identical cpu=$workers iterations=$iters"
  done
done

# Both must reject invalid alphabet characters, including binary >127.
printf '>bad\nAB-CD\n' > "$tmp/invalid.fasta"
if env -u MSA_FASTA_ONEPASS "$PACK" "$tmp/invalid.fasta" "$tmp/invalid.default" >/dev/null 2>&1; then
  echo "ERROR: legacy parser accepted an invalid FASTA" >&2; exit 1
fi
if MSA_FASTA_ONEPASS=1 "$PACK" "$tmp/invalid.fasta" "$tmp/invalid.fast" >/dev/null 2>&1; then
  echo "ERROR: one-pass parser accepted an invalid FASTA" >&2; exit 1
fi
echo "FASTA_ONEPASS_SMOKE=PASS"
