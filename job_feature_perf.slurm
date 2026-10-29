#!/bin/bash
#SBATCH -J msa_t1_abba
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
test -s source/bin8.binaries.sha256 || {
  echo "ERROR: missing smoke-stage compiled binaries marker" >&2
  exit 2
}
(cd source && sha256sum -c bin8.binaries.sha256)
echo "PERF_START feature=t1 job=$SLURM_JOB_ID host=$(hostname) time=$(date -Is)"
bash source/scripts/run_feature_abba.sh
echo "PERF_FINISH feature=t1 time=$(date -Is)"
