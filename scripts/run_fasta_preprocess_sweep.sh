#!/bin/bash
# Compare raw FASTA vs timed line-rewrapped FASTA on 12 official queries.
# Executed by job_fasta_preprocess_sweep.slurm on one exclusive compute node.
set -euo pipefail

case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: do not run on login node" >&2; exit 2 ;;
esac

: "${SLURM_JOB_ID:?this script requires a Slurm compute allocation}"
: "${SLURM_SUBMIT_DIR:?missing submit directory}"

RUN="$SLURM_SUBMIT_DIR"
ROOT="${BENCH_ROOT:-$HOME/WORK/dot}"
SRC="$RUN/source"
INPUT="${FASTA_DATA:-$ROOT/preliminary}"
ORIGINAL="${ORIGINAL_TBL:-$ROOT/experiments/supermsa/runs/query-parallel-p6-t8-r01/results/tbl}"
LIST="${FASTA_QUERY_LIST:-$ROOT/experiments/supermsa/probes/parallel-scan-20261028_230525/queries.txt}"
SUMMARY="$RUN/summary.tsv"

die() { echo "ERROR: $*" >&2; exit 1; }
for f in "$SRC/prologue.sh" "$SRC/run_queries.sh" "$SRC/score.py" "$SRC/scripts/query_worker.sh"; do
  test -s "$f" || die "missing $f"
done
test -x "$SRC/scripts/fasta_rewrap" || die "missing compiled transformer"
test -x "$SRC/src/jackhmmer" || die "missing baseline jackhmmer"
test -f "$INPUT/database.fasta" || die "missing input database"
test -s "$LIST" || die "missing query list"
test -d "$ORIGINAL" || die "missing original full benchmark tables"
test ! -e "$SUMMARY" || die "summary.tsv exists; use a new experiment directory"
test ! -e "$RUN/results" || die "results exists; use a new experiment directory"
test ! -e "$RUN/data" || die "data exists; use a new experiment directory"
test "${SLURM_CPUS_PER_TASK:-0}" -ge 48 || die "need at least 48 allocated CPUs"

mkdir -p "$RUN/data/query" "$RUN/results"
ln -s "$INPUT/database.fasta" "$RUN/data/database.fasta"
ln -s "$INPUT/baseline_roc10.tsv" "$RUN/data/baseline_roc10.tsv"
: > "$RUN/queries.selected"

while IFS= read -r line || test -n "$line"; do
  line="${line%$'\r'}"
  [[ -z "$line" || "$line" == \#* ]] && continue
  sid="${line##*/}"
  sid="${sid%.fasta}"
  [[ "$sid" =~ ^[A-Za-z0-9_.-]+$ ]] || die "bad query entry: $line"
  test -s "$INPUT/query/$sid.fasta" || die "missing query $sid"
  test ! -e "$RUN/data/query/$sid.fasta" || die "duplicated query $sid"
  ln -s "$INPUT/query/$sid.fasta" "$RUN/data/query/$sid.fasta"
  printf '%s\n' "$sid" >> "$RUN/queries.selected"
done < "$LIST"
test "$(wc -l < "$RUN/queries.selected")" -eq 12 || die "query list must select 12 queries"

compare_tables() {
  local left="$1" right="$2" sid
  while IFS= read -r sid; do
    test -f "$left/$sid.tbl" || die "missing left table: $sid"
    test -f "$right/$sid.tbl" || die "missing right table: $sid"
    if ! diff -q \
         <(awk 'NF && $0 !~ /^#/' "$left/$sid.tbl") \
         <(awk 'NF && $0 !~ /^#/' "$right/$sid.tbl") >/dev/null; then
      echo "MISMATCH: $sid ($left vs $right)" >&2
      return 1
    fi
  done < "$RUN/queries.selected"
}

echo "Job $SLURM_JOB_ID Node $(hostname) ; treatments: raw rewrap rewrap raw"
printf 'trial\tformat\tprologue_s\tsearch_s\ttotal_s\tqueries_run\tincorrect\tmatch_v1\n' > "$SUMMARY"
modes=(raw rewrap rewrap raw)
for idx in "${!modes[@]}"; do
  trial=$(printf '%02d' "$((idx+1))")
  mode="${modes[$idx]}"
  out="$RUN/results/$trial-$mode"
  mkdir -p "$out"
  if [ "$mode" = rewrap ]; then flag=1; else flag=0; fi
  echo "=== Trial $trial/04 : $mode ==="

  DATA="$RUN/data" OUT="$out" FASTA_PREPROCESS="$flag" \
      bash "$SRC/prologue.sh" > "$RUN/$trial-$mode.prologue.log" 2>&1 || {
        tail -n 40 "$RUN/$trial-$mode.prologue.log" >&2
        die "prologue failed: $mode"
      }

  prep=$(awk '/^prologue time  = / {print $4}' "$RUN/$trial-$mode.prologue.log")
  [[ "$prep" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "could not parse prologue time"

  DATA="$RUN/data" OUT="$out" FASTA_PREPROCESS="$flag" \
  JACKHMMER="$SRC/src/jackhmmer" CPU=8 PARALLEL=6 FORCE=1 WARMUP=1 \
      bash "$SRC/run_queries.sh" "$RUN/data" "$out" > "$RUN/$trial-$mode.search.log" 2>&1 || {
        tail -n 50 "$RUN/$trial-$mode.search.log" >&2
        die "search failed: $mode"
      }

  read -r search ran skipped < <(awk -F '\t' 'NR==2 {print $1, $2, $3}' "$out/wall_time.tsv")
  [[ "$search" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "bad search time: $search"
  test "$ran" -eq 12 || die "not all 12 queries ran"
  test "$skipped" -eq 0 || die "skipped=$skipped"
  count=$(find "$out/tbl" -maxdepth 1 -name '*.tbl' | wc -l)
  test "$count" -eq 12 || die "expected 12 hit tables"

  awk -F '\t' '
     NR>1 {n++; if ($14 != "True") { print "INCORRECT:", $1 > "/dev/stderr"; bad=1 }}
     END {if (n != 12 || bad) exit 1}
  ' "$out/scores.tsv" || die "ROC10 correctness check failed: $trial"

  compare_tables "$out/tbl" "$ORIGINAL" || die "changed hit rows compared to submitted v1"
  if [ "$idx" -eq 0 ]; then
    ref="$out/tbl"
  else
    compare_tables "$out/tbl" "$ref" || die "changed hit rows compared to raw trial 01"
  fi

  total=$(awk -v p="$prep" -v s="$search" 'BEGIN {printf "%.1f", p+s}')
  printf '%s\t%s\t%s\t%s\t%s\t12\t0\tYES\n' \
      "$trial" "$mode" "$prep" "$search" "$total" >> "$SUMMARY"
  echo "PASS: mode=$mode prologue=$prep search=$search total=$total 12/12 correct; hit rows identical"
done
echo "ALL_FOUR_TRIALS_COMPLETED=YES"
echo "SUMMARY=$SUMMARY"
