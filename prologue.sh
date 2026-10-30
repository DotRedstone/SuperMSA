#!/bin/bash
# 选手预处理入口：由 job_baseline.slurm 在计算节点上、正式搜索（run_queries.sh）之前同步调用一次。
# 任何预处理工作写在下面的 prepare() 里，计时框架不要改。
# 注意，你必须从读取preliminary中的原始数据开始计时，不允许提前处理
# 可用变量（与 run_queries.sh 默认布局一致，也可用环境变量覆盖）:
#   REPO  仓库目录          DATA  数据目录（含 query/ 与 database.fasta）
#   OUT   搜索结果目录      预处理产物请写在 ~/WORK 下（home 在计算节点只读）
# 计时: prepare() 开始到结束的墙钟时间，打印为固定格式的一行
#   prologue time  = <秒> s
# 评分时与 search time 相加；prepare() 失败（非零退出）则不打印该行，结果无效。
set -euo pipefail

case $(hostname) in
    cln0[1-4]*|ibcln*)
        echo "ERROR: 禁止在登录节点运行程序。prologue.sh 由 job_baseline.slurm 在计算节点上调用，请用 sbatch 提交。" >&2
        exit 1;;
esac

REPO=$(cd "$(dirname "$0")" && pwd)
DATA=${DATA:-$(dirname "$REPO")/preliminary}
OUT=${OUT:-$REPO/results}
export REPO DATA OUT

elapsed() { awk -v a="$1" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}'; }

prepare() {
    if [ "${MSA_DSQDATA:-0}" = 1 ]; then
        [ "${MSA_BIN8:-0}" != 1 ] || { echo "ERROR: MSA_BIN8 and MSA_DSQDATA are mutually exclusive" >&2; return 1; }
        local writer="$REPO/scripts/fasta_to_dsqdata"
        local prefix="$OUT/prepared/database"
        local f total
        [ -x "$writer" ] || { echo "ERROR: missing DSQDATA writer" >&2; return 1; }
        [ -s "$DATA/database.fasta" ] || { echo "ERROR: missing original FASTA" >&2; return 1; }
        mkdir -p "$OUT/prepared"
        for f in "$prefix" "$prefix.dsqi" "$prefix.dsqm" "$prefix.dsqs"; do
            [ ! -e "$f" ] || {
                echo "ERROR: DSQDATA artifact exists: $f; use a fresh OUT" >&2
                return 1
            }
        done
        # Every byte of conversion is produced during timed prepare().
        if ! "$writer" "$DATA/database.fasta" "$prefix"; then
            rm -f -- "$prefix" "$prefix.dsqi" "$prefix.dsqm" "$prefix.dsqs"
            return 1
        fi
        total=0
        for f in "$prefix" "$prefix.dsqi" "$prefix.dsqm" "$prefix.dsqs"; do
            [ -s "$f" ] || { echo "ERROR: incomplete DSQDATA artifact" >&2; return 1; }
            total=$((total + $(stat -c '%s' "$f")))
        done
        echo "DSQDATA_FILE_BYTES=$total"
        echo "DSQDATA_PREPARED=$prefix"
    fi
    # Optional 8-bit digital DB. Output is constructed only inside the
    # measured prologue and is never reused across benchmark runs.
    if [ "${MSA_BIN8:-0}" = 1 ]; then
        local converter="$REPO/scripts/fasta_to_bin8"
        local prepared="$OUT/prepared/database.bin8"
        local tmp

        [ -x "$converter" ] || { echo "ERROR: missing converter $converter" >&2; return 1; }
        [ -s "$DATA/database.fasta" ] || { echo "ERROR: missing input database" >&2; return 1; }
        mkdir -p "$OUT/prepared"
        [ ! -e "$prepared" ] || { echo "ERROR: prepared database exists; use fresh OUT" >&2; return 1; }
        tmp=$(mktemp "$OUT/prepared/.database.bin8.XXXXXX") || return 1
        if ! "$converter" "$DATA/database.fasta" "$tmp"; then
            rm -f -- "$tmp"
            return 1
        fi
        if ! mv -- "$tmp" "$prepared"; then
            rm -f -- "$tmp"
            return 1
        fi
        stat -c 'BIN8_FILE_BYTES=%s' "$prepared"
        echo "BIN8_PREPARED=$prepared"
    fi
}

echo "预处理开始..."
t0=$(date +%s.%N)
prepare
wait    # prepare() 里放到后台（&）的任务也必须在计时内结束
echo    # 先换行：prepare() 的输出可能没以换行结尾，保证计时行独占一行
echo "prologue time  = $(elapsed "$t0") s"
