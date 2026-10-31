#!/bin/bash
# 按 run.env 执行一组 trial（A=base，B=tuned），每个 trial 都是完整的 prologue + search。
# 正确性门槛：每个 trial 的 score.py 全部 correct，且命中表与第 1 个 trial 等价
# （有 REFERENCE_TBL 时也与它比较）。任一门槛失败立即停止。
# 用法：abba.sh <run_dir>（由 abba.slurm 调用；MSA_ALLOW_NO_SLURM=1 时可在本地测试）
set -euo pipefail

RUN=$(cd "${1:?usage: abba.sh <run_dir>}" && pwd)
cd "$RUN"
# shellcheck source=/dev/null
source ./run.env
die() { echo "ERROR: $*" >&2; echo "ABBA_RESULT=FAIL" >&2; exit 1; }

if [ -z "${SLURM_JOB_ID:-}" ] && [ "${MSA_ALLOW_NO_SLURM:-0}" != 1 ]; then
    die "只能在 Slurm 作业中运行"
fi
[ ! -e trials ] || die "trials/ 已存在，运行目录只写一次；请开新运行"

for sha in "$BASE_SHA" "$TUNED_SHA"; do
    (cd "$BUILDS/${sha:0:12}" && sha256sum --quiet -c BINARIES.sha256) \
        || die "build ${sha:0:12} 的二进制和编译时不一致"
done

# 数据：数据库和基线评分用软链接，查询只链接选中的子集。
mkdir -p data/query
ln -sfn "$DATA_SRC/database.fasta" data/database.fasta
[ ! -f "$DATA_SRC/baseline_roc10.tsv" ] || ln -sfn "$DATA_SRC/baseline_roc10.tsv" data/baseline_roc10.tsv
while IFS= read -r sid; do
    [ -s "$DATA_SRC/query/$sid.fasta" ] || die "缺少查询 $sid"
    ln -sfn "$DATA_SRC/query/$sid.fasta" "data/query/$sid.fasta"
done < queries.txt
nq=$(wc -l < queries.txt)

{
    echo "JOB_ID=${SLURM_JOB_ID:-local}"
    echo "NODE=$(hostname)"
    echo "STARTED_AT=$(date -Is)"
} >> run.env

printf 'trial\tarm\tsha\tprologue_s\tsearch_s\ttotal_s\tqueries\tcorrect\tequivalent\n' > summary.tsv
first_tbl=
for ((i = 0; i < ${#ORDER}; i++)); do
    arm=${ORDER:$i:1}
    trial=$(printf '%02d' $((i + 1)))
    if [ "$arm" = A ]; then sha=$BASE_SHA; envs=$BASE_ENV; else sha=$TUNED_SHA; envs=$TUNED_ENV; fi
    src=$BUILDS/${sha:0:12}
    out=$RUN/trials/$trial-$arm
    mkdir -p "$out"
    echo "=== trial $trial arm=$arm sha=${sha:0:12} env='$envs' $(date -Is)"

    # shellcheck disable=SC2086  # envs 是空格分隔的 K=V 列表
    env $envs DATA="$RUN/data" OUT="$out" bash "$src/prologue.sh" > "$out/prologue.log" 2>&1 \
        || { tail -n 30 "$out/prologue.log" >&2; die "trial $trial prologue 失败"; }
    prep=$(awk '/^prologue time  = / {print $4}' "$out/prologue.log")
    [[ $prep =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "trial $trial 无法解析 prologue time"

    # 资源参数为空时不传，让 run_queries.sh 使用自己的默认值（--official 模式，与正式入口一致）。
    knobs=()
    [ -z "$CPU" ] || knobs+=(CPU="$CPU")
    [ -z "$PARALLEL" ] || knobs+=(PARALLEL="$PARALLEL")
    [ -z "$WARMUP" ] || knobs+=(WARMUP="$WARMUP")
    # shellcheck disable=SC2086
    env $envs DATA="$RUN/data" OUT="$out" JACKHMMER="$src/src/jackhmmer" "${knobs[@]}" FORCE=1 \
        bash "$src/run_queries.sh" "$RUN/data" "$out" > "$out/search.log" 2>&1 \
        || { tail -n 30 "$out/search.log" >&2; die "trial $trial search 失败"; }
    read -r search ran skipped < <(awk -F '\t' 'NR==2 {print $1, $2, $3}' "$out/wall_time.tsv")
    [ "$ran" = "$nq" ] && [ "$skipped" = 0 ] || die "trial $trial 只跑了 $ran/$nq 条"

    correct=$(awk -F '\t' 'NR==1 {for (c = 1; c <= NF; c++) if ($c == "correct") k = c; next}
                           $k == "True" {n++} END {print n + 0}' "$out/scores.tsv")
    total=$(awk -v p="$prep" -v s="$search" 'BEGIN {printf "%.1f", p + s}')

    equiv=PASS
    if [ -z "$first_tbl" ]; then
        first_tbl=$out/tbl
    elif ! python3 compare_hit_tables.py --queries queries.txt "$first_tbl" "$out/tbl" > "$out/compare.log" 2>&1; then
        equiv=FAIL
    fi
    if [ "$equiv" = PASS ] && [ -n "${REFERENCE_TBL:-}" ] \
        && ! python3 compare_hit_tables.py --queries queries.txt "$REFERENCE_TBL" "$out/tbl" >> "$out/compare.log" 2>&1; then
        equiv=FAIL
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$trial" "$arm" "${sha:0:12}" "$prep" "$search" "$total" "$ran" "$correct/$nq" "$equiv" >> summary.tsv
    echo "trial $trial: prologue=$prep search=$search total=$total correct=$correct/$nq equivalent=$equiv"
    [ "$correct" = "$nq" ] || die "trial $trial ROC10 未全部通过（$correct/$nq）"
    [ "$equiv" = PASS ] || { cat "$out/compare.log" >&2; die "trial $trial 命中表与参照不等价"; }
done

echo "FINISHED_AT=$(date -Is)" >> run.env
python3 summarize.py "$RUN" | tee report.txt
