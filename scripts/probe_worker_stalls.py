#!/usr/bin/env python3
"""Sample scheduling states and wait channels for a jackhmmer subprocess.

The sampler does NOT claim to know if a sleeping thread is waiting for input.
A futex wait could also mean queue synchronization or barrier waiting.
Always combine this probe with a timing sweep and/or perf scheduling traces.

Usage: python3 scripts/probe_worker_stalls.py REPORT.tsv -- JACKHMMER args...
No root access or privileged perf_event permissions required.
"""
import os
import subprocess
import sys
import time
from pathlib import Path

if len(sys.argv) < 4 or sys.argv[2] != "--":
    raise SystemExit("usage: probe_worker_stalls.py REPORT.tsv -- executable args...")
report = Path(sys.argv[1])
cmd = sys.argv[3:]
if not cmd:
    raise SystemExit("no command")
proc = subprocess.Popen(cmd)
samples = 0
try:
    with report.open("w", encoding="utf-8", buffering=1) as fp:
        fp.write("timestamp\tpid\ttid\tstate\twchan\n")
        while proc.poll() is None:
            taskdir = Path("/proc") / str(proc.pid) / "task"
            try:
                tids = list(taskdir.iterdir())
            except (FileNotFoundError, PermissionError):
                break
            now = time.time()
            for task in tids:
                try:
                    status = (task / "status").read_text(encoding="ascii")
                    state = next(
                        (line.split("\t", 1)[-1].strip()
                         for line in status.splitlines() if line.startswith("State:")),
                        "unknown"
                    )
                    wchan = (task / "wchan").read_text(encoding="ascii").strip()
                except (OSError, UnicodeError):
                    continue
                fp.write(f"{now:.3f}\t{proc.pid}\t{task.name}\t{state}\t{wchan}\n")
            samples += 1
            time.sleep(0.25)
finally:
    ret = proc.wait()
print(f"QUEUE_STALL_PROBE samples={samples} process_exit={ret} report={report}", file=sys.stderr)
sys.exit(ret)
