#!/bin/bash
#SBATCH -J msa_t2_smoke
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH -t 00:50:00
#SBATCH --no-requeue
#SBATCH -o smoke.%j.out
set -euo pipefail
cd "$SLURM_SUBMIT_DIR/source"
echo "SMOKE_START feature=t2 job=$SLURM_JOB_ID host=$(hostname) time=$(date -Is)"
bash scripts/build_huffman_candidate.sh
BIN8_REFERENCE_CONVERTER="$PWD/scripts/fasta_to_bin8_reference" bash tests/test_bin8_batched_io.sh
echo "SMOKE_SUCCESS feature=t2 marker=BIN8_BATCHED_IO_SMOKE=PASS"
