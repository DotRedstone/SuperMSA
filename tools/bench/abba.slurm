#!/bin/bash
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=56
#SBATCH --exclusive
#SBATCH --no-requeue
#SBATCH -o slurm-%j.out
# 由 tools/bench/new_run.sh 复制到运行目录并在该目录 sbatch；不要直接手动提交仓库里的这一份。
set -euo pipefail
exec bash "$SLURM_SUBMIT_DIR/abba.sh" "$SLURM_SUBMIT_DIR"
