#!/bin/bash
# Add-on 12-query comparison: timed Huffman vs native Easel DSQDATA.
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: do not benchmark on login node" >&2; exit 2 ;;
esac
: "${SLURM_JOB_ID:?requires sbatch}"
: "${SLURM_SUBMIT_DIR:?requires sbatch}"

RUN="$SLURM_SUBMIT_DIR"
ROOT="${BENCH_ROOT:-$HOME/WORK/dot}"
SRC="$RUN/source"
DATA_ORIGINAL="${BENCH_DATA:-$ROOT/preliminary}"
QUERY_LIST="${BENCH_QUERY_LIST:-$ROOT/experiments/supermsa/probes/parallel-scan-20261028_230525/queries.txt}"
ORIGINAL_TBL="${BENCH_BASELINE_TBL:-$ROOT/experiments/supermsa/runs/query-parallel-p6-t8-r01/results/tbl}"
SUMMARY="$RUN/summary.tsv"
die() { echo "ERROR: $*" >&2; exit 1; }

for f in "$SRC/prologue.sh" "$SRC/run_queries.sh" "$SRC/score.py" \
         "$SRC/scripts/query_worker.sh" "$SRC/scripts/fasta_to_bin8" \
         "$SRC/scripts/bin8_to_huffman" "$SRC/scripts/fasta_to_dsqdata" \
         "$SRC/src/jackhmmer"; do
  test -s "$f" || die "missing $f"
done
test -s "$QUERY_LIST" || die "missing query list: $QUERY_LIST"
test -s "$DATA_ORIGINAL/database.fasta" || die "missing official DB"
test -s "$DATA_ORIGINAL/baseline_roc10.tsv" || die "missing official baseline"
test -d "$ORIGINAL_TBL" || die "missing original v1 hit tables"
test "${SLURM_CPUS_PER_TASK:-0}" -ge 48 || die "need 48+ allocated CPUs"
test ! -e "$RUN/data" || die "data dir already exists"
test ! -e "$RUN/results" || die "results already exist"
test ! -e "$SUMMARY" || die "summary already exists"

