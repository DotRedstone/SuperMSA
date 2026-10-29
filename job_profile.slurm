#!/bin/bash
#SBATCH -J msa_hotspot
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=12
#SBATCH -t 00:30:00
#SBATCH --no-requeue
#SBATCH -o profile.%j.out

# Profile one representative query, not an existing benchmark process.
# Requires PROFILE_BIN, PROFILE_DATA and PROFILE_SID at submission time.
set -euo pipefail

RUN=${SLURM_SUBMIT_DIR:?}
BIN=${PROFILE_BIN:?export PROFILE_BIN}
DATA=${PROFILE_DATA:?export PROFILE_DATA}
SID=${PROFILE_SID:?export PROFILE_SID}
EVENT=${PROFILE_EVENT:-cycles:u}
CPU=${PROFILE_CPU:-8}

[[ "$SID" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Invalid SID: $SID" >&2; exit 2; }
test -x "$BIN"
test -s "$DATA/query/$SID.fasta"
test -s "$DATA/database.fasta"
command -v perf >/dev/null || { echo "ERROR: perf executable missing on compute node" >&2; exit 2; }
test ! -e "$RUN/perf.data" || { echo "ERROR: perf.data already exists; use a fresh run directory" >&2; exit 2; }

echo "Job=${SLURM_JOB_ID:-unknown} Node=$(hostname)"
echo "Binary=$BIN"
echo "Query=$SID CPU=$CPU Event=$EVENT"
echo "Perf=$(perf --version)"
echo "perf_event_paranoid=$(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null || echo unavailable)"
echo "Note: -g uses frame-pointer unwinding. Missing frames may require a debug/FP build."

# Report and data belong to this profiling experiment only.
# Keep exactly the search parameters used in the official 6x8 run.
perf record -o "$RUN/perf.data" \
    -e "$EVENT" -F 49 -g -- \
    "$BIN" --cpu "$CPU" \
    --noali --F1 0.0005 --F2 5e-05 --F3 5e-07 \
    -N 3 -E 0.001 -o /dev/null \
    --tblout "$RUN/$SID.tbl" -A "$RUN/$SID.sto" \
    "$DATA/query/$SID.fasta" "$DATA/database.fasta" \
    > "$RUN/jackhmmer.log" 2>&1

perf report --stdio -i "$RUN/perf.data" --sort dso,symbol > "$RUN/perf-report.txt"
echo "PROFILE_COMPLETED=YES"
echo "REPORT=$RUN/perf-report.txt"
