#!/bin/bash
#SBATCH -J msa_huffman
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=56
#SBATCH --exclusive
#SBATCH -t 03:00:00
#SBATCH --no-requeue
#SBATCH -o huffman.%j.out

set -euo pipefail
RUN="$SLURM_SUBMIT_DIR"
test -f "$RUN/source/scripts/run_huffman_sweep.sh" || {
  echo "ERROR: missing snapshotted Huffman sweep runner" >&2
  exit 2
}
echo "Job=$SLURM_JOB_ID Node=$(hostname) Started=$(date -Is)"
bash "$RUN/source/scripts/run_huffman_sweep.sh"
echo "Completed=$(date -Is)"
