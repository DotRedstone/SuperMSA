#!/bin/bash
#SBATCH -J fasta_prep
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=56
#SBATCH --exclusive
#SBATCH -t 02:30:00
#SBATCH --no-requeue
#SBATCH -o fasta.%j.out

set -euo pipefail

RUN="$SLURM_SUBMIT_DIR"
test -f "$RUN/source/scripts/run_fasta_preprocess_sweep.sh" || {
  echo "ERROR: missing snapshotted comparison script" >&2
  exit 2
}
echo "Job: $SLURM_JOB_ID, Node: $(hostname), Started: $(date -Is)"
bash "$RUN/source/scripts/run_fasta_preprocess_sweep.sh"
echo "Completed: $(date -Is)"
