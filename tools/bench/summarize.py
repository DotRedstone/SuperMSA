#!/usr/bin/env python3
"""汇总一个运行目录：summary.tsv + run.env -> 报告（stdout）和 run.json。

配对：ORDER 按 4 个一组的 ABBA 块切分，每块给出两组配对差值 (A1-B2, A4-B3)。
判定：所有配对差值同号才判 faster / slower，否则判 inconclusive。
兼容 Python 3.6（集群登录节点）。
"""
import csv
import json
import shlex
import sys
from pathlib import Path


def read_env(path):
    env = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            parts = shlex.split(value)
            env[key] = parts[0] if parts else ""
    return env


def mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


def main():
    run = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    env = read_env(run / "run.env")
    with (run / "summary.tsv").open(encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    for r in rows:
        for k in ("prologue_s", "search_s", "total_s"):
            r[k] = float(r[k])
        # 各查询耗时之和：不受"最慢一条决定墙钟"的拖尾影响，查询数少时比墙钟更能反映方案效果。
        timing = run / "trials" / ("%s-%s" % (r["trial"], r["arm"])) / "timing.tsv"
        if timing.is_file():
            with timing.open(encoding="utf-8") as fh:
                r["query_sum_s"] = round(sum(float(t["seconds"]) for t in csv.DictReader(fh, delimiter="\t")), 1)

    order = env.get("ORDER", "")
    complete = len(rows) == len(order)
    arms = {a: [r for r in rows if r["arm"] == a] for a in "AB"}
    stats = {}
    for a, rs in arms.items():
        if rs:
            stats[a] = {k: round(mean([r[k] for r in rs]), 1)
                        for k in ("prologue_s", "search_s", "total_s", "query_sum_s")
                        if all(k in r for r in rs)}

    pairs = []
    for start in range(0, len(order) - 3, 4):
        if order[start:start + 4] == "ABBA" and start + 4 <= len(rows):
            t = [r["total_s"] for r in rows[start:start + 4]]
            pairs += [round(t[0] - t[1], 1), round(t[3] - t[2], 1)]

    lines = ["run      %s/%s/%s" % (env.get("TASK"), env.get("VARIANT"), env.get("RUN_ID")),
             "job      %s on %s" % (env.get("JOB_ID"), env.get("NODE")),
             "A(base)  %s %s env='%s'" % (env.get("BASE_REF"), env.get("BASE_SHA", "")[:12], env.get("BASE_ENV")),
             "B(tuned) %s %s env='%s'" % (env.get("TUNED_REF"), env.get("TUNED_SHA", "")[:12], env.get("TUNED_ENV")),
             "order    %s  queries=%s  complete=%s" % (order, env.get("QUERIES"), complete),
             ""]
    for a in "AB":
        if a in stats:
            s = stats[a]
            lines.append("%s mean   prologue=%7.1f  search=%7.1f  total=%7.1f  query_sum=%8.1f  (n=%d)"
                         % (a, s["prologue_s"], s["search_s"], s["total_s"],
                            s.get("query_sum_s", float("nan")), len(arms[a])))

    verdict = "incomplete" if not complete else "single-arm"
    saved = pct = None
    if complete and "A" in stats and "B" in stats:
        saved = round(stats["A"]["total_s"] - stats["B"]["total_s"], 1)
        pct = round(100.0 * saved / stats["A"]["total_s"], 2)
        lines.append("saved    %.1f s (%.2f%%)  paired A-B=%s" % (saved, pct, pairs))
        if pairs and all(p > 0 for p in pairs):
            verdict = "faster"
        elif pairs and all(p < 0 for p in pairs):
            verdict = "slower"
        else:
            verdict = "inconclusive"
        base_totals = [r["total_s"] for r in arms["A"]]
        lines.append("drift    base last-first = %.1f s" % (base_totals[-1] - base_totals[0]))
        if "query_sum_s" in stats["A"] and "query_sum_s" in stats["B"]:
            qa, qb = stats["A"]["query_sum_s"], stats["B"]["query_sum_s"]
            lines.append("query_sum %.1f -> %.1f s (%.2f%%)  不受拖尾影响，仅作参考；判定仍以总时间为准"
                         % (qa, qb, 100.0 * (qa - qb) / qa))
    lines.append("VERDICT=%s" % verdict)
    print("\n".join(lines))

    doc = {k.lower(): v for k, v in env.items()}
    doc.update(trials=[dict(r) for r in rows], means=stats, saved_s=saved,
               saved_pct=pct, paired_diffs_s=pairs, verdict=verdict)
    (run / "run.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                                  encoding="utf-8")


if __name__ == "__main__":
    main()
