#!/usr/bin/env python3
"""为已有 SuperMSA 实验生成只读快照索引。"""

import argparse
import csv
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path


UNKNOWN = "UNVERIFIED"
SUMMARY_FIELDS = (
    "trial", "feature", "mode", "prologue_s", "search_s", "total_s",
    "queries_run", "quality", "identical_v1", "worker_threads", "warmup_runs",
)
RECORD_FIELDS = (
    "record_kind", "task_id", "variant", "run_id", "record_path",
    "source_commit", "source_archive_sha256", "source_snapshot_present",
    "job_ids", "summary_path", "summary_state", "summary_rows",
    "provenance_path", "query_set_path", "raw_log_paths", "review_class",
)
TRIAL_BASE_FIELDS = ("record_path", "summary_path") + SUMMARY_FIELDS
TASKS = {
    "e01-fasta-onepass": "DP-01",
    "e02-bin8-batched-io": "DP-03",
    "e03-queue-geometry": "DP-04",
    "e04-queue-signal-one": "DP-05",
    "e05-fasta-direct-map": "DP-01",
    "e06-fasta-config-cache": "DP-01",
    "p01-reader-worker-profile": "EV-02",
}


def relative(workspace, path):
    return path.relative_to(workspace).as_posix()


def existing_path(workspace, path):
    return relative(workspace, path) if path.is_file() else UNKNOWN


def source_commit(directory):
    path = directory / "source-commit.txt"
    if path.is_file():
        value = path.read_text(errors="replace").strip()
        if re.fullmatch(r"[0-9a-fA-F]{7,40}", value):
            return value.lower()
    return UNKNOWN


def source_archive_hash(directory):
    path = directory / "source-archive.sha256"
    if path.is_file():
        line = path.read_text(errors="replace").splitlines()
        if line:
            match = re.match(r"^([0-9a-fA-F]{64})(?:\s|$)", line[0])
            if match:
                return match.group(1).lower()
    return UNKNOWN


def job_ids(directory):
    found = set()
    path = directory / "job_ids.txt"
    if path.is_file():
        found.update(re.findall(r"(?<!\d)\d{7,}(?!\d)", path.read_text(errors="replace")))
    for entry in directory.iterdir() if directory.is_dir() else ():
        match = re.match(r"^(?:perf|smoke|stdout|stderr|probe)\.(\d{7,})\.", entry.name)
        if match:
            found.add(match.group(1))
        match = re.match(r"^stdout\.(\d{7,})$", entry.name)
        if match:
            found.add(match.group(1))
    return ",".join(sorted(found, key=int)) if found else UNKNOWN


