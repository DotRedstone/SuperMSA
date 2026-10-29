#!/bin/bash
# Run only via job_ssv_band_sweep.slurm on an allocated compute node.
set -euo pipefail

case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: cannot benchmark on login node" >&2; exit 2 ;;
esac

: "${SLURM_JOB_ID:?submit with sbatch}"
: "${SLURM_SUBMIT_DIR:?missing Slurm submit dir}"

RUN="$SLURM_SUBMIT_DIR"
ROOT="${BENCH_ROOT:-$HOME/WORK/dot}"
SRC="$RUN/source"
BINS="${BAND_BIN_DIR:-$ROOT/experiments/supermsa/probes/ssv-band-build-r01/bin}"
ORIGINAL="${BAND_ORIGINAL_TBL:-$ROOT/experiments/supermsa/runs/query-parallel-p6-t8-r01/results/tbl}"
QUERY_LIST="${BAND_QUERY_LIST:-$ROOT/experiments/supermsa/probes/parallel-scan-20261028_230525/queries.txt}"
DATA_SOURCE="${BAND_DATA:-$ROOT/preliminary}"
SUMMARY="$RUN/summary.tsv"

die() { echo "ERROR: $*" >&2; exit 1; }

test -f "$SRC/run_queries.sh" || die "missing snapshotted run_queries.sh"
test -f "$SRC/scripts/query_worker.sh" || die "missing snapshotted query_worker.sh"
test -f "$SRC/score.py" || die "missing snapshotted score.py"
test -s "$DATA_SOURCE/database.fasta" || die "missing database.fasta"
test -s "$DATA_SOURCE/baseline_roc10.tsv" || die "missing baseline ROC10 file"
test -f "$QUERY_LIST" || die "missing query list"
test -d "$ORIGINAL" || die "missing original 100-query hit tables"
test ! -e "$SUMMARY" || die "summary.tsv already exists: use a new run directory"
test ! -e "$RUN/results" || die "results already exist: use a new run directory"
test ! -e "$RUN/data" || die "data already staged: use a new run directory"
test "${SLURM_CPUS_PER_TASK:-0}" -ge 48 || die "need at least 48 allocated CPUs"

for b in 14 12 10 8; do
  test -x "$BINS/jackhmmer-band-$b" || die "binary missing: band=$b"
done
test -s "$BINS/../binaries.sha256" || die "missing build sha256 manifest"
(cd "$BINS/.." && sha256sum -c binaries.sha256) || die "binary checksums changed"

mkdir -p "$RUN/data/query" "$RUN/results"
ln -s "$DATA_SOURCE/database.fasta" "$RUN/data/database.fasta"
ln -s "$DATA_SOURCE/baseline_roc10.tsv" "$RUN/data/baseline_roc10.tsv"

# The original 12-query list can contain query IDs or paths to FASTA files.
: > "$RUN/queries.selected"
while IFS= read -r line || test -n "$line"; do
  line="${line%$'\r'}"
  [[ -z "$line" || "$line" == \#* ]] && continue
  sid="${line##*/}"
  sid="${sid%.fasta}"
  [[ "$sid" =~ ^[A-Za-z0-9_.-]+$ ]] || die "invalid query entry: $line"
  test -s "$DATA_SOURCE/query/$sid.fasta" || die "missing query FASTA for $sid"
  test ! -e "$RUN/data/query/$sid.fasta" || die "duplicate query: $sid"
  ln -s "$DATA_SOURCE/query/$sid.fasta" "$RUN/data/query/$sid.fasta"
  printf '%s\n' "$sid" >> "$RUN/queries.selected"
done < "$QUERY_LIST"

count=$(wc -l < "$RUN/queries.selected")
test "$count" -eq 12 || die "expected 12 query IDs, found $count; see $QUERY_LIST"
echo "Job=$SLURM_JOB_ID Node=$(hostname) CPU=8 PARALLEL=6 WARMUP=1 QueryCount=$count"
echo "Runs: 14 12 10 8 8 10 12 14"
printf 'trial\tband\tseconds\tqueries_run\tskipped\tmatching_original\tmatching_band14\n' > "$SUMMARY"

# Compare hit rows in rank order; comments can contain differing file paths.
compare_tables() {
  local left="$1" right="$2" sid
  while IFS= read -r sid; do
    test -s "$left/$sid.tbl" || die "missing / empty table: $left/$sid.tbl"
    test -s "$right/$sid.tbl" || die "missing / empty table: $right/$sid.tbl"
    if ! diff -q \
        <(awk 'NF && $0 !~ /^#/' "$left/$sid.tbl") \
        <(awk 'NF && $0 !~ /^#/' "$right/$sid.tbl") > /dev/null; then
      echo "MISMATCH: $sid ($left vs $right)" >&2
      return 1
    fi
  done < "$RUN/queries.selected"
}

bands=(14 12 10 8 8 10 12 14)
for idx in "${!bands[@]}"; do
  trial=$(printf '%02d' "$((idx+1))")
  band="${bands[$idx]}"
  out="$RUN/results/${trial}-band${band}"
  log="$RUN/${trial}-band${band}.log"
  echo "=== Trial $trial/08 : band=$band ==="
  mkdir -p "$out"
  DATA="$RUN/data" \
  OUT="$out" \
  JACKHMMER="$BINS/jackhmmer-band-$band" \
  CPU=8 PARALLEL=6 FORCE=1 WARMUP=1 \
      bash "$SRC/run_queries.sh" "$RUN/data" "$out" > "$log" 2>&1 || {
        tail -n 50 "$log" >&2
        die "benchmark failed: trial=$trial band=$band"
      }

  test -s "$out/wall_time.tsv" || die "missing wall time for $trial"
  read -r secs ran skipped < <(awk -F '\t' 'NR==2 {print $1, $2, $3}' "$out/wall_time.tsv")
  [[ "$secs" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "bad seconds: $secs"
  test "$ran" -eq 12 || die "expected 12 queries but saw $ran"
  test "$skipped" -eq 0 || die "skipped queries=$skipped"
  table_count=$(find "$out/tbl" -maxdepth 1 -name '*.tbl' | wc -l)
  test "$table_count" -eq 12 || die "expected 12 tables but saw $table_count"
  awk -F '\t' '
    NR > 1 { n++; if ($14 != "True") { print "BAD ROC10 correctness:", $1, $14 > "/dev/stderr"; bad=1 } }
    END { if (n != 12 || bad) exit 1 }
  ' "$out/scores.tsv" || die "ROC10 quality check failed on trial $trial"

  compare_tables "$out/tbl" "$ORIGINAL" || die "differs from original v1: trial $trial"
  if [ "$idx" -eq 0 ]; then
    ref="$out/tbl"
  else
    compare_tables "$out/tbl" "$ref" || die "differs from band14 trial1: trial $trial"
  fi
  printf '%s\t%s\t%s\t%s\t%s\tYES\tYES\n' \
    "$trial" "$band" "$secs" "$ran" "$skipped" >> "$SUMMARY"
  echo "PASS: band=$band time=${secs}s, correct=12/12, hit-tables identical to original v1"
done

echo "ALL_EIGHT_TRIALS_COMPLETED=YES"
echo "SUMMARY=$SUMMARY"
