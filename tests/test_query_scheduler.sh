#!/bin/bash
# Lightweight scheduler regression test with a fake jackhmmer.
# Run on test01 (NOT a login node): bash tests/test_query_scheduler.sh
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/msa-scheduler-test.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/repo/scripts" "$tmp/data/query"
cp "$REPO/run_queries.sh" "$tmp/repo/run_queries.sh"
cp "$REPO/scripts/query_worker.sh" "$tmp/repo/scripts/query_worker.sh"

cat > "$tmp/repo/score.py" <<'PY'
import pathlib, sys
args = sys.argv
out = args[args.index("--results") + 1]
pathlib.Path(out, "scoring_was_called").write_text("ok\n")
PY

cat > "$tmp/fake-jackhmmer" <<'SH'
#!/bin/bash
set -euo pipefail
tbl=""; sto=""; prev=""; last=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tblout) tbl="$2"; shift 2 ;;
        -A) sto="$2"; shift 2 ;;
        *) prev="$last"; last="$1"; shift ;;
    esac
done
sid=$(basename "$prev" .fasta)
if [ "${FAIL_SID:-}" = "$sid" ]; then
    [ "$tbl" = /dev/null ] || echo 'partial' > "$tbl"
    exit 9
fi
sleep 0.05
if [ "$tbl" != /dev/null ]; then
    printf '# fake table\nhit - %s - 1e-10\n' "$sid" > "$tbl"
fi
if [ -n "$sto" ] && [ "$sto" != /dev/null ]; then
    printf '# STOCKHOLM 1.0\n//\n' > "$sto"
fi
SH
chmod +x "$tmp/fake-jackhmmer"

printf '>db\nAAAA\n' > "$tmp/data/database.fasta"
for i in 01 02 03 04; do
    printf '>q%s\nAAAA\n' "$i" > "$tmp/data/query/q$i.fasta"
done

run() {
    local parallel="$1" out="$2"
    PARALLEL="$parallel" CPU=8 WARMUP=0 FORCE=1 \
        JACKHMMER="$tmp/fake-jackhmmer" \
        bash "$tmp/repo/run_queries.sh" "$tmp/data" "$out" > "$tmp/run.log" 2>&1
}

bash -n "$REPO/run_queries.sh"
bash -n "$REPO/scripts/query_worker.sh"
run 1 "$tmp/serial"
run 3 "$tmp/parallel"

diff -r "$tmp/serial/tbl" "$tmp/parallel/tbl"
test "$(find "$tmp/parallel/tbl" -name '*.tbl' | wc -l)" -eq 4
test "$(tail -n +2 "$tmp/parallel/timing.tsv" | wc -l)" -eq 4
test -f "$tmp/parallel/scoring_was_called"
awk -F '\t' 'NR==2 {exit !($2 == 4 && $3 == 0)}' "$tmp/parallel/wall_time.tsv"

PARALLEL=3 CPU=8 WARMUP=0 FORCE=0 \
    JACKHMMER="$tmp/fake-jackhmmer" \
    bash "$tmp/repo/run_queries.sh" "$tmp/data" "$tmp/parallel" > "$tmp/skip.log" 2>&1
awk -F '\t' 'NR==2 {exit !($2 == 0 && $3 == 4)}' "$tmp/parallel/wall_time.tsv"

if FAIL_SID=q02 PARALLEL=3 CPU=8 WARMUP=0 FORCE=1 \
    JACKHMMER="$tmp/fake-jackhmmer" \
    bash "$tmp/repo/run_queries.sh" "$tmp/data" "$tmp/failed" > "$tmp/fail.log" 2>&1; then
    echo 'FAIL: worker error did not fail the whole batch' >&2
    exit 1
fi
test ! -f "$tmp/failed/tbl/q02.tbl"
test ! -f "$tmp/failed/wall_time.tsv"
test ! -f "$tmp/failed/scoring_was_called"
echo 'PASS: serial/parallel outputs, timing, skips, and worker failure propagation'
