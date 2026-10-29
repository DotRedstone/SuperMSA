#!/bin/bash
# Queue geometry is purely a performance knob: no change in output rows.
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: use test01" >&2; exit 2;;
esac
ROOT=$(cd "$(dirname "$0")/.." && pwd)
JACK="$ROOT/src/jackhmmer"
DB="$ROOT/data/demodb.fasta"
QUERY="$ROOT/data/query.fasta"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
for iters in 1 3; do
  args=(--cpu 2 -N "$iters" --noali --F1 0.0005 --F2 5e-05 --F3 5e-07 -E 0.001 -o /dev/null)
  env -u MSA_BIN8_DB -u MSA_DSQDATA_DB -u MSA_BLOCK_SEQS -u MSA_QUEUE_FACTOR \
    "$JACK" "${args[@]}" \
    --tblout "$tmp/ref.tbl" -A "$tmp/ref.sto" "$QUERY" "$DB"
  for cfg in '256 2' '1024 4' '2048 2'; do
    read -r size factor <<< "$cfg"
    env -u MSA_BIN8_DB -u MSA_DSQDATA_DB MSA_BLOCK_SEQS="$size" MSA_QUEUE_FACTOR="$factor" \
      MSA_QUEUE_CONFIG_LOG=1 "$JACK" "${args[@]}" \
      --tblout "$tmp/test.tbl" -A "$tmp/test.sto" "$QUERY" "$DB" \
      2> "$tmp/config.log"
    grep -q "^MSA_QUEUE_CONFIG workers=2 block_seqs=$size queue_blocks=$((2*factor))$" "$tmp/config.log"
    diff -u <(grep -v '^#' "$tmp/ref.tbl") <(grep -v '^#' "$tmp/test.tbl")
    cmp "$tmp/ref.sto" "$tmp/test.sto"
    echo "PASS: block=$size queue_factor=$factor iterations=$iters"
  done
done
echo "QUEUE_GEOMETRY_SMOKE=PASS"
