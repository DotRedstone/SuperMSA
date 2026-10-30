#!/usr/bin/env python3
"""将已结束的旧实验原位重命名为领域/任务/方案/轮次，并保留旧路径。"""

import argparse
import json
import os
from pathlib import Path


ROOT = Path("experiments/supermsa")
PROBE_RUNS = {
    "bin8-build-r01": "dp/DP-02/V01-bin8/build-r01",
    "bin8-sweep-r01": "dp/DP-02/V01-bin8/sweep-r01",
    "candidate-repeat-r01": "qs/QS-01/V02-candidate-repeat/repeat-r01",
    "fasta-preprocess-r01": "dp/DP-01/V00-preprocess/sweep-r01",
    "four-formats-sweep-r01": "ev/EV-01/V01-four-formats/sweep-r01",
    "four-way-build-r01": "dp/DP-02/V02-four-way/build-r01",
    "parallel-scan-20261028_230525": "qs/QS-01/V01-parallel-scan/scan-20261028_230525",
    "perf-hotspot-r01": "ev/EV-03/V01-hotspot/profile-r01",
    "ssv-band-build-r01": "ck/CK-01/V01-band-limit/build-r01",
    "ssv-band-sweep-r01": "ck/CK-01/V01-band-limit/sweep-r01",
}
HISTORICAL_RUNS = {
    "e01-fasta-onepass": ("dp/DP-01/V01-onepass", ("abba-r01", "abba-r02", "build-r01")),
    "e02-bin8-batched-io": ("dp/DP-03/V01-batched-io", ("abba-r01", "abba-r02")),
    "e03-queue-geometry": ("dp/DP-04/V01-queue-geometry", ("abba-r01", "abba-r02")),
    "e04-queue-signal-one": ("dp/DP-05/V01-signal-one", ("abba-r01",)),
    "e05-fasta-direct-map": ("dp/DP-01/V02-direct-map", ("abba-r01",)),
    "e06-fasta-config-cache": ("dp/DP-01/V03-config-cache", ("abba-r01",)),
    "p01-reader-worker-profile": ("ev/EV-02/V01-reader-worker", ("probe-r01",)),
}
LEGACY_PROBE_FILES = (
    "diagnose_hit_drift.py", "hit-drift-r01.txt", "organize_experiments.py",
    "requeue_three_feature_abba_r02.sh", "submit_t4_t5_r01.sh", "submit_three_optimizations.sh",
    "supermsa-bin8-source.tar", "supermsa-dsq-fix.tar", "supermsa-e05-r01.commit",
    "supermsa-e05-r01.tar", "supermsa-e06-r01.commit", "supermsa-e06-r01.tar",
    "supermsa-four-way.tar", "supermsa-hitdiag.tar", "supermsa-queue-t4t5-r01.tar",
    "supermsa-r02-helper.tar", "supermsa-t1.tar", "supermsa-t1-validation-r02.tar",
    "supermsa-t2.tar", "supermsa-t2-validation-r02.tar", "supermsa-t3.tar",
    "supermsa-t3-validation-r02.tar", "supermsa-t4-r01.tar", "supermsa-t5-r01.tar",
    "t4-r01.commit", "t5-r01.commit",
)
RENAMED_FILES = {
    "supermsa-bin8-source.tar": "DP-02-V01-bin8-source.tar",
    "supermsa-dsq-fix.tar": "DP-02-V02-dsq-fix.tar",
    "supermsa-e05-r01.commit": "DP-01-V02-direct-map-r01.commit",
    "supermsa-e05-r01.tar": "DP-01-V02-direct-map-r01.tar",
    "supermsa-e06-r01.commit": "DP-01-V03-config-cache-r01.commit",
    "supermsa-e06-r01.tar": "DP-01-V03-config-cache-r01.tar",
    "supermsa-four-way.tar": "DP-02-V02-four-way-source.tar",
    "supermsa-hitdiag.tar": "EV-03-V01-hitdiag-source.tar",
    "supermsa-queue-t4t5-r01.tar": "DP-04-05-queue-r01.tar",
    "supermsa-r02-helper.tar": "EV-01-abba-r02-helper.tar",
    "supermsa-t1.tar": "DP-01-V01-onepass-source.tar",
    "supermsa-t1-validation-r02.tar": "DP-01-V01-onepass-validation-r02.tar",
    "supermsa-t2.tar": "DP-03-V01-batched-io-source.tar",
    "supermsa-t2-validation-r02.tar": "DP-03-V01-batched-io-validation-r02.tar",
    "supermsa-t3.tar": "DP-04-V01-queue-geometry-source.tar",
    "supermsa-t3-validation-r02.tar": "DP-04-V01-queue-geometry-validation-r02.tar",
    "supermsa-t4-r01.tar": "DP-05-V01-signal-one-r01.tar",
    "supermsa-t5-r01.tar": "EV-02-V01-reader-worker-r01.tar",
    "t4-r01.commit": "DP-05-V01-signal-one-r01.commit",
    "t5-r01.commit": "EV-02-V01-reader-worker-r01.commit",
}


