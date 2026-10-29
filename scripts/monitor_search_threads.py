#!/usr/bin/env python3
"""Low-frequency, best-effort thread count sampler for one snapshot binary.

One TSV row per sample. Counts only matching JackHMMER processes, not
Python/shell/xargs launcher tasks; the latter are mostly sleeping and are
reported separately as a scheduling caveat.
"""
import os
import sys
import time

if len(sys.argv) != 3:
    raise SystemExit("usage: monitor_search_threads.py /abs/path/to/jackhmmer interval_s")
target = os.path.realpath(sys.argv[1])
interval = float(sys.argv[2])
if not (0.25 <= interval <= 30):
    raise SystemExit("sampling interval must be between 0.25 and 30 seconds")

print("timestamp\tprocesses\tthreads_total\tthreads_max\tpid_thread_counts", flush=True)
while True:
    rows = []
    for entry in os.scandir("/proc"):
        if not entry.name.isdecimal():
            continue
        try:
            if os.path.realpath(os.readlink(f"/proc/{entry.name}/exe")) != target:
                continue
            with os.scandir(f"/proc/{entry.name}/task") as tasks:
                count = sum(1 for _ in tasks)
            rows.append((int(entry.name), count))
        except (PermissionError, FileNotFoundError, ProcessLookupError, OSError):
            continue
    total = sum(threads for _, threads in rows)
    largest = max((threads for _, threads in rows), default=0)
    details = ",".join(f"{pid}:{count}" for pid, count in sorted(rows))
    print(f"{time.time():.3f}\t{len(rows)}\t{total}\t{largest}\t{details}", flush=True)
    time.sleep(interval)
