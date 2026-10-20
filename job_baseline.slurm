#!/bin/bash
#SBATCH -J msa_baseline
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH -o stdout.%j
#SBATCH --no-requeue
#SBATCH --ntasks-per-node=56
# 不设 #SBATCH -e：stderr 与 stdout 合并进同一个日志 stdout.%j

# 用法: sbatch <repo>/job_baseline.slurm（日志 stdout.%j 写到提交目录）
#       sbatch --wait ... 会阻塞到作业结束，退出码即作业退出码，便于脚本化同步等待。
# 流程: prologue.sh（预处理，计时）→ run_queries.sh（搜索 + 评分），全部输出在同一个日志里。
# 数据默认取<repo>旁的 ../preliminary，结果写到 <repo>/results；可用环境变量 DATA / OUT / CPU 覆盖。
# 基线约 5–6 小时，分区有时长上限时请加 #SBATCH -t。

SCRIPT=$0
[ -n "${SLURM_JOB_ID:-}" ] && SCRIPT=$(scontrol show job "$SLURM_JOB_ID" | sed -n 's/^ *Command=//p')
ROOT=$(cd "${SLURM_SUBMIT_DIR:-.}" && cd "$(dirname "$SCRIPT")" && pwd)
[ -f "$ROOT/run_queries.sh" ] || { echo "ERROR: 找不到 $ROOT/run_queries.sh" >&2; exit 1; }

# module load compilers/gcc/v12.2.0    # 若编译时用了 module 中的 gcc，在此加载同一环境

bash "$ROOT/prologue.sh" || { echo "ERROR: prologue.sh 失败，终止作业" >&2; exit 1; }
bash "$ROOT/run_queries.sh"
