#!/bin/bash
# Correctness-gated 12-query ABBA run; feature-specific source snapshot.
set -euo pipefail
: "${SLURM_JOB_ID:?Run via sbatch}"
: "${SLURM_SUBMIT_DIR:?Run via sbatch}"
: "${SLURM_CPUS_PER_TASK:?Missing CPU allocation}"
FEATURE="t3"
RUN="$SLURM_SUBMIT_DIR"
SRC="$RUN/source"
ROOT="$HOME/WORK/dot"
INPUT="$ROOT/preliminary"
QFILE="$ROOT/experiments/supermsa/probes/parallel-scan-20261028_230525/queries.txt"
REF_TBL="$ROOT/experiments/supermsa/runs/query-parallel-p6-t8-r01/results/tbl"
SUMMARY="$RUN/summary.tsv"
die(){ echo "ERROR: $*" >&2; exit 1; }
test "$SLURM_CPUS_PER_TASK" -ge 56 || die "need 56 CPUs"
test ! -e "$RUN/results" && test ! -e "$SUMMARY" || die "pilot already exists"
test -s "$INPUT/database.fasta" && test -s "$INPUT/baseline_roc10.tsv" || die "input missing"
test -s "$QFILE" && test -d "$REF_TBL" || die "reference queries or tables missing"
test -x "$SRC/src/jackhmmer" || die "candidate not built"
if [ "$FEATURE" = t2 ]; then
  test -x "$SRC/scripts/fasta_to_bin8_reference" || die "missing pinned reference converter"
  test -x "$SRC/scripts/fasta_to_bin8" || die "missing optimized converter"
fi
mkdir -p "$RUN/data/query" "$RUN/results"
ln -s "$INPUT/database.fasta" "$RUN/data/database.fasta"
ln -s "$INPUT/baseline_roc10.tsv" "$RUN/data/baseline_roc10.tsv"
: > "$RUN/queries.selected"
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  [[ -z "$line" || "$line" == \#* ]] && continue
  sid="${line##*/}"
  sid="${sid%.fasta}"
  [[ "$sid" =~ ^[A-Za-z0-9_.-]+$ ]] || die "bad query id: $sid"
  test -s "$INPUT/query/$sid.fasta" || die "missing $sid"
  test ! -e "$RUN/data/query/$sid.fasta" || die "duplicate query id"
  ln -s "$INPUT/query/$sid.fasta" "$RUN/data/query/$sid.fasta"
  echo "$sid" >> "$RUN/queries.selected"
done < "$QFILE"
test "$(wc -l < "$RUN/queries.selected")" -eq 12 || die "expected 12 queries"
comparetbl(){
  local from="$1" to="$2"
  python3 "$SRC/scripts/compare_hit_tables.py" \
    --queries "$RUN/queries.selected" "$to" "$from" ||
    die "hit-identity/score/ranking validation failed; see comparator diagnostics"
}
printf 'trial\tfeature\tmode\tprologue_s\tsearch_s\ttotal_s\tqueries_run\tquality\tidentical_v1\tworker_threads\twarmup_runs\n' > "$SUMMARY"
modes=(base tuned tuned base)
for i in "${!modes[@]}"; do
  mode="${modes[$i]}"
  trial=$(printf '%02d' "$((i+1))")
  OUT="$RUN/results/$trial-$mode"
  mkdir -p "$OUT"
  export MSA_FASTA_ONEPASS=0 MSA_BLOCK_SEQS=1000 MSA_QUEUE_FACTOR=2
  export BIN8_PREPROCESS=0 HUFF_PREPROCESS=0 DSQDATA_PREPROCESS=0
  unset BIN8_CONVERTER MSA_BIN8_DB MSA_DSQDATA_DB
  case "$FEATURE:$mode" in
    t1:tuned) export MSA_FASTA_ONEPASS=1;;
    t2:base) export BIN8_PREPROCESS=1 BIN8_CONVERTER="$SRC/scripts/fasta_to_bin8_reference";;
    t2:tuned) export BIN8_PREPROCESS=1 BIN8_CONVERTER="$SRC/scripts/fasta_to_bin8";;
    t3:tuned) export MSA_BLOCK_SEQS=256 MSA_QUEUE_FACTOR=4;;
  esac
  echo "BEGIN feature=$FEATURE mode=$mode $(date -Is)"
  DATA="$RUN/data" OUT="$OUT" bash "$SRC/prologue.sh" > "$RUN/$trial-$mode.prologue.log" 2>&1 ||
    { tail -n 70 "$RUN/$trial-$mode.prologue.log" >&2; die "prologue failed"; }
  prep=$(awk '/^prologue time  = / {print $4}' "$RUN/$trial-$mode.prologue.log")
  [[ "$prep" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "bad prep time"
  DATA="$RUN/data" OUT="$OUT" JACKHMMER="$SRC/src/jackhmmer" \
    CPU=7 PARALLEL=6 ITERS=3 WARMUP=1 FORCE=1 \
    bash "$SRC/run_queries.sh" "$RUN/data" "$OUT" > "$RUN/$trial-$mode.search.log" 2>&1 ||
    { tail -n 70 "$RUN/$trial-$mode.search.log" >&2; die "search failed"; }
  read -r search ran skipped < <(awk -F '\t' 'NR==2{print $1,$2,$3}' "$OUT/wall_time.tsv")
  [[ "$search" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "bad search time"
  [ "$ran" -eq 12 ] && [ "$skipped" -eq 0 ] || die "queries skipped or incomplete"
  [ "$(find "$OUT/tbl" -maxdepth 1 -name '*.tbl' | wc -l)" -eq 12 ] ||
    die "expected 12 tables"
  awk -F '\t' 'NR>1 {n++; if($14!="True") bad=1} END{exit(n!=12 || bad)}' "$OUT/scores.tsv" ||
    die "ROC10 quality checks failed"
  comparetbl "$OUT/tbl" "$REF_TBL"
  if [ "$i" -eq 0 ]; then first="$OUT/tbl"; else comparetbl "$OUT/tbl" "$first"; fi
  total=$(awk -v p="$prep" -v s="$search" 'BEGIN{printf "%.1f",p+s}')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t12\tPASS\tYES\t48\t1\n' \
    "$trial" "$FEATURE" "$mode" "$prep" "$search" "$total" >> "$SUMMARY"
  echo "PASS: trial=$trial feature=$FEATURE mode=$mode prep=$prep search=$search total=$total"
done
echo "FEATURE_ABBA_COMPLETED=YES feature=$FEATURE"
