#!/bin/bash
#SBATCH -J msa_4formats
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=56
#SBATCH --exclusive
#SBATCH -t 04:00:00
#SBATCH --no-requeue
#SBATCH -o fourformats.%j.out
set -euo pipefail
RUN="$SLURM_SUBMIT_DIR"
test -f "$RUN/source/scripts/run_four_formats_sweep.sh" || {
  echo "ERROR: no snapshotted four-format sweep runner" >&2; exit 2;
}
echo "Job=$SLURM_JOB_ID Node=$(hostname) Started=$(date -Is)"
echo "CPU_ALLOCATED=$SLURM_CPUS_PER_TASK"
echo "Balanced treatments: raw bin8 dsq huff huff dsq bin8 raw"
bash "$RUN/source/scripts/run_four_formats_sweep.sh"
echo "Completed=$(date -Is)"