def moves():
    result = []
    for old, new in PROBE_RUNS.items():
        result.append((ROOT / "probes" / old, ROOT / new))
    for variant, (parent, runs) in HISTORICAL_RUNS.items():
        for run in runs:
            result.append((ROOT / "probes/experiments" / variant / run, ROOT / parent / run))
    result.extend((
        (ROOT / "runs/query-parallel-p6-t8-r01", ROOT / "qs/QS-01/V03-p6t8/query-parallel-p6-t8-r01"),
        (Path("baselines/supermsa/stdout.16155687"), ROOT / "ev/EV-00/V00-baseline/job-16155687/stdout.16155687"),
        (ROOT / "msa_probe.16158363.out", ROOT / "ev/EV-00/V01-msa-probe/job-16158363/msa_probe.16158363.out"),
        (ROOT / "msa_probe.slurm", ROOT / "ev/EV-00/V01-msa-probe/job-16158363/msa_probe.slurm"),
        (ROOT / "analysis/parallel-scan-r01.tsv", ROOT / "assets/analysis/parallel-scan-r01.tsv"),
    ))
    for name in LEGACY_PROBE_FILES:
        extension = Path(name).suffix
        group = {".tar": "source-archives", ".commit": "source-markers",
                 ".py": "legacy-scripts", ".sh": "legacy-scripts",
                 ".txt": "analysis"}[extension]
        result.append((ROOT / "probes" / name, ROOT / "assets" / group / RENAMED_FILES.get(name, name)))
    return result


def stat_row(workspace, old, new):
    source = workspace / old
    if source.is_symlink() or not source.exists():
        raise ValueError("source missing or already a link: " + str(old))
    if (workspace / new).exists() or (workspace / new).is_symlink():
        raise ValueError("destination already exists: " + str(new))
    st = source.stat()
    if st.st_dev != (workspace / ROOT).stat().st_dev:
        raise ValueError("cross-filesystem rename: " + str(old))
    return {"old": old.as_posix(), "new": new.as_posix(),
            "device": st.st_dev, "inode": st.st_ino,
            "kind": "directory" if source.is_dir() else "file",
            "inventory": inventory(source)}


def inventory(path):
    result = {"files": 0, "directories": 0, "links": 0,
              "broken_links": 0, "file_bytes": 0}
    entries = [path] + list(path.rglob("*")) if path.is_dir() else [path]
    for entry in entries:
        if entry.is_symlink():
            result["links"] += 1
            result["broken_links"] += int(not entry.exists())
        elif entry.is_dir():
            result["directories"] += 1
        elif entry.is_file():
            result["files"] += 1
            result["file_bytes"] += entry.stat().st_size
        else:
            raise ValueError("unsupported file type: " + str(entry))
    return result


