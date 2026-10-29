#!/bin/bash
# Queue wakeup policy correctness under iterative multithreaded searches.
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: no compute tests on login node" >&2; exit 2;;
esac
ROOT=$(cd "$(dirname "$0")/.." && pwd)
JACK="$ROOT/src/jackhmmer"
DB="$ROOT/data/demodb.fasta"
Q="$ROOT/data/query.fasta"
for f in "$JACK" "$DB" "$Q"; do test -s "$f"; done
command -v timeout
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
unset MSA_BIN8_DB MSA_DSQDATA_DB

for cpu in 2 6; do
  for iterations in 1 3; do
    args=(--cpu "$cpu" -N "$iterations" --noali
          --F1 0.0005 --F2 5e-05 --F3 5e-07 -E 0.001 -o /dev/null)
    for pass in 1 2 3; do
      base="$TMP/default.c${cpu}.i${iterations}.p${pass}"
      tuned="$TMP/signal.c${cpu}.i${iterations}.p${pass}"
      env -u MSA_WQ_SIGNAL_ONE timeout 120s "$JACK" "${args[@]}" \
        --tblout "$base.tbl" -A "$base.sto" "$Q" "$DB"
      MSA_WQ_SIGNAL_ONE=1 timeout 120s "$JACK" "${args[@]}" \
        --tblout "$tuned.tbl" -A "$tuned.sto" "$Q" "$DB"
      awk 'NF && $0 !~ /^#/' "$base.tbl" > "$base.hits"
      awk 'NF && $0 !~ /^#/' "$tuned.tbl" > "$tuned.hits"
      test -s "$base.hits"
      cmp "$base.hits" "$tuned.hits" ||
        { echo "ERROR: hit difference cpu=$cpu iterations=$iterations pass=$pass" >&2; exit 1; }
      cmp "$base.sto" "$tuned.sto" ||
        { echo "ERROR: alignment difference cpu=$cpu iterations=$iterations pass=$pass" >&2; exit 1; }
      echo "PASS: queue_signal_one cpu=$cpu iterations=$iterations pass=$pass"
    done
  done
done
echo "QUEUE_SIGNAL_ONE_SMOKE=PASS"
