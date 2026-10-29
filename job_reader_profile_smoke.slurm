#!/bin/bash
#SBATCH -J msa_t5_smoke
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH -t 01:00:00
#SBATCH --no-requeue
#SBATCH -o smoke.%j.out
set -euo pipefail
cd "$SLURM_SUBMIT_DIR/source"
bash scripts/build_bin8_candidate.sh
bash tests/test_reader_worker_profile.sh
echo "READER_WORKER_PROFILE_BUILD_AND_SMOKE=PASS"
