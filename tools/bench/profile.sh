#!/bin/bash
# 在登录节点创建一个 profile 运行目录并提交作业（只做 git/mkdir/sbatch）。
#   tools/bench/profile.sh --task EV-01 --variant V02-v3-hotspot --ref main --sids 'Q969Q1_1 P00782_1' [--env 'K=V'] [--dry-run]
# 作业先用该 build 的 prologue.sh 生成 bin8 库（与正式路径一致），再对每条查询单独 perf record。
set -euo pipefail

WS=${MSA_WS:-$HOME/WORK/dot}
REPO=${MSA_REPO:-$WS/SuperMSA}
EXP=$WS/experiments/supermsa
die() { echo "ERROR: $*" >&2; exit 1; }
g() { (cd "$REPO" && git "$@"); }
resolve_sha() {
    g rev-parse -q --verify "$1^{commit}" 2>/dev/null || g rev-parse -q --verify "origin/$1^{commit}" 2>/dev/null
}

task= variant= ref=main sids= envs= dry=0
while [ $# -gt 0 ]; do
    case $1 in
        --task) task=$2; shift 2;;
        --variant) variant=$2; shift 2;;
        --ref) ref=$2; shift 2;;
        --sids) sids=$2; shift 2;;
        --env) envs=$2; shift 2;;
        --dry-run) dry=1; shift;;
        *) die "unknown option $1";;
    esac
done
[[ $task =~ ^(DP|CK|QS|SA|EV)-[0-9]{2}$ ]] || die "--task 形如 EV-01"
[[ $variant =~ ^V[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "--variant 形如 V02-v3-hotspot"
[ -n "$sids" ] || die "需要 --sids"
for s in $sids; do [[ $s =~ ^[A-Za-z0-9_.-]+$ ]] && [ -s "$WS/preliminary/query/$s.fasta" ] || die "查询不存在：$s"; done
sha=$(resolve_sha "$ref") || die "无法解析 $ref（先在本地 push 并执行 tools/bench/sync_hpc.sh）"
build=$EXP/builds/${sha:0:12}
[ -f "$build/BINARIES.sha256" ] || die "$ref (${sha:0:12}) 尚未编译：在 test01 上执行 tools/bench/build.sh $ref"

domain=$(echo "${task:0:2}" | tr 'A-Z' 'a-z')
parent=$EXP/$domain/$task/$variant
n=1
while compgen -G "$parent/r$(printf %02d $n)-*" > /dev/null; do n=$((n + 1)); done
run=$parent/r$(printf %02d $n)-profile
echo "run=$run"
echo "ref=$ref ${sha:0:12} env='$envs' sids='$sids'"
[ "$dry" = 0 ] || exit 0

mkdir -p "$run"
cp "$REPO/tools/bench/profile.slurm" "$run/"
{
    printf 'TASK=%q\nVARIANT=%q\nREF=%q\nSHA=%q\nENVS=%q\nSIDS=%q\n' "$task" "$variant" "$ref" "$sha" "$envs" "$sids"
    printf 'BUILD=%q\nDATA_SRC=%q\nCREATED_AT=%q\n' "$build" "$WS/preliminary" "$(date -Is)"
} > "$run/run.env"
job=$(cd "$run" && sbatch --parsable -J "${task}-prof" profile.slurm)
echo "JOB_ID=${job%%;*}" >> "$run/run.env"
echo "SUBMITTED job=${job%%;*} run=$run"
