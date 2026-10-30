#!/usr/bin/env bash
# 为新实验建立规范目录、留存代码状态并提交基线作业。
set -euo pipefail

usage() {
    echo "Usage: $0 --workspace WORKSPACE [--dry-run] TASK VARIANT RUN_ID" >&2
    exit 2
}

[[ "${1:-}" == "--workspace" && $# -ge 5 ]] || usage
workspace="$2"
shift 2
dry_run=0
if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=1
    shift
fi
[[ $# -eq 3 ]] || usage
task="$1"
variant="$2"
run_id="$3"
[[ "$task" =~ ^(DP|CK|QS|SA|EV)-[0-9]{2}$ ]] || usage
[[ "$variant" =~ ^V[0-9]{2}-[a-z0-9-]+$ ]] || usage
[[ "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage

workspace="$(cd "$workspace" && pwd -P)"
domain="${task:0:2}"
domain="${domain,,}"
repo="$workspace/SuperMSA"
run="$workspace/experiments/supermsa/$domain/$task/$variant/$run_id"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
template="$script_dir/run.template.json"

[[ -e "$repo/.git" && -f "$repo/job_baseline.slurm" && -f "$template" ]] || {
    echo "Missing repository, job template or run.template.json" >&2
    exit 1
}
[[ ! -e "$run" && ! -L "$run" ]] || {
    echo "Experiment already exists: $run" >&2
    exit 1
}
if (( dry_run )); then
    printf 'run=%s\n' "$run"
    printf 'job=%s\n' "$repo/job_baseline.slurm"
    exit 0
fi

mkdir -p "$(dirname "$run")"
mkdir "$run"
mkdir "$run/results"
commit="$(cd "$repo" && git rev-parse HEAD)"
{
    date -Is
    printf 'git_commit=%s\n' "$commit"
    (cd "$repo" && git status --short)
} > "$run/metadata.txt"
cp "$repo/job_baseline.slurm" "$run/job.snapshot.slurm"
cp "$repo/run_queries.sh" "$run/run_queries.snapshot.sh"
cp "$repo/prologue.sh" "$run/prologue.snapshot.sh"
python3 - "$template" "$run/run.json" "$task" "$variant" "$run_id" "$commit" <<'PY'
import json
import sys
with open(sys.argv[1]) as stream:
    document = json.load(stream)
document.update(task_id=sys.argv[3], variant_id=sys.argv[4],
                run_id=sys.argv[5], git_commit=sys.argv[6])
with open(sys.argv[2], "w") as stream:
    json.dump(document, stream, ensure_ascii=False, indent=2, sort_keys=True)
    stream.write("\n")
PY
job_id="$(
    cd "$run"
    OUT="$run/results" DATA="$workspace/preliminary" FORCE=1 \
        sbatch --parsable --export=ALL "$repo/job_baseline.slurm"
)"
job_id="${job_id%%;*}"
[[ "$job_id" =~ ^[0-9]+$ ]] || {
    echo "Slurm returned an unexpected job ID; inspect $run before retrying" >&2
    exit 1
}
python3 - "$run/run.json" "$job_id" <<'PY'
import json
import sys
with open(sys.argv[1]) as stream:
    document = json.load(stream)
document["slurm_job_id"] = sys.argv[2]
with open(sys.argv[1], "w") as stream:
    json.dump(document, stream, ensure_ascii=False, indent=2, sort_keys=True)
    stream.write("\n")
PY
printf 'run=%s\njob_id=%s\n' "$run" "$job_id"
