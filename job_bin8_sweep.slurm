#!/bin/bash
#SBATCH -J msa_bin8
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=56
#SBATCH --exclusive
#SBATCH -t 02:30:00
#SBATCH --no-requeue
#SBATCH -o bin8.%j.out

set -euo pipefail
RUN="$SLURM_SUBMIT_DIR"
test -f "$RUN/source/scripts/run_bin8_sweep.sh" || {
    echo "ERROR: missing snapshotted bin8 comparison script" >&2
    exit 2
}
echo "Job=$SLURM_JOB_ID Node=$(hostname) Started=$(date -Is)"
bash "$RUN/source/scripts/run_bin8_sweep.sh"
echo "Completed=$(date -Is)"
