#!/usr/bin/env python3
"""Validate MSA_RW_PROFILE logs from one jackhmmer process (Python 3.6)."""
import argparse
import collections
import math
import sys

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("log")
    p.add_argument("--workers",type=int,required=True)
    args=p.parse_args()
    rows=collections.defaultdict(list)
    with open(args.log, encoding="utf-8",errors="replace") as fp:
        for line in fp:
            if not line.startswith("MSA_RW_PROFILE "):
                continue
            d={}
            for term in line.strip().split()[1:]:
                k,sep,v=term.partition("=")
                if sep: d[k]=v
            for k in ("round","role","blocks","sequences","residues"):
                if k not in d: raise ValueError("missing {}: {}".format(k,line))
            for k in ("blocks","sequences","residues"):
                if int(d[k])<0: raise ValueError("negative {}".format(k))
            fields=("read_s","queue_s") if d["role"]=="reader" else ("wait_s","compute_s")
            for k in fields:
                v=float(d[k])
                if not math.isfinite(v) or v<0:
                    raise ValueError("invalid {}: {}".format(k,line))
            rows[int(d["round"])].append(d)
    if not rows: raise ValueError("no MSA_RW_PROFILE entries")
    for roundid in sorted(rows):
        group=rows[roundid]
        readers=[x for x in group if x["role"]=="reader"]
        workers=[x for x in group if x["role"]=="worker"]
        if len(readers)!=1 or len(workers)!=args.workers:
            raise ValueError("round {} has {} readers and {} workers, expected 1 and {}".format(
                roundid,len(readers),len(workers),args.workers))
        ids=[int(x["id"]) for x in workers]
        if sorted(ids)!=list(range(args.workers)):
            raise ValueError("round {} has invalid worker IDs {}".format(roundid,ids))
        reader=readers[0]
        for key in ("blocks","sequences","residues"):
            actual=sum(int(x[key]) for x in workers)
            expected=int(reader[key])
            if actual!=expected:
                raise ValueError("round {} {} reader={} worker_total={}".format(
                    roundid,key,expected,actual))
        if int(reader["sequences"]) == 0:
            raise ValueError("round {} no sequences".format(roundid))
        waits=sum(float(x["wait_s"]) for x in workers)
        computes=sum(float(x["compute_s"]) for x in workers)
        print("PROFILE_ROUND={} reader_read_s={} reader_queue_s={} "
              "worker_wait_sum_s={:.6f} worker_compute_sum_s={:.6f} "
              "blocks={} sequences={} residues={}".format(
                  roundid,reader["read_s"],reader["queue_s"],waits,computes,
                  reader["blocks"],reader["sequences"],reader["residues"]))
    print("READER_WORKER_PROFILE_VALID=PASS rounds={} workers={}".format(len(rows),args.workers))

if __name__ == "__main__":
    try:
        main()
    except (OSError,ValueError,KeyError) as e:
        print("READER_WORKER_PROFILE_VALID=FAIL: {}".format(e),file=sys.stderr)
        sys.exit(1)
