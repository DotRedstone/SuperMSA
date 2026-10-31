#!/usr/bin/env bash
# QS-02/V01：MSA_QS_LONGEST_FIRST=1 时按查询长度从长到短启动；默认保持原顺序。用假 jackhmmer 记录启动顺序。
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/msa-lpt.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT
export MSA_BIN8=0
mkdir -p "$tmp/repo/scripts" "$tmp/data/query"
cp "$REPO/run_queries.sh" "$tmp/repo/"; cp "$REPO/scripts/query_worker.sh" "$tmp/repo/scripts/"
printf 'import sys\n' > "$tmp/repo/score.py"
printf '>t\nAC\n' > "$tmp/data/database.fasta"
printf '>a\nAC\n'            > "$tmp/data/query/a.fasta"   # 2
printf '>b\nACDEFGHIK\nLM\n' > "$tmp/data/query/b.fasta"   # 11
printf '>c\nACDEF\n'         > "$tmp/data/query/c.fasta"   # 5
cat > "$tmp/jack" <<SH
#!/usr/bin/env bash
tbl=; prev=; last=
while [ \$# -gt 0 ]; do case \$1 in --tblout) tbl=\$2; shift 2;; -A) shift 2;; *) prev=\$last; last=\$1; shift;; esac; done
[ "\$tbl" = /dev/null ] || { basename "\$prev" .fasta >> "$tmp/order"; echo '# t' > "\$tbl"; }
SH
chmod +x "$tmp/jack"
run() { rm -f "$tmp/order"; env "$@" JACKHMMER="$tmp/jack" PARALLEL=1 CPU=1 WARMUP=0 FORCE=1 \
    bash "$tmp/repo/run_queries.sh" "$tmp/data" "$tmp/out" > /dev/null 2>&1; tr '\n' ' ' < "$tmp/order"; }
[ "$(run MSA_QS_LONGEST_FIRST=0)" = "a b c " ] || { echo "FAIL: default order changed"; exit 1; }
[ "$(run MSA_QS_LONGEST_FIRST=1)" = "b c a " ] || { echo "FAIL: longest-first order: $(run MSA_QS_LONGEST_FIRST=1)"; exit 1; }
echo "QS_LONGEST_FIRST=PASS"
