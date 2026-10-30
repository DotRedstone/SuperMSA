#!/bin/bash
# One query per process. Invoked by run_queries.sh via GNU xargs -P.
set -euo pipefail

qf=${1:?missing query FASTA}
: "${JACKHMMER:?}" "${CPU:?}" "${ITERS:?}" "${EVALUE:?}" "${FILTERS:?}" "${OUT:?}" "${DB:?}"

sid=$(basename "$qf" .fasta)
tmp=$(mktemp -d "$OUT/.query-${sid}.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT

args=(--cpu "$CPU" $FILTERS -N "$ITERS" -E "$EVALUE" -o /dev/null)
start=$(date +%s.%N)

# Publish only complete outputs; a failed jackhmmer must not leave a
# truncated hit table that a subsequent run could mistake for success.
"$JACKHMMER" "${args[@]}" \
    --tblout "$tmp/hits.tbl" -A "$tmp/msa.sto" "$qf" "$DB"
[ -f "$tmp/hits.tbl" ] || { echo "ERROR: missing hit table for $sid" >&2; exit 1; }

mv -f "$tmp/hits.tbl" "$OUT/tbl/$sid.tbl"
if [ -f "$tmp/msa.sto" ]; then
    mv -f "$tmp/msa.sto" "$OUT/msa/$sid.sto"
else
    # A search with no alignment may not produce a Stockholm file.
    rm -f "$OUT/msa/$sid.sto"
fi

seconds=$(awk -v a="$start" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}')
hits=$(grep -vc '^#' "$OUT/tbl/$sid.tbl" || true)
printf '%s\t%s\t%s\n' "$sid" "$seconds" "$hits" > "$tmp/timing.tsv"
mv -f "$tmp/timing.tsv" "$OUT/.query-timings/$sid.tsv"
