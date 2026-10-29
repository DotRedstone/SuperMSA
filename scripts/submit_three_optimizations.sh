#!/bin/bash
# Submit three isolated smoke -> perf pipelines to Slurm.
# Run on the login node only, after transferring all three Git archives.
# Never mutate an active four-format or prior benchmark snapshot.
set -euo pipefail
ROOT="$HOME/WORK/dot/experiments/supermsa/probes"
REF="$ROOT/four-way-build-r01/source/scripts/fasta_to_bin8"
command -v sbatch >/dev/null || { echo "ERROR: sbatch not in PATH" >&2; exit 2; }
test -x "$REF" || { echo "ERROR: missing original BIN8 converter $REF" >&2; exit 2; }
for id in t1 t2 t3; do
  src="$ROOT/supermsa-$id.tar"
  dst="$ROOT/$id-abba-r01"
  test -s "$src" || { echo "ERROR: missing $src" >&2; exit 2; }
  test ! -e "$dst" || { echo "ERROR: $dst already exists; refusing overwrite" >&2; exit 2; }
  tar -tf "$src" | grep -Fx 'scripts/run_feature_abba.sh' >/dev/null ||
    { echo "ERROR: no pilot runner in $src" >&2; exit 2; }
  tar -tf "$src" | grep -Fx 'job_feature_smoke.slurm' >/dev/null ||
    { echo "ERROR: no smoke job in $src" >&2; exit 2; }
  tar -tf "$src" | grep -Fx 'job_feature_perf.slurm' >/dev/null ||
    { echo "ERROR: no perf job in $src" >&2; exit 2; }
done
for id in t1 t2 t3; do
  src="$ROOT/supermsa-$id.tar"
  dst="$ROOT/$id-abba-r01"
  mkdir -p "$dst/source"
  tar -xf "$src" -C "$dst/source"
  (
    cd "$dst/source"
    case "$id" in
      t1) test -f tests/test_fasta_onepass.sh ;;
      t2) test -f tests/test_bin8_batched_io.sh ;;
      t3) test -f tests/test_queue_geometry.sh ;;
    esac
  )
  sha256sum "$src" > "$dst/source-archive.sha256"
  cp "$dst/source/job_feature_smoke.slurm" "$dst/smoke.slurm"
  cp "$dst/source/job_feature_perf.slurm" "$dst/perf.slurm"
  if [ "$id" = t2 ]; then
    cp -p "$REF" "$dst/source/scripts/fasta_to_bin8_reference"
    sha256sum "$dst/source/scripts/fasta_to_bin8_reference" > "$dst/reference-converter.sha256"
  fi
  bash -n "$dst/smoke.slurm" "$dst/perf.slurm" "$dst/source/scripts/run_feature_abba.sh"
  (
    cd "$dst"
    smoke=$(sbatch --parsable smoke.slurm)
    smoke="${smoke%%;*}"
    [[ "$smoke" =~ ^[0-9]+$ ]] || { echo "ERROR: unrecognized smoke job ID $smoke" >&2; exit 1; }
    # Invalid dependencies are automatically canceled by Slurm.
    perf=$(sbatch --parsable --dependency="afterok:$smoke" \
            --kill-on-invalid-dep=yes perf.slurm)
    perf="${perf%%;*}"
    [[ "$perf" =~ ^[0-9]+$ ]] || { echo "ERROR: unrecognized perf job ID $perf" >&2; exit 1; }
    printf 'feature=%s\nsmoke_job=%s\nperf_job=%s\ndependency=afterok:%s\n' \
      "$id" "$smoke" "$perf" "$smoke" | tee job_ids.txt
  )
done
echo "ALL_THREE_FEATURES_QUEUED=YES"
echo "Monitor: squeue -u \$USER"
