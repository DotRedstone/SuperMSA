#!/usr/bin/env bash
# 用假的 jackhmmer 和 score.py 在本地跑通 abba.sh 和 summarize.py。
# 不需要 Slurm，也不读取比赛数据。
set -euo pipefail
# 这里测的是调度/测评逻辑，关闭默认开启的 bin8 预处理（假 build 里没有转换器）。
export MSA_BIN8=0

REPO=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/msa-bench-test.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- 假数据 ---
mkdir -p "$tmp/data/query"
printf '>t1\nACDE\n' > "$tmp/data/database.fasta"
for q in q1 q2 q3; do printf '>%s\nACDE\n' "$q" > "$tmp/data/query/$q.fasta"; done
printf 'query\tbaseline\n' > "$tmp/data/baseline_roc10.tsv"

# --- 假 build：真实的 prologue/run_queries/worker，假的 jackhmmer 和 score.py ---
make_build() {  # make_build <sha12> <sleep_seconds>
    local b=$tmp/builds/$1
    mkdir -p "$b/src" "$b/scripts"
    cp "$REPO/prologue.sh" "$REPO/run_queries.sh" "$b/"
    cp "$REPO/scripts/query_worker.sh" "$b/scripts/"
    cat > "$b/src/jackhmmer" <<SH
#!/usr/bin/env bash
tbl=; prev=; last=
while [ \$# -gt 0 ]; do
    case \$1 in --tblout) tbl=\$2; shift 2;; -A) shift 2;; *) prev=\$last; last=\$1; shift;; esac
done
sid=\$(basename "\$prev" .fasta)
sleep $2
[ "\$tbl" = /dev/null ] || printf '# t\nT1 - %s - 1e-30 100.0 0.1 1e-30 100.0 0.1 1.0 1 0 0 1 1 1 1 desc\n' "\$sid" > "\$tbl"
SH
    cat > "$b/score.py" <<'PY'
import pathlib, sys
a = sys.argv
out = pathlib.Path(a[a.index("--results") + 1])
rows = ["query\tcorrect"] + ["%s\tTrue" % p.stem for p in sorted((out / "tbl").glob("*.tbl"))]
(out / "scores.tsv").write_text("\n".join(rows) + "\n")
PY
    chmod +x "$b/src/jackhmmer"
    (cd "$b" && sha256sum src/jackhmmer > BINARIES.sha256)
}
make_build aaaaaaaaaaaa 0.4
make_build bbbbbbbbbbbb 0.1

# --- 运行目录 ---
run=$tmp/run
mkdir -p "$run"
cp "$REPO"/tools/bench/{abba.sh,compare_hit_tables.py,summarize.py} "$run/"
printf 'q1\nq2\nq3\n' > "$run/queries.txt"
cat > "$run/run.env" <<EOF
TASK=DP-99
VARIANT=V01-test
RUN_ID=r01-q3
BASE_REF=main
BASE_SHA=aaaaaaaaaaaa0000
BASE_ENV=''
TUNED_REF=perf/dp-99/v01-test
TUNED_SHA=bbbbbbbbbbbb0000
TUNED_ENV='MSA_TEST_FLAG=1'
ORDER=ABBA
QUERIES=q3
CPU=1
PARALLEL=2
WARMUP=0
BUILDS=$tmp/builds
DATA_SRC=$tmp/data
EOF

MSA_ALLOW_NO_SLURM=1 bash "$run/abba.sh" "$run" > "$tmp/abba.log" 2>&1 || { cat "$tmp/abba.log"; fail "abba.sh"; }
[ "$(tail -n +2 "$run/summary.tsv" | wc -l)" = 4 ] || fail "expected 4 trials"
awk -F '\t' 'NR > 1 && ($8 != "3/3" || $9 != "PASS") {exit 1}' "$run/summary.tsv" || fail "gates"
grep -q '^VERDICT=faster$' "$run/report.txt" || { cat "$run/report.txt"; fail "verdict"; }
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['verdict']=='faster' and len(d['trials'])==4" \
    "$run/run.json" || fail "run.json"

# 运行目录只写一次
MSA_ALLOW_NO_SLURM=1 bash "$run/abba.sh" "$run" > /dev/null 2>&1 && fail "rerun into existing run dir accepted"

# --official：CPU/PARALLEL/WARMUP 为空时不传，run_queries.sh 用自己的默认值
run3=$tmp/run3
mkdir -p "$run3"
cp "$run"/{abba.sh,compare_hit_tables.py,summarize.py,queries.txt} "$run3/"
grep -v '^\(JOB_ID\|NODE\|STARTED_AT\|FINISHED_AT\|ORDER\|CPU\|PARALLEL\|WARMUP\)=' "$run/run.env" > "$run3/run.env"
printf "ORDER=A\nCPU=''\nPARALLEL=''\nWARMUP=''\n" >> "$run3/run.env"
MSA_ALLOW_NO_SLURM=1 bash "$run3/abba.sh" "$run3" > "$tmp/abba3.log" 2>&1 || { cat "$tmp/abba3.log"; fail "official mode"; }
grep -q '并发数 6' "$run3/trials/01-A/search.log" || fail "official mode did not use run_queries default PARALLEL=6"
grep -q '^VERDICT=single-arm$' "$run3/report.txt" || fail "official verdict"

# 二进制被改动时必须拒绝
run2=$tmp/run2
mkdir -p "$run2"
cp "$run"/{abba.sh,compare_hit_tables.py,summarize.py,queries.txt} "$run2/"
grep -v '^\(JOB_ID\|NODE\|STARTED_AT\|FINISHED_AT\)=' "$run/run.env" > "$run2/run.env"
echo '# tampered' >> "$tmp/builds/bbbbbbbbbbbb/src/jackhmmer"
MSA_ALLOW_NO_SLURM=1 bash "$run2/abba.sh" "$run2" > /dev/null 2>&1 && fail "tampered binary accepted"

echo "BENCH_HARNESS=PASS"
