#!/bin/bash
# Requeue already-smoke-validated T1/T2/T3 as clean r02 ABBA jobs.
# Do not modify source or results in existing -r01 trial directories.
set -euo pipefail
ROOT="$HOME/WORK/dot/experiments/supermsa/probes"
REF="$HOME/WORK/dot/experiments/supermsa/runs/query-parallel-p6-t8-r01/results/tbl"
command -v sbatch >/dev/null || { echo "ERROR: sbatch not available" >&2; exit 2; }
test -d "$REF" || { echo "ERROR: missing original V1 hit tables $REF" >&2; exit 2; }
tmp=$(mktemp -d "$ROOT/.feature-r02-preflight.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

echo "Preflight: check existing first-base 12-query results BEFORE spending more CPU."
for id in t1 t2 t3; do
  OLD="$ROOT/$id-abba-r01"
  PATCH="$ROOT/supermsa-$id-validation-r02.tar"
  RUN="$ROOT/$id-abba-r02"
  test ! -e "$RUN" || { echo "ERROR: $RUN already exists; refusing overwrite" >&2; exit 2; }
  test -s "$PATCH" || { echo "ERROR: missing $PATCH" >&2; exit 2; }
  test -s "$OLD/queries.selected" || { echo "ERROR: missing r01 queries for $id" >&2; exit 2; }
  test -s "$OLD/results/01-base/wall_time.tsv" || { echo "ERROR: missing completed r01 base trial for $id" >&2; exit 2; }
  test -d "$OLD/results/01-base/tbl" || { echo "ERROR: missing r01 hit tables for $id" >&2; exit 2; }
  for path in scripts/run_feature_abba.sh scripts/compare_hit_tables.py tests/test_compare_hit_tables.py; do
    tar -tf "$PATCH" | grep -Fx "$path" >/dev/null ||
      { echo "ERROR: $path missing in $PATCH" >&2; exit 2; }
  done
  mkdir -p "$tmp/$id"
  tar -m -xf "$PATCH" -C "$tmp/$id"
  echo "=== ${id}: comparator unit tests ==="
  python3 "$tmp/$id/tests/test_compare_hit_tables.py"
  echo "=== ${id}: independent r01 base validation against historical V1 ==="
  python3 "$tmp/$id/scripts/compare_hit_tables.py" \
    --queries "$OLD/queries.selected" "$REF" "$OLD/results/01-base/tbl"
  echo "PASS: $id old base output passes corrected numerical/tie-aware comparator"
done

echo "All three reference checks passed; prepare NEW immutable r02 snapshots."
for id in t1 t2 t3; do
  OLD="$ROOT/$id-abba-r01"
  PATCH="$ROOT/supermsa-$id-validation-r02.tar"
  RUN="$ROOT/$id-abba-r02"
  mkdir -p "$RUN/source"
  cp -a "$OLD/source/." "$RUN/source/"
  tar -m -xf "$PATCH" -C "$RUN/source"
  sha256sum "$PATCH" > "$RUN/validation-patch.sha256"
  printf 'reused_compiled_source=%s\nvalidation_patch=%s\n' \
    "$OLD/source" "$PATCH" > "$RUN/provenance.txt"
  cp "$RUN/source/job_feature_perf.slurm" "$RUN/perf.slurm"
  bash -n "$RUN/perf.slurm" "$RUN/source/scripts/run_feature_abba.sh"
  case "$id" in
    t2) hash=huffman.binaries.sha256
        test -x "$RUN/source/scripts/fasta_to_bin8_reference" ||
          { echo "ERROR: T2 original converter not found" >&2; exit 2; };;
    *)  hash=bin8.binaries.sha256;;
  esac
  (cd "$RUN/source" && sha256sum -c "$hash")
done

echo "All copies verified. Submit three new performance jobs."
for id in t1 t2 t3; do
  RUN="$ROOT/$id-abba-r02"
  (
    cd "$RUN"
    job=$(sbatch --parsable perf.slurm)
    job="${job%%;*}"
    [[ "$job" =~ ^[0-9]+$ ]] || { echo "ERROR: unexpected job ID $job" >&2; exit 2; }
    printf 'feature=%s\nperf_job=%s\nreused_smoke=r01\n' \
      "$id" "$job" | tee job_ids.txt
  )
done
echo "ALL_THREE_FEATURES_R02_QUEUED=YES"
