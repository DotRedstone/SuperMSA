#!/bin/bash
#SBATCH -J msa_t4_smoke
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
python3 tests/test_compare_hit_tables.py
bash tests/test_queue_signal_one.sh
echo "QUEUE_SIGNAL_ONE_BUILD_AND_SMOKE=PASS"
