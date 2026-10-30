#!/bin/bash
# 创建一个运行目录并提交 Slurm 作业（登录节点可用：只做 git/mkdir/sbatch）。
#
#   tools/bench/new_run.sh --task DP-02 --variant V02-bin8 --tuned perf/dp-02/v02-bin8 \
#       --tuned-env 'MSA_DP_BIN8=1' --queries q100 [--base main] [--base-env ''] \
#       [--order ABBA] [--cpu 8] [--parallel 6] [--warmup 1] [--time 06:00:00] [--dry-run]
#       [--reference-tbl DIR]   每个 trial 的命中表还要与 DIR 中的表等价（例如历史基线）
#
# 单臂运行（例如验证基线）：--order A，此时只用 --base。
# 两臂默认用同一个 build（--base 默认等于 --tuned），只靠环境变量切换，变量最少。
# 运行目录：$MSA_WS/experiments/supermsa/<domain>/<task>/<variant>/rNN-<queries>/
set -euo pipefail

WS=${MSA_WS:-$HOME/WORK/dot}
REPO=${MSA_REPO:-$WS/SuperMSA}
EXP=$WS/experiments/supermsa
die() { echo "ERROR: $*" >&2; exit 1; }
# 集群上的 git 是 1.8.3，不支持 git -C；分支名找不到时自动尝试 origin/<分支名>。
g() { (cd "$REPO" && git "$@"); }
resolve_sha() {
    g rev-parse -q --verify "$1^{commit}" 2>/dev/null || g rev-parse -q --verify "origin/$1^{commit}" 2>/dev/null
}

task= variant= base= tuned= base_env= tuned_env= queries=q12 order=ABBA
cpu=8 parallel=6 warmup=1 time_limit= dry=0 reference=
while [ $# -gt 0 ]; do
    case $1 in
        --task) task=$2; shift 2;;
        --variant) variant=$2; shift 2;;
        --base) base=$2; shift 2;;
        --tuned) tuned=$2; shift 2;;
        --base-env) base_env=$2; shift 2;;
        --tuned-env) tuned_env=$2; shift 2;;
        --queries) queries=$2; shift 2;;
        --order) order=$2; shift 2;;
        --cpu) cpu=$2; shift 2;;
        --parallel) parallel=$2; shift 2;;
        --warmup) warmup=$2; shift 2;;
        --time) time_limit=$2; shift 2;;
        --reference-tbl) reference=$2; shift 2;;
        --dry-run) dry=1; shift;;
        *) die "unknown option $1";;
    esac
done

[[ $task =~ ^(DP|CK|QS|SA|EV)-[0-9]{2}$ ]] || die "--task 形如 DP-02"
[[ $variant =~ ^V[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "--variant 形如 V02-bin8"
[[ $order =~ ^[AB]+$ ]] || die "--order 只能由 A/B 组成"
[[ $queries =~ ^q[0-9]+$ ]] || die "--queries 形如 q12、q100"
qfile=$REPO/tools/bench/querysets/$queries.txt
[ -s "$qfile" ] || die "没有查询集 $qfile"
[ -n "$base" ] || base=$tuned
[ -n "$base" ] || die "至少需要 --base 或 --tuned"
[[ $order != *B* ]] || [ -n "$tuned" ] || die "order 含 B 时需要 --tuned"
[ -n "$tuned" ] || tuned=$base

builds=$EXP/builds
resolve() {
    local sha
    sha=$(resolve_sha "$1") || die "无法解析 $1（先在 $REPO 执行 git pull）"
    [ -f "$builds/${sha:0:12}/BINARIES.sha256" ] || die "$1 (${sha:0:12}) 尚未编译：在 test01 上执行 tools/bench/build.sh $1"
    echo "$sha"
}
base_sha=$(resolve "$base")
tuned_sha=$(resolve "$tuned")
[ -z "$reference" ] || [ -d "$reference" ] || die "--reference-tbl 不是目录：$reference"
nq=$(grep -cvE '^\s*(#|$)' "$qfile")

# 默认时限：每条查询每个 trial 按 1 分钟估算，再加 30 分钟余量。
[ -n "$time_limit" ] || time_limit=$(( ${#order} * nq + 30 ))

domain=$(echo "${task:0:2}" | tr 'A-Z' 'a-z')
parent=$EXP/$domain/$task/$variant
n=1
while compgen -G "$parent/r$(printf %02d $n)-*" > /dev/null; do n=$((n + 1)); done
run=$parent/r$(printf %02d $n)-$queries

harness_sha=$(g rev-parse HEAD)
echo "run=$run"
echo "base=$base ${base_sha:0:12} env='$base_env'"
echo "tuned=$tuned ${tuned_sha:0:12} env='$tuned_env'"
echo "order=$order queries=$queries($nq) cpu=$cpu parallel=$parallel warmup=$warmup time=$time_limit"
[ "$dry" = 0 ] || exit 0

[ -z "$(g status --porcelain)" ] || die "$REPO 有未提交改动，集群上的仓库只能通过 push 更新"
mkdir -p "$run"
cp "$REPO/tools/bench/abba.sh" "$REPO/tools/bench/abba.slurm" \
   "$REPO/tools/bench/compare_hit_tables.py" "$REPO/tools/bench/summarize.py" "$run/"
grep -vE '^\s*(#|$)' "$qfile" > "$run/queries.txt"
{
    printf 'TASK=%q\nVARIANT=%q\nRUN_ID=%q\n' "$task" "$variant" "$(basename "$run")"
    printf 'BASE_REF=%q\nBASE_SHA=%q\nBASE_ENV=%q\n' "$base" "$base_sha" "$base_env"
    printf 'TUNED_REF=%q\nTUNED_SHA=%q\nTUNED_ENV=%q\n' "$tuned" "$tuned_sha" "$tuned_env"
    printf 'ORDER=%q\nQUERIES=%q\nCPU=%q\nPARALLEL=%q\nWARMUP=%q\n' "$order" "$queries" "$cpu" "$parallel" "$warmup"
    [ -z "$reference" ] || printf 'REFERENCE_TBL=%q\n' "$reference"
    printf 'BUILDS=%q\nDATA_SRC=%q\nHARNESS_SHA=%q\nCREATED_AT=%q\n' \
        "$builds" "${DATA:-$WS/preliminary}" "$harness_sha" "$(date -Is)"
} > "$run/run.env"

job=$(cd "$run" && sbatch --parsable -J "${task}-${variant%%-*}" --time="$time_limit" abba.slurm)
echo "JOB_ID=${job%%;*}" >> "$run/run.env"
echo "SUBMITTED job=${job%%;*} run=$run"
