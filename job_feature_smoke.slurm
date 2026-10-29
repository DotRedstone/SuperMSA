#!/bin/bash
#SBATCH -J msa_t1_smoke
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH -t 00:50:00
#SBATCH --no-requeue
#SBATCH -o smoke.%j.out
set -euo pipefail
cd "$SLURM_SUBMIT_DIR/source"
echo "SMOKE_START feature=t1 job=$SLURM_JOB_ID host=$(hostname) time=$(date -Is)"
bash scripts/build_bin8_candidate.sh
bash tests/test_fasta_onepass.sh
echo "SMOKE_SUCCESS feature=t1 marker=FASTA_ONEPASS_SMOKE=PASS"