def plan(workspace):
    entries = [stat_row(workspace, old, new) for old, new in moves()]
    if len({row["old"] for row in entries}) != len(entries):
        raise ValueError("duplicate source")
    if len({row["new"] for row in entries}) != len(entries):
        raise ValueError("duplicate destination")
    return entries


def verify(workspace, entries):
    for row in entries:
        old, new = workspace / row["old"], workspace / row["new"]
        if not old.is_symlink() or old.resolve(strict=True) != new:
            raise ValueError("old path does not resolve to new path: " + row["old"])
        st = new.stat()
        if (st.st_dev, st.st_ino) != (row["device"], row["inode"]):
            raise ValueError("device or inode changed: " + row["new"])
        if (row["kind"] == "directory") != new.is_dir():
            raise ValueError("file kind changed: " + row["new"])
        if inventory(new) != row["inventory"]:
            raise ValueError("file inventory changed: " + row["new"])


def apply(workspace, manifest):
    entries = plan(workspace)
    manifest.parent.mkdir(parents=True, exist_ok=False)
    manifest.write_text(json.dumps({"schema_version": 1, "state": "in_progress", "moves": entries},
                                   indent=2, sort_keys=True) + "\n")
    try:
        for row in entries:
            old, new = workspace / row["old"], workspace / row["new"]
            new.parent.mkdir(parents=True, exist_ok=True)
            old.rename(new)
            old.symlink_to(os.path.relpath(str(new), str(old.parent)), target_is_directory=new.is_dir())
        verify(workspace, entries)
    except Exception:
        restore(workspace, entries)
        raise
    manifest.write_text(json.dumps({"schema_version": 1, "state": "applied", "moves": entries},
                                   indent=2, sort_keys=True) + "\n")
    return entries


def restore(workspace, entries):
    for row in reversed(entries):
        old, new = workspace / row["old"], workspace / row["new"]
        if new.exists():
            st = new.stat()
            if (st.st_dev, st.st_ino) != (row["device"], row["inode"]):
                raise ValueError("destination changed; stop rollback: " + row["new"])
            if inventory(new) != row["inventory"]:
                raise ValueError("destination contents changed; stop rollback: " + row["new"])
            if old.is_symlink() and old.resolve(strict=True) == new:
                old.unlink()
            elif old.exists() or old.is_symlink():
                raise ValueError("old path occupied; stop rollback: " + row["old"])
            new.rename(old)
        elif not old.exists() or old.is_symlink() or old.stat().st_ino != row["inode"]:
            raise ValueError("cannot restore: " + row["old"])


def rollback(workspace, manifest):
    document = json.loads(manifest.read_text())
    entries = document["moves"]
    restore(workspace, entries)
    document["state"] = "rolled_back"
    manifest.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--snapshot", required=True, help="迁移记录目录名，例如 legacy-20261030")
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--plan", action="store_true")
    action.add_argument("--apply", action="store_true")
    action.add_argument("--verify", action="store_true")
    action.add_argument("--rollback", action="store_true")
    args = parser.parse_args()
    if not args.snapshot.startswith("legacy-") or not args.snapshot.replace("-", "").isalnum():
        parser.error("snapshot must start with legacy- and contain only letters, digits and hyphens")
    workspace = args.workspace.resolve()
    manifest = workspace / ROOT / "migrations" / args.snapshot / "manifest.json"
    if args.plan:
        print("planned_moves=" + str(len(plan(workspace))))
    elif args.apply:
        print("applied_moves=" + str(len(apply(workspace, manifest))))
    elif args.verify:
        document = json.loads(manifest.read_text())
        verify(workspace, document["moves"])
        print("verified_moves=" + str(len(document["moves"])))
    else:
        rollback(workspace, manifest)
        print("rolled_back=" + str(len(json.loads(manifest.read_text())["moves"])))


if __name__ == "__main__":
    main()
