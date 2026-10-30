#!/bin/bash
#SBATCH -J msa_parallel
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=56
#SBATCH --no-requeue
#SBATCH -o stdout.%j

# Submit from a new run directory with OUT, DATA, CPU, PARALLEL and FORCE set.
# Logs go to the submission directory. Preserve the original baseline job.
set -euo pipefail

SCRIPT=$(scontrol show job "$SLURM_JOB_ID" | sed -n 's/^ *Command=//p')
ROOT=$(cd "$(dirname "$SCRIPT")" && pwd)
[ -f "$ROOT/run_queries.sh" ] || { echo "ERROR: missing run_queries.sh under $ROOT" >&2; exit 1; }

export CPU=${CPU:-8}
export PARALLEL=${PARALLEL:-6}
echo "Parallel search: PARALLEL=$PARALLEL CPU=$CPU"
bash "$ROOT/prologue.sh"
bash "$ROOT/run_queries.sh"