mkdir -p "$RUN/data/query" "$RUN/results"
ln -s "$DATA_ORIGINAL/database.fasta" "$RUN/data/database.fasta"
ln -s "$DATA_ORIGINAL/baseline_roc10.tsv" "$RUN/data/baseline_roc10.tsv"
: > "$RUN/queries.selected"
while IFS= read -r line || test -n "$line"; do
  line="${line%$'\r'}"
  [[ -z "$line" || "$line" == \#* ]] && continue
  sid="${line##*/}"
  sid="${sid%.fasta}"
  [[ "$sid" =~ ^[A-Za-z0-9_.-]+$ ]] || die "invalid query ID $sid"
  test -s "$DATA_ORIGINAL/query/$sid.fasta" || die "missing FASTA query $sid"
  test ! -e "$RUN/data/query/$sid.fasta" || die "duplicate query ID $sid"
  ln -s "$DATA_ORIGINAL/query/$sid.fasta" "$RUN/data/query/$sid.fasta"
  printf '%s\n' "$sid" >> "$RUN/queries.selected"
done < "$QUERY_LIST"
test "$(wc -l < "$RUN/queries.selected")" -eq 12 || die "expected exactly 12 queries"

compare_rows() {
  local a="$1" b="$2" sid
  while IFS= read -r sid; do
    test -f "$a/$sid.tbl" || die "missing table: $a/$sid.tbl"
    test -f "$b/$sid.tbl" || die "missing table: $b/$sid.tbl"
    diff -q \
      <(awk 'NF && $0 !~ /^#/' "$a/$sid.tbl") \
      <(awk 'NF && $0 !~ /^#/' "$b/$sid.tbl") >/dev/null ||
      die "hit-row mismatch on query $sid (see $a vs $b)"
  done < "$RUN/queries.selected"
}

# Balanced order reduces systematic warm-cache / thermal ordering bias.
modes=(huff dsq dsq huff)
printf 'trial\tmode\tprologue_s\tsearch_s\ttotal_s\tqueries_run\tskipped\tquality\tidentical_v1\tencoded_bytes\tworkers_per_query\tunpackers_per_query\tbudget_threads\tobserved_peak_threads\tobserved_peak_processes\n' > "$SUMMARY"
for idx in "${!modes[@]}"; do
  trial=$(printf '%02d' "$((idx+1))")
  mode="${modes[$idx]}"
  flag=0
  huff_flag=0
  dsq_flag=0
  [ "$mode" = bin8 ] && flag=1
  [ "$mode" = huff ] && huff_flag=1
  [ "$mode" = dsq ] && dsq_flag=1
  out="$RUN/results/$trial-$mode"
  mkdir -p "$out"
  echo "=== $trial $mode $(date -Is) ==="

  DATA="$RUN/data" OUT="$out" BIN8_PREPROCESS="$flag" HUFF_PREPROCESS="$huff_flag" DSQDATA_PREPROCESS="$dsq_flag" \
     bash "$SRC/prologue.sh" > "$RUN/$trial-$mode.prologue.log" 2>&1 || {
       tail -n 50 "$RUN/$trial-$mode.prologue.log" >&2; die "prologue failed"
     }
  prep=$(awk '/^prologue time  = / {print $4}' "$RUN/$trial-$mode.prologue.log")
  [[ "$prep" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "bad prologue time"

  # 56 allocated CPUs: 6 searches, at most 54 JackHMMER threads.
  # Huffman: 8 workers + 1 main per search = 9
  # DSQDATA: 6 workers + 1 main + 1 loader + 1 unpacker = 9
  search_workers=8
  unpackers=0
  if [ "$mode" = dsq ]; then search_workers=6; unpackers=1; fi
  budget=$((6 * (search_workers + 1 + (dsq_flag * (1 + unpackers)))))
  [ "$budget" -le "${SLURM_CPUS_PER_TASK}" ] ||
    die "estimated JackHMMER thread budget exceeds CPU allocation ($budget)"
  echo "THREAD_BUDGET mode=$mode parallel=6 search_workers=$search_workers unpackers=$unpackers estimated=$budget allocated=${SLURM_CPUS_PER_TASK}"
  monitor_log="$RUN/$trial-$mode.threads.tsv"
  python3 "$SRC/scripts/monitor_search_threads.py" "$SRC/src/jackhmmer" 1 > "$monitor_log" &
  monitor_pid=$!
  if ! DATA="$RUN/data" OUT="$out" BIN8_PREPROCESS="$flag" HUFF_PREPROCESS="$huff_flag" DSQDATA_PREPROCESS="$dsq_flag" \
    MSA_DSQ_UNPACKERS="$unpackers" JACKHMMER="$SRC/src/jackhmmer" CPU="$search_workers" \
    PARALLEL=6 FORCE=1 WARMUP=1 \
    bash "$SRC/run_queries.sh" "$RUN/data" "$out" > "$RUN/$trial-$mode.search.log" 2>&1; then
    kill "$monitor_pid" 2>/dev/null || :
    wait "$monitor_pid" 2>/dev/null || :
    tail -n 60 "$RUN/$trial-$mode.search.log" >&2
    die "search failed"
  fi
  kill "$monitor_pid" 2>/dev/null || :
  wait "$monitor_pid" 2>/dev/null || :
  peak_threads=$(awk -F '\t' 'NR>1 && $3>max {max=$3} END{print max+0}' "$monitor_log")
  peak_procs=$(awk -F '\t' 'NR>1 && $2>max {max=$2} END{print max+0}' "$monitor_log")
  echo "THREAD_OBSERVED mode=$mode peak_threads=$peak_threads peak_processes=$peak_procs"
  [ "$peak_threads" -le "${SLURM_CPUS_PER_TASK}" ] ||
    die "observed JackHMMER thread count exceeds allocated CPUs ($peak_threads)"

  read -r search ran skipped < <(awk -F '\t' 'NR==2 {print $1, $2, $3}' "$out/wall_time.tsv")
  [[ "$search" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "bad search time"
  test "$ran" -eq 12 && test "$skipped" -eq 0 || die "not exactly 12 fresh queries"
  test "$(find "$out/tbl" -maxdepth 1 -name '*.tbl' | wc -l)" -eq 12 ||
    die "missing hit tables"
  awk -F '\t' '
    NR > 1 { n++; if ($14 != "True") {print "BAD:", $1, $14 > "/dev/stderr"; bad=1} }
    END {if (n != 12 || bad) exit 1}
  ' "$out/scores.tsv" || die "ROC10 quality check failed"
  compare_rows "$out/tbl" "$ORIGINAL_TBL"
  if [ "$idx" -eq 0 ]; then ref="$out/tbl"; else compare_rows "$out/tbl" "$ref"; fi

  total=$(awk -v a="$prep" -v b="$search" 'BEGIN {printf "%.1f",a+b}')
  bytes=0
  if [ "$flag" = 1 ]; then
    test -s "$out/prepared/database.bin8" || die "missing timed bin8 artifact"
    bytes=$(stat -c '%s' "$out/prepared/database.bin8")
  elif [ "$huff_flag" = 1 ]; then
    test -s "$out/prepared/database.huf" || die "missing timed huffman artifact"
    bytes=$(stat -c '%s' "$out/prepared/database.huf")
  elif [ "$dsq_flag" = 1 ]; then
    pfx="$out/prepared/database"
    bytes=0
    for file in "$pfx" "$pfx.dsqi" "$pfx.dsqm" "$pfx.dsqs"; do
      test -s "$file" || die "missing timed native DSQDATA artifact $file"
      bytes=$((bytes + $(stat -c '%s' "$file")))
    done
  fi
  printf '%s\t%s\t%s\t%s\t%s\t12\t0\tPASS\tYES\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$trial" "$mode" "$prep" "$search" "$total" "$bytes" \
      "$search_workers" "$unpackers" "$budget" "$peak_threads" "$peak_procs" >> "$SUMMARY"
  echo "PASS: mode=$mode prep=$prep search=$search total=$total hit rows identical"
done
echo "ALL_FOUR_NEW_FORMAT_TRIALS_COMPLETED=YES"
echo "SUMMARY=$SUMMARY"
