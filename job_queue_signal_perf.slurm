#!/bin/bash
#SBATCH -J msa_t4_abba
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=56
#SBATCH --exclusive
#SBATCH -t 03:30:00
#SBATCH --no-requeue
#SBATCH -o perf.%j.out
set -euo pipefail
cd "$SLURM_SUBMIT_DIR"
test -s source/bin8.binaries.sha256 ||
  { echo "ERROR: compiled binary hash marker missing" >&2; exit 2; }
(cd source && sha256sum -c bin8.binaries.sha256)
bash source/scripts/run_queue_signal_abba.sh
echo "QUEUE_SIGNAL_ABBA_JOB=PASS"