def summary(workspace, directory):
    path = directory / "summary.tsv"
    if not path.is_file():
        return UNKNOWN, "NO_SUMMARY", UNKNOWN, []
    with path.open(newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if (not reader.fieldnames or not all(reader.fieldnames)
                or len(set(reader.fieldnames)) != len(reader.fieldnames)
                or "record_path" in reader.fieldnames or "summary_path" in reader.fieldnames):
            return relative(workspace, path), "UNPARSED", UNKNOWN, []
        rows = list(reader)
        if any(None in row for row in rows):
            return relative(workspace, path), "UNPARSED", UNKNOWN, []
    state = "HAS_TRIALS" if rows else "HEADER_ONLY"
    return relative(workspace, path), state, str(len(rows)), rows


def record(workspace, kind, directory, task_id, variant, run_id):
    if kind == "BASELINE_LOG":
        record_path = relative(workspace, directory)
        match = re.fullmatch(r"stdout\.(\d{7,})", directory.name)
        return {
            "record_kind": kind, "task_id": UNKNOWN, "variant": UNKNOWN,
            "run_id": directory.name, "record_path": record_path,
            "source_commit": UNKNOWN, "source_archive_sha256": UNKNOWN,
            "source_snapshot_present": "NO", "job_ids": match.group(1) if match else UNKNOWN,
            "summary_path": UNKNOWN, "summary_state": "NO_SUMMARY",
            "summary_rows": UNKNOWN, "provenance_path": UNKNOWN,
            "query_set_path": UNKNOWN, "raw_log_paths": record_path,
            "review_class": "UNKNOWN",
        }, []

    record_path = relative(workspace, directory)
    summary_path, summary_state, summary_rows, rows = summary(workspace, directory)
    logs = sorted(
        entry for entry in directory.iterdir()
        if entry.is_file() and re.match(r"^(?:perf|smoke|stdout|stderr|probe)\.\d{7,}\.out$", entry.name)
    )
    result = {
        "record_kind": kind, "task_id": task_id, "variant": variant,
        "run_id": run_id, "record_path": record_path,
        "source_commit": source_commit(directory),
        "source_archive_sha256": source_archive_hash(directory),
        "source_snapshot_present": "YES" if (directory / "source").is_dir() else "NO",
        "job_ids": job_ids(directory), "summary_path": summary_path,
        "summary_state": summary_state, "summary_rows": summary_rows,
        "provenance_path": existing_path(workspace, directory / "provenance.txt"),
        "query_set_path": existing_path(workspace, directory / "queries.selected"),
        "raw_log_paths": ",".join(relative(workspace, item) for item in logs) if logs else UNKNOWN,
        "review_class": "UNKNOWN",
    }
    trials = [dict(row) for row in rows]
    for trial in trials:
        trial["record_path"] = record_path
        trial["summary_path"] = summary_path
    return result, trials


def collect(workspace):
    experiments = workspace / "experiments" / "supermsa"
    if not experiments.is_dir():
        raise ValueError("missing experiments/supermsa")
    items = []
    probes = experiments / "probes"
    if probes.is_dir():
        for directory in sorted(probes.iterdir()):
            if directory.is_dir() and directory.name != "experiments":
                items.append(("PROBE", directory, UNKNOWN, directory.name, directory.name))
        historical = probes / "experiments"
        if historical.is_dir():
            for variant in sorted(historical.iterdir()):
                if variant.is_dir():
                    for directory in sorted(variant.iterdir()):
                        if directory.is_dir():
                            items.append(("EXPERIMENT_RUN", directory, TASKS.get(variant.name, UNKNOWN), variant.name, directory.name))
    runs = experiments / "runs"
    if runs.is_dir():
        for directory in sorted(runs.iterdir()):
            if directory.is_dir():
                task = "QS-01" if directory.name.startswith("query-parallel-") else UNKNOWN
                items.append(("RUN", directory, task, directory.name, directory.name))
    baseline = workspace / "baselines" / "supermsa"
    if baseline.is_dir():
        for path in sorted(baseline.glob("stdout.*")):
            if path.is_file():
                items.append(("BASELINE_LOG", path, UNKNOWN, UNKNOWN, path.name))

    records, trials = [], []
    for item in items:
        row, trial_rows = record(workspace, *item)
        records.append(row)
        trials.extend(trial_rows)
    return records, trials


def write_tsv(path, fields, rows):
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def trial_fields(trials):
    extras = sorted(set(key for row in trials for key in row) - set(TRIAL_BASE_FIELDS))
    return TRIAL_BASE_FIELDS + tuple(extras)


def create_catalog(workspace, snapshot):
    if not re.fullmatch(r"[A-Za-z0-9_-]+", snapshot):
        raise ValueError("snapshot must contain only letters, digits, underscore or hyphen")
    workspace = workspace.resolve()
    records, trials = collect(workspace)
    parent = workspace / "experiments" / "supermsa" / "catalog"
    if parent.is_symlink():
        raise ValueError("catalog parent must not be a symlink")
    parent.mkdir(exist_ok=True)
    output = parent / snapshot
    if output.exists():
        raise FileExistsError(str(output))
    temporary = parent / ("." + snapshot + ".tmp-" + str(os.getpid()))
    temporary.mkdir()
    write_tsv(temporary / "records.tsv", RECORD_FIELDS, records)
    write_tsv(temporary / "trials.tsv", trial_fields(trials), trials)
    manifest = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "record_count": len(records),
        "trial_count": len(trials),
        "path_base": "WORK/dot",
        "source_policy": "Existing files are referenced and not modified.",
    }
    (temporary / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    (temporary / "README.md").write_text(
        "# SuperMSA 实验索引快照\n\n"
        "路径相对于 `WORK/dot`。`records.tsv` 列出原目录与已有证据；"
        "`trials.tsv` 按原列名摘录现有 `summary.tsv` 的试验行；"
        "不同来源没有的列留空，`summary_path` 指向原表。"
        "`HEADER_ONLY` 表示摘要只有表头，不能视为完成。"
        "`UNVERIFIED` 表示未从约定的原始文件核实；"
        "`review_class=UNKNOWN` 表示未判定能否迁移或清理。"
        "本索引不证明正式 100-query 正确性，也不修改原始实验。\n"
    )
    if output.exists():
        raise FileExistsError(str(output))
    temporary.rename(output)
    return output, len(records), len(trials)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, required=True, help="包含 experiments/supermsa 的工作区")
    parser.add_argument("--snapshot", default=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    parser.add_argument("--dry-run", action="store_true", help="只检查并统计，不写入索引")
    args = parser.parse_args()
    if args.dry_run:
        records, trials = collect(args.workspace.resolve())
        print("records={} trials={}".format(len(records), len(trials)))
        return
    output, record_count, trial_count = create_catalog(args.workspace, args.snapshot)
    print("catalog=" + output.relative_to(args.workspace.resolve()).as_posix())
    print("records={} trials={}".format(record_count, trial_count))


if __name__ == "__main__":
    main()
