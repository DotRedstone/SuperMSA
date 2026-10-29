#!/bin/bash
#SBATCH -J msa_t2_abba
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
test -s source/four_way.binaries.sha256 || {
  echo "ERROR: missing smoke-stage compiled binaries marker" >&2
  exit 2
}
echo "PERF_START feature=t2 job=$SLURM_JOB_ID host=$(hostname) time=$(date -Is)"
bash source/scripts/run_feature_abba.sh
echo "PERF_FINISH feature=t2 time=$(date -Is)"
