#!/bin/bash
#SBATCH -J ssv_band
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=56
#SBATCH --exclusive
#SBATCH -t 03:00:00
#SBATCH --no-requeue
#SBATCH -o band.%j.out

set -euo pipefail

RUN="$SLURM_SUBMIT_DIR"
test -f "$RUN/source/scripts/run_ssv_band_sweep.sh" || {
  echo "ERROR: missing snapshotted sweep script under $RUN/source/scripts" >&2
  exit 2
}
echo "Allocated node: $(hostname)"
echo "Job ID: $SLURM_JOB_ID"
echo "Source snapshot: $RUN/source"
echo "Started: $(date -Is)"
bash "$RUN/source/scripts/run_ssv_band_sweep.sh"
echo "Finished: $(date -Is)"
