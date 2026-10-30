#!/usr/bin/env bash
# DP-01/V04 local/test-node check: no Slurm and no competition dataset.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
command -v gcc >/dev/null
command -v python3 >/dev/null
test -f "$ROOT/easel/libeasel.a"
test -x "$ROOT/src/jackhmmer"
test -s "$ROOT/data/demodb.fasta"
test -s "$ROOT/data/query.fasta"

python3 - "$tmp/edge.fasta" <<'PY'
import sys
with open(sys.argv[1], 'wb') as f:
    f.write(b'>alpha ' + b'X' * 4700 + b'\r\n')
    f.write(b'A' * 70000 + b'\r\n')
    f.write(b'>beta special\r\nAc D e F\r\nWXYZ*\r\n')
    f.write(b'>gamma\nQ\n')
    f.write(b'>delta\nM')
PY
printf '>bad\nAC-DE\n' > "$tmp/bad-gap.fasta"
printf '>bad\nAB\377CD\n' > "$tmp/bad-highbit.fasta"

gcc -std=c99 -O2 -Wall -Wextra -I"$ROOT/easel"     -o "$tmp/compare" "$ROOT/tests/test_fasta_read_chunk.c"     -L"$ROOT/easel" -leasel -pthread -lm
"$tmp/compare" "$ROOT/data/demodb.fasta" "$tmp/edge.fasta"     "$tmp/bad-gap.fasta" "$tmp/bad-highbit.fasta"

# Compare true jackhmmer outputs in serial/threaded, one/three iterations.
for workers in 0 2; do
  for iters in 1 3; do
    common=(--cpu "$workers" --noali --F1 0.0005 --F2 5e-05 --F3 5e-07
            -N "$iters" -E 0.001 -o /dev/null)
    for mode in 0 1; do
      MSA_FASTA_CHUNK_64K="$mode" "$ROOT/src/jackhmmer" "${common[@]}" \
        --tblout "$tmp/$mode.tbl" -A "$tmp/$mode.sto" \
        "$ROOT/data/query.fasta" "$ROOT/data/demodb.fasta" >/dev/null
      grep -v '^#' "$tmp/$mode.tbl" > "$tmp/$mode.hits"
    done
    test -s "$tmp/0.hits"
    cmp "$tmp/0.hits" "$tmp/1.hits"
    cmp "$tmp/0.sto" "$tmp/1.sto"
    echo "PASS: jackhmmer cpu=$workers iters=$iters"
  done
done
echo "FASTA_CHUNK_64K_SMOKE=PASS"
