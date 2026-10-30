#!/usr/bin/env bash
# DP-02/V04：在 demo 库上验证 DSQDATA 往返无损，且 raw 与 DSQDATA 的命中表和 MSA 逐字节相同。
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: use test01, not login node" >&2; exit 2 ;;
esac
REPO=$(cd "$(dirname "$0")/.." && pwd)
JACK="$REPO/src/jackhmmer"
PACK5="$REPO/scripts/fasta_to_dsqdata"
VERIFY5="$REPO/scripts/verify_dsqdata"
DB="$REPO/data/demodb.fasta"
QUERY="$REPO/data/query.fasta"
for f in "$JACK" "$PACK5" "$VERIFY5" "$DB" "$QUERY"; do
  test -s "$f" || { echo "ERROR: missing $f" >&2; exit 1; }
done
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
"$PACK5" "$DB" "$tmp/database"
"$VERIFY5" "$DB" "$tmp/database"
for workers in 0 2; do
  for iters in 1 3; do
    prefix="$tmp/cpu${workers}-n${iters}"
    ARGS=(--cpu "$workers" --noali --F1 0.0005 --F2 5e-05 --F3 5e-07 \
          -N "$iters" -E 0.001 -o /dev/null)
    timeout --signal=TERM 120s env -u MSA_BIN8_DB -u MSA_DSQDATA_DB "$JACK" "${ARGS[@]}" \
      --tblout "$prefix.raw.tbl" -A "$prefix.raw.sto" "$QUERY" "$DB"
    timeout --signal=TERM 120s env -u MSA_BIN8_DB MSA_DSQDATA_DB="$tmp/database" MSA_DSQ_UNPACKERS=1 "$JACK" "${ARGS[@]}" \
      --tblout "$prefix.dsq.tbl" -A "$prefix.dsq.sto" "$QUERY" "$DB"
    awk 'NF && $0 !~ /^#/' "$prefix.raw.tbl" > "$prefix.raw.hits"
    awk 'NF && $0 !~ /^#/' "$prefix.dsq.tbl" > "$prefix.dsq.hits"
    test -s "$prefix.raw.hits" || { echo "FAIL: raw FASTA produced no hits" >&2; exit 1; }
    diff -u "$prefix.raw.hits" "$prefix.dsq.hits" || { echo "FAIL: hits workers=$workers iterations=$iters" >&2; exit 1; }
    diff -u "$prefix.raw.sto" "$prefix.dsq.sto" || { echo "FAIL: MSA workers=$workers iterations=$iters" >&2; exit 1; }
    echo "PASS: raw/DSQDATA identical workers=$workers iterations=$iters"
  done
done
echo "DSQDATA_SMOKE=PASS"
