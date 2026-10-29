#!/bin/bash
#SBATCH -J msa_t3_smoke
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH -t 00:50:00
#SBATCH --no-requeue
#SBATCH -o smoke.%j.out
set -euo pipefail
cd "$SLURM_SUBMIT_DIR/source"
echo "SMOKE_START feature=t3 job=$SLURM_JOB_ID host=$(hostname) time=$(date -Is)"
bash scripts/build_bin8_candidate.sh
bash tests/test_queue_geometry.sh
echo "SMOKE_SUCCESS feature=t3 marker=QUEUE_GEOMETRY_SMOKE=PASS"
