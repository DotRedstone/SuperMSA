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
ALIAS_FIELDS = ("alias_path", "canonical_path")
SUPPORT_FIELDS = ("file_path", "role", "size_bytes")
TASKS = {
    "e01-fasta-onepass": "DP-01",
    "e02-bin8-batched-io": "DP-03",
    "e03-queue-geometry": "DP-04",
    "e04-queue-signal-one": "DP-05",
    "e05-fasta-direct-map": "DP-01",
    "e06-fasta-config-cache": "DP-01",
    "p01-reader-worker-profile": "EV-02",
}
PROBE_TASKS = {
    "bin8-build-r01": "DP-02",
    "bin8-sweep-r01": "DP-02",
    "candidate-repeat-r01": "QS-01",
    "fasta-preprocess-r01": "DP-01",
    "four-formats-sweep-r01": "EV-01",
    "four-way-build-r01": "DP-02",
    "parallel-scan-20261028_230525": "QS-01",
    "ssv-band-build-r01": "CK-01",
    "ssv-band-sweep-r01": "CK-01",
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
        match = re.match(r"^(?:perf|smoke|stdout|stderr|probe|msa_probe)\.(\d{7,})\.", entry.name)
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
        if entry.is_file() and re.match(r"^(?:perf|smoke|stdout|stderr|probe|msa_probe)\.\d{7,}\.out$", entry.name)
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
    domains = ("dp", "ck", "qs", "sa", "ev")
    if any((experiments / domain).is_dir() for domain in domains):
        for domain in domains:
            parent = experiments / domain
            if not parent.is_dir():
                continue
            for task in sorted(parent.iterdir()):
                if not task.is_dir() or task.is_symlink():
                    continue
                for variant in sorted(task.iterdir()):
                    if not variant.is_dir() or variant.is_symlink():
                        continue
                    for run in sorted(variant.iterdir()):
                        if run.is_dir() and not run.is_symlink():
                            items.append(("HISTORICAL_RUN", run, task.name, variant.name, run.name))
    else:
        probes = experiments / "probes"
        if probes.is_dir():
            for directory in sorted(probes.iterdir()):
                if directory.is_dir() and not directory.is_symlink() and directory.name != "experiments":
                    items.append(("PROBE", directory, PROBE_TASKS.get(directory.name, UNKNOWN), directory.name, directory.name))
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


def collect_aliases(workspace, records):
    probes = workspace / "experiments" / "supermsa" / "probes"
    canonical = {row["record_path"] for row in records}
    aliases = []
    migrated = (workspace / "experiments/supermsa/dp").is_dir()
    if migrated:
        root = workspace / "experiments/supermsa"
        candidates = []
        for parent in (probes, root / "runs", root / "analysis", workspace / "baselines/supermsa"):
            if parent.is_dir():
                candidates.extend(path for path in parent.rglob("*") if path.is_symlink())
        candidates.extend(path for path in root.iterdir() if path.is_symlink())
        for entry in sorted(candidates):
            target = entry.resolve(strict=True)
            target_path = relative(workspace, target)
            aliases.append({"alias_path": relative(workspace, entry), "canonical_path": target_path})
        return aliases
    if probes.is_dir():
        for entry in sorted(probes.iterdir()):
            if not entry.is_symlink():
                continue
            target = entry.resolve(strict=True)
            target_path = relative(workspace, target)
            if target_path not in canonical:
                raise ValueError("alias target is not indexed: " + relative(workspace, entry))
            aliases.append({"alias_path": relative(workspace, entry), "canonical_path": target_path})
    return aliases


def create_view(workspace, snapshot_dir, records):
    view = snapshot_dir / "by-task"
    for row in records:
        destination = view / row["task_id"] / row["variant"] / row["run_id"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists() or destination.is_symlink():
            raise ValueError("duplicate view path: " + str(destination.relative_to(snapshot_dir)))
        target = workspace / row["record_path"]
        if not target.exists():
            raise FileNotFoundError(str(target))
        destination.symlink_to(os.path.relpath(target, destination.parent))


def collect_supporting(workspace):
    root = workspace / "experiments" / "supermsa"
    directories = [root, root / "probes", root / "analysis", root / "scripts"]
    assets = root / "assets"
    if assets.is_dir():
        directories.extend(path for path in assets.iterdir() if path.is_dir())
    migrations = root / "migrations"
    if migrations.is_dir():
        directories.extend(path for path in migrations.iterdir() if path.is_dir())
    files = sorted(path for directory in directories if directory.is_dir()
                   for path in directory.iterdir() if path.is_file() and not path.is_symlink())
    result = []
    for path in files:
        if path.suffix == ".tar":
            role = "SOURCE_ARCHIVE"
        elif path.suffix == ".commit":
            role = "SOURCE_COMMIT_MARKER"
        elif path.suffix in (".sh", ".slurm", ".py"):
            role = "SCRIPT"
        elif path.suffix in (".out", ".log"):
            role = "LOG"
        elif path.parent.name == "analysis" or path.suffix in (".tsv", ".txt"):
            role = "ANALYSIS"
        else:
            role = "OTHER"
        result.append({"file_path": relative(workspace, path), "role": role,
                       "size_bytes": str(path.stat().st_size)})
    return result


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
    aliases = collect_aliases(workspace, records)
    supporting = collect_supporting(workspace)
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
    write_tsv(temporary / "aliases.tsv", ALIAS_FIELDS, aliases)
    write_tsv(temporary / "supporting.tsv", SUPPORT_FIELDS, supporting)
    create_view(workspace, temporary, records)
    manifest = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "record_count": len(records),
        "trial_count": len(trials),
        "alias_count": len(aliases),
        "supporting_count": len(supporting),
        "path_base": "workspace_root",
        "source_policy": "Existing files are referenced and not modified.",
    }
    (temporary / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    (temporary / "README.md").write_text(
        "# SuperMSA 实验索引快照\n\n"
        "路径相对于传入的工作区根目录。`records.tsv` 列出不重复的原目录与已有证据；"
        "`trials.tsv` 按原列名摘录现有 `summary.tsv` 的试验行；"
        "`aliases.tsv` 记录历史符号链接；`by-task/` 是指向原文件的分类链接视图。"
        "`supporting.tsv` 列出顶层脚本、源码包、分析文件和日志，不推断其与运行的对应关系。"
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
