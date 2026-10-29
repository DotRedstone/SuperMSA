#!/bin/bash
#SBATCH -J msa_t5_probe
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH -t 01:30:00
#SBATCH --no-requeue
#SBATCH -o profile.%j.out
set -euo pipefail
RUN="$SLURM_SUBMIT_DIR"
SRC="$RUN/source"
DATA="$HOME/WORK/dot/preliminary"
QUERY="$DATA/query/Q9CIV7_1.fasta"
DB="$DATA/database.fasta"
for f in "$QUERY" "$DB" "$SRC/src/jackhmmer"; do
  test -s "$f" || { echo "ERROR: missing $f" >&2;exit 2; }
done
(cd "$SRC" && sha256sum -c bin8.binaries.sha256)
test ! -e "$RUN/probe" || { echo "ERROR: probe directory already exists" >&2;exit 2; }
mkdir "$RUN/probe"
COMMON=(--cpu 7 -N 3 --noali --F1 0.0005 --F2 5e-05 --F3 5e-07 -E 0.001 -o /dev/null)
env -u MSA_RW_PROFILE -u MSA_BIN8_DB -u MSA_DSQDATA_DB \
  "$SRC/src/jackhmmer" "${COMMON[@]}" \
  --tblout "$RUN/probe/base.tbl" -A "$RUN/probe/base.sto" \
  "$QUERY" "$DB" > "$RUN/probe/base.out" 2> "$RUN/probe/base.err"
env -u MSA_BIN8_DB -u MSA_DSQDATA_DB MSA_RW_PROFILE=1 \
  "$SRC/src/jackhmmer" "${COMMON[@]}" \
  --tblout "$RUN/probe/profile.tbl" -A "$RUN/probe/profile.sto" \
  "$QUERY" "$DB" > "$RUN/probe/profile.out" 2> "$RUN/probe/profile.err"
cmp <(grep -v '^#' "$RUN/probe/base.tbl") \
    <(grep -v '^#' "$RUN/probe/profile.tbl")
cmp "$RUN/probe/base.sto" "$RUN/probe/profile.sto"
python3 "$SRC/scripts/check_reader_worker_profile.py" \
  "$RUN/probe/profile.err" --workers 7 | tee "$RUN/probe/timing-summary.txt"
echo "READER_WORKER_FULL_DB_PROBE=PASS"
