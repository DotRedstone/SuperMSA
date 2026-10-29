#!/bin/bash
#SBATCH -J msa_e06_smoke
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH -t 00:50:00
#SBATCH --no-requeue
#SBATCH -o smoke.%j.out
set -euo pipefail
cd "$SLURM_SUBMIT_DIR/source"
echo "SMOKE_START feature=e06 job=$SLURM_JOB_ID host=$(hostname) time=$(date -Is)"
bash scripts/build_bin8_candidate.sh
export MSA_FASTA_CACHE_FLAGS=0
bash tests/test_fasta_onepass.sh
bash tests/test_fasta_direct_map.sh
bash tests/test_fasta_config_cache.sh
echo "SMOKE_SUCCESS feature=e06 marker=E06_FASTA_CONFIG_CACHE_SMOKE=PASS"
