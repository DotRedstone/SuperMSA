#!/bin/bash
#SBATCH -p cnall
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=56
#SBATCH --exclusive
#SBATCH --no-requeue
#SBATCH -t 03:00:00
#SBATCH -o slurm-%j.out
# 由 tools/bench/profile.sh 复制到运行目录后提交。每条查询单独 perf record（cycles:u，带调用栈），参数与正式运行相同。
set -euo pipefail
RUN=$SLURM_SUBMIT_DIR
cd "$RUN"
# shellcheck source=/dev/null
source ./run.env
command -v perf >/dev/null || { echo "ERROR: 计算节点上没有 perf" >&2; exit 2; }
(cd "$BUILD" && sha256sum --quiet -c BINARIES.sha256) || { echo "ERROR: build 与编译时不一致" >&2; exit 2; }
echo "JOB_ID=$SLURM_JOB_ID NODE=$(hostname) perf=$(perf --version) paranoid=$(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null)"

# 与正式路径一致：先用该 build 的 prologue 生成预处理产物（bin8 库）。
mkdir -p data/query out
ln -sfn "$DATA_SRC/database.fasta" data/database.fasta
for s in $SIDS; do ln -sfn "$DATA_SRC/query/$s.fasta" "data/query/$s.fasta"; done
# shellcheck disable=SC2086
env $ENVS DATA="$RUN/data" OUT="$RUN/out" bash "$BUILD/prologue.sh" > prologue.log 2>&1
grep 'prologue time' prologue.log
if [ -s out/prepared/database.bin8 ]; then export MSA_BIN8_DB=$RUN/out/prepared/database.bin8; fi
echo "MSA_BIN8_DB=${MSA_BIN8_DB:-<unset: raw FASTA>}"

for s in $SIDS; do
    t0=$(date +%s.%N)
    # shellcheck disable=SC2086
    env $ENVS perf record -q -o "$s.perf.data" -e cycles:u -F 199 -g -- \
        "$BUILD/src/jackhmmer" --cpu 8 --noali --F1 0.0005 --F2 5e-05 --F3 5e-07 -N 3 -E 0.001 -o /dev/null \
        --tblout "out/$s.tbl" "data/query/$s.fasta" "data/database.fasta" > "$s.jackhmmer.log" 2>&1
    secs=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}')
    echo "== $s: ${secs}s (含 perf 开销), hits=$(grep -vc '^#' "out/$s.tbl" || true)"
    perf report -q --stdio --no-children -g none -i "$s.perf.data" --sort symbol 2>/dev/null | grep -v '^$' | head -40 > "$s.top.txt"
    perf report -q --stdio --no-children -g none -i "$s.perf.data" --sort dso 2>/dev/null | grep -v '^$' | head -10 > "$s.dso.txt"
    head -25 "$s.top.txt"
done
echo "PROFILE_COMPLETED=YES"
