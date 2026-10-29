#!/usr/bin/env python3
"""Read-only diagnostics for independent HMMER --tblout runs (Python >=3.6).

Unlike compare_hit_tables.py this tool never sets a correctness tolerance:
it reports observed drift over ALL selected queries and candidate sets.
Usage:
 python3 diagnose_hit_drift.py --queries queries.selected --reference DIR \
   --candidate raw08=DIR --candidate t1=DIR --candidate t2=DIR --candidate t3=DIR

No output files are modified; script prints deltas, max/min and examples.
"""
import argparse
import collections
import math
from pathlib import Path

NUMERIC = {4:"full_e", 5:"full_score", 6:"full_bias", 7:"best_e",
           8:"best_score", 9:"best_bias", 10:"exp"}
INTS = range(11, 18)


def read_tbl(path):
    rows = {}
    order = []
    with path.open("r", encoding="utf-8", errors="replace") as fp:
        for n, line in enumerate(fp, 1):
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.split(maxsplit=18)
            if len(fields) < 18:
                raise ValueError("{}:{} malformed {} fields".format(path,n,len(fields)))
            name = fields[0]
            if name in rows:
                raise ValueError("{}:{} duplicate {}".format(path,n,name))
            rows[name] = fields
            order.append(name)
    return rows, order


def compare(refdir, testdir, qids):
    counts = collections.Counter()
    stats = {idx:{"max_abs":0., "max_rel":0., "gt025":0, "gt05":0,
                  "gt20pct":0, "example":None} for idx in NUMERIC}
    examples = []
    for sid in qids:
        ra, oa = read_tbl(refdir / (sid+".tbl"))
        rb, ob = read_tbl(testdir / (sid+".tbl"))
        sa, sb = set(ra), set(rb)
        counts["queries"] += 1
        counts["reference_hits"] += len(sa)
        counts["candidate_hits"] += len(sb)
        counts["missing_targets"] += len(sa-sb)
        counts["extra_targets"] += len(sb-sa)
        if sa != sb and len(examples)<12:
            examples.append("{} targets missing={} extra={}".format(sid,
                        sorted(sa-sb)[:3], sorted(sb-sa)[:3]))
        common = sa & sb
        posa = {v:i for i,v in enumerate(oa)}
        posb = {v:i for i,v in enumerate(ob)}
        for name in common:
            a,b = ra[name],rb[name]
            counts["matching_targets"] += 1
            if a[1]!=b[1] or a[2]!=b[2] or a[3]!=b[3] or (len(a)>18 and len(b)>18 and a[18]!=b[18]):
                counts["metadata_diffs"] += 1
                if len(examples)<12:
                    examples.append("{} {} metadata".format(sid,name))
            if any(a[k]!=b[k] for k in INTS):
                counts["integer_diffs"] += 1
                if len(examples)<12:
                    examples.append("{} {} domain-count".format(sid,name))
            if posa[name]!=posb[name]:
                counts["position_changes"] += 1
            for idx in NUMERIC:
                try:
                    x,y=float(a[idx]),float(b[idx])
                except (ValueError,IndexError):
                    counts["invalid_numeric"]+=1
                    continue
                if not math.isfinite(x) or not math.isfinite(y):
                    counts["invalid_numeric"]+=1
                    continue
                d=abs(x-y)
                denom=max(abs(x),abs(y))
                rel=d/denom if denom else 0.
                stat=stats[idx]
                if d>stat["max_abs"]:
                    stat["max_abs"]=d
                if rel>stat["max_rel"]:
                    stat["max_rel"]=rel
                if d>0.25+1e-9: stat["gt025"]+=1
                if d>0.50+1e-9: stat["gt05"]+=1
                if rel>0.20+1e-9: stat["gt20pct"]+=1
                if stat["example"] is None or d>stat["example"][0]:
                    stat["example"]=(d, sid, name, x, y)
        # Count non-tied adjacent rank inversions as a low-cost signal;
        # pairwise inversions require a separate full ranking check.
        shared=[x for x in ob if x in posa]
        last_pos=-1
        for name in shared:
            if posa[name]<last_pos:
                counts["order_backtracks"]+=1
            last_pos=max(last_pos,posa[name])
    return counts,stats,examples


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--queries",required=True,type=Path)
    p.add_argument("--reference",required=True,type=Path)
    p.add_argument("--candidate",action="append",required=True,
                   help="label=directory; repeat for each candidate")
    args=p.parse_args()
    qids=[x.strip() for x in args.queries.read_text(encoding="utf-8").splitlines()
          if x.strip() and not x.lstrip().startswith("#")]
    if len(qids)!=len(set(qids)) or not qids:
        raise SystemExit("invalid query list")
    for spec in args.candidate:
        label,sep,path=spec.partition("=")
        if not sep or not label or not path:
            raise SystemExit("use --candidate label=directory")
        print("\n=== {} ===".format(label))
        try:
            counts,stats,examples=compare(args.reference,Path(path),qids)
        except (OSError, ValueError) as e:
            print("ERROR: {}".format(e))
            continue
        for key in ("queries","reference_hits","candidate_hits","missing_targets",
                    "extra_targets","metadata_diffs","integer_diffs","invalid_numeric",
                    "position_changes","order_backtracks"):
            print("{}={}".format(key,counts[key]))
        for idx,name in NUMERIC.items():
            st=stats[idx]
            ex=st["example"]
            sample=("{} {} {} -> {}".format(ex[1],ex[2],ex[3],ex[4])
                    if ex else "-")
            print("{} max_abs={:.6g} max_rel={:.4g} gt0.25={} gt0.5={} gt20pct={} worst={}".format(
                  name,st["max_abs"],st["max_rel"],st["gt025"],st["gt05"],st["gt20pct"],sample))
        if examples:
            print("OTHER_DIFFS:")
            for ex in examples: print("  "+ex)


if __name__=="__main__":
    main()
