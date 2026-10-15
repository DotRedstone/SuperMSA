#!/bin/bash
# 用法: run_queries.sh [data_dir] [out_dir]
#   data_dir  含 query/*.fasta 与 database.fasta，默认 ../preliminary（与仓库并列）
#   out_dir   默认 <repo>/results，也可用环境变量 OUT 指定
# 输出:
#   tbl/<sid>.tbl   命中表（评分输入）     msa/<sid>.sto  多序列比对
#   timing.tsv      逐条耗时（仅供参考）   wall_time.tsv  正式计时：预热结束 → 最后一条跑完
# 环境变量: JACKHMMER CPU(8) ITERS(3) EVALUE(0.001) FILTERS WARMUP(5) FORCE(0，设 1 重跑已有结果)
# 预热: 先对第一条 query 跑 WARMUP 次，把数据库读进 page cache，结果丢弃、不计时。
# 评分: data_dir 下有 baseline_roc10.tsv 时，逐条判定 ROC10 是否不低于基线的 90%。
set -euo pipefail

case $(hostname) in
    cln0[1-4]*|ibcln*)
        echo "ERROR: 禁止在登录节点运行程序。小规模测试请 ssh test01；完整运行请用 sbatch 提交（见 job_baseline.slurm）。" >&2
        exit 1;;
esac

REPO=$(cd "$(dirname "$0")" && pwd)
DATA=${1:-${DATA:-$(dirname "$REPO")/preliminary}}
OUT=${2:-${OUT:-$REPO/results}}
JACKHMMER=${JACKHMMER:-$REPO/src/jackhmmer}
CPU=${CPU:-8}
ITERS=${ITERS:-3}
EVALUE=${EVALUE:-0.001}
FILTERS=${FILTERS:---noali --F1 0.0005 --F2 5e-05 --F3 5e-07}
WARMUP=${WARMUP:-5}
FORCE=${FORCE:-0}
DB=$DATA/database.fasta
TIMING=$OUT/timing.tsv

die() { echo "ERROR: $*" >&2; exit 1; }
elapsed() { awk -v a="$1" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}'; }

[ -f "$DB" ]           || die "$DB not found"
[ -d "$DATA/query" ]   || die "$DATA/query not found"
[ -x "$JACKHMMER" ]    || die "jackhmmer not executable: $JACKHMMER"
queries=("$DATA"/query/*.fasta)
[ -e "${queries[0]}" ] || die "no *.fasta in $DATA/query"

mkdir -p "$OUT/tbl" "$OUT/msa" 2>/dev/null && touch "$OUT/.write_test" 2>/dev/null \
    || die "输出目录不可写: $OUT（home 在计算节点只读，请把仓库放在 ~/WORK 下或指定 out_dir）"
rm -f "$OUT/.write_test"
[ -f "$TIMING" ] && [ "$FORCE" = 0 ] || echo -e "sid\tseconds\thits" > "$TIMING"

ARGS=(--cpu "$CPU" $FILTERS -N "$ITERS" -E "$EVALUE" -o /dev/null)
total=${#queries[@]}

if [ "$WARMUP" -gt 0 ]; then
    echo "预热 $WARMUP 次（不计时）..."
    for _ in $(seq "$WARMUP"); do
        "$JACKHMMER" "${ARGS[@]}" --tblout /dev/null "${queries[0]}" "$DB"
    done
fi

i=0; ran=0; skipped=0
t_all=$(date +%s.%N)
for qf in "${queries[@]}"; do
    sid=$(basename "$qf" .fasta)
    i=$((i + 1))
    if [ "$FORCE" = 0 ] && [ -s "$OUT/tbl/$sid.tbl" ]; then
        echo "[$i/$total] $sid: exists, skip"
        skipped=$((skipped + 1))
        continue
    fi
    ran=$((ran + 1))
    t0=$(date +%s.%N)
    "$JACKHMMER" "${ARGS[@]}" --tblout "$OUT/tbl/$sid.tbl" -A "$OUT/msa/$sid.sto" "$qf" "$DB"
    secs=$(elapsed "$t0")
    hits=$(grep -vc '^#' "$OUT/tbl/$sid.tbl" || true)
    echo -e "$sid\t$secs\t$hits" >> "$TIMING"
    echo "[$i/$total] $sid: ${secs}s, $hits hits"
done

wall=$(elapsed "$t_all")
echo -e "seconds\tqueries_run\tskipped\n$wall\t$ran\t$skipped" > "$OUT/wall_time.tsv"
echo "正式计时: ${wall} s（运行 $ran 条，跳过 $skipped 条）"
[ "$skipped" = 0 ] || echo "WARNING: 有 $skipped 条沿用已有结果，计时无效；正式测试请清空输出目录或设 FORCE=1" >&2

BASELINE=$DATA/baseline_roc10.tsv
[ -f "$BASELINE" ] || BASELINE=
python3 "$REPO/score.py" --data "$DATA" --results "$OUT" ${BASELINE:+--baseline "$BASELINE"} || echo "warning: scoring step failed" >&2
