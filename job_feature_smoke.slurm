#!/bin/bash
#SBATCH -J msa_t3_smoke
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH -t 00:50:00
#SBATCH --no-requeue
#SBATCH -o smoke.%j.out
set -euo pipefail
cd "$SLURM_SUBMIT_DIR/source"
echo "SMOKE_START feature=t3 job=$SLURM_JOB_ID host=$(hostname) time=$(date -Is)"
bash scripts/build_bin8_candidate.sh
bash tests/test_queue_geometry.sh
# Supplementary /proc state samples. These are NOT direct starvation metrics.
MSA_BLOCK_SEQS=256 MSA_QUEUE_FACTOR=4 MSA_QUEUE_CONFIG_LOG=1 \
  python3 scripts/probe_worker_stalls.py "$SLURM_SUBMIT_DIR/toy-worker-states.tsv" -- \
  ./src/jackhmmer --cpu 2 -N 1 --noali -o /dev/null \
  data/query.fasta data/demodb.fasta > "$SLURM_SUBMIT_DIR/toy-stall-probe.log" 2>&1
echo "SMOKE_SUCCESS feature=t3 marker=QUEUE_GEOMETRY_SMOKE=PASS"
