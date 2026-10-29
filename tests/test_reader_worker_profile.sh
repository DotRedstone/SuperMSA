#!/bin/bash
# Verify opt-in timing has no impact on HMMER hit/Stockholm output
# and that per-worker accounting conserves all blocks/records/residues.
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: use test/compute node" >&2; exit 2;;
esac
ROOT=$(cd "$(dirname "$0")/.." && pwd)
JACK="$ROOT/src/jackhmmer"
DB="$ROOT/data/demodb.fasta"
QUERY="$ROOT/data/query.fasta"
for f in "$JACK" "$DB" "$QUERY"; do test -s "$f"; done
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

for workers in 2 6; do
  for iterations in 1 3; do
    common=(--cpu "$workers" -N "$iterations" --noali
            --F1 0.0005 --F2 5e-05 --F3 5e-07 -E 0.001 -o /dev/null)
    env -u MSA_RW_PROFILE -u MSA_BIN8_DB -u MSA_DSQDATA_DB \
      "$JACK" "${common[@]}" --tblout "$tmp/base.tbl" -A "$tmp/base.sto" \
      "$QUERY" "$DB" 2> "$tmp/base.err"
    if grep -q '^MSA_RW_PROFILE' "$tmp/base.err"; then
      echo "ERROR: profile output appeared with profiling disabled" >&2;exit 1
    fi
    env -u MSA_BIN8_DB -u MSA_DSQDATA_DB MSA_RW_PROFILE=1 \
      "$JACK" "${common[@]}" --tblout "$tmp/profile.tbl" -A "$tmp/profile.sto" \
      "$QUERY" "$DB" 2> "$tmp/profile.err"
    grep -v '^#' "$tmp/base.tbl" > "$tmp/base.hits"
    grep -v '^#' "$tmp/profile.tbl" > "$tmp/profile.hits"
    test -s "$tmp/base.hits"
    cmp "$tmp/base.hits" "$tmp/profile.hits"
    cmp "$tmp/base.sto" "$tmp/profile.sto"
    python3 "$ROOT/scripts/check_reader_worker_profile.py" \
      "$tmp/profile.err" --workers "$workers"
    echo "PASS: opt-in reader-worker profiling workers=$workers iterations=$iterations"
  done
done
echo "READER_WORKER_PROFILE_SMOKE=PASS"
