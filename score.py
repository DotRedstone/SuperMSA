#!/usr/bin/env python3
"""Score search results against the SCOP labels carried by the released data.

Labels come straight from the data directory:
  * database.fasta: annotated sequences look like
        >annotated_C9ST65 g.78.1.1 |1.7e-06 |g1sse.1 |35-121 |349-433
    (a full-length protein may carry several SCOP domains before the first
    "|"); every other sequence is a reversed decoy and has no label.
  * query/*.fasta: the header carries the query's own SCOP code(s).

Judging convention:

  hit                                              verdict
  ------------------------------------------------ --------------------------
  annotated_ header without a SCOP code             skipped (not counted)
  any domain in the query's superfamily             TP  (counts toward recall)
  otherwise any domain in the query's fold          ignored (homology disputed)
  otherwise query or hit has a class e domain       ignored
  otherwise both have a b.67-b.70 domain            ignored (beta-propellers)
  otherwise labeled (different fold)                FP
  no label at all (reversed decoy)                  FP

The ignore/skip rules follow the MMseqs2 benchmark evaluator (EvaluateResults.cpp):
SCOP class e ("multi-domain proteins") has ambiguous assignments, and the
beta-propeller folds b.67-b.70 are easily confused with each other. Unlike
MMseqs2, which counts TPs at the family level, TPs here are counted at the
superfamily level to reward remote homologs. The query's own source protein,
if present in the database, is an ordinary hit (TP).

Metrics per query, then averaged over all official queries:
  recall    = TP / (database sequences in the query's superfamily)
  precision = TP / (TP + FP)
  ROC1      = true homologs ranked above the first FP, / all true homologs
  ROC10     = Gribskov-Robinson ROC_n, n=10: mean over the first 10 FPs of
              "true homologs ranked above it", / all true homologs.
              Fewer than 10 FPs: the curve stays flat at the final TP count.
ROC metrics READ THE HIT FILE IN ORDER -- write hits most significant first.
ROC10 is the primary quality metric.

Every file in query/ is an official query. A query without a hit table
scores 0 on every metric.

Correctness: with --baseline, a query is correct if its ROC10 >= 90% of the
baseline's ROC10 for that query; the number of incorrect queries is reported.

Usage: score.py [--data DIR] [--results DIR] [--baseline FILE] [--format tbl|m8] [-o FILE]
  --data      released data directory (default: ../preliminary next to the repo)
  --results   run_queries.sh output directory (default: results/ in the repo)
  --baseline  scores.tsv written by this script for the baseline run
Reads <results>/tbl/*.tbl (hmmer --tblout) or *.m8 (query,target in cols 1,2).
Official scoring is recomputed offline by the organizers; submitted hit tables
must be produced by your actual search program.
"""
import argparse
import collections
import glob
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.abspath(__file__))
SCCS = re.compile(r'^[a-z]\.\d+\.\d+\.\d+$')
ROC_N = 10
PASS_RATIO = 0.9
PROPELLER = ('b.67', 'b.68', 'b.69', 'b.70')


def superfamily(code):
    return code.rsplit('.', 1)[0]


def fold(code):
    return '.'.join(code.split('.')[:2])


def domains(codes):
    """-> (superfamilies, folds, has class e, has beta-propeller) of SCOP codes."""
    folds = frozenset(fold(c) for c in codes)
    return (frozenset(superfamily(c) for c in codes), folds,
            any(c.startswith('e.') for c in codes), any(f in PROPELLER for f in folds))


def header_codes(fields):
    """SCOP codes in a header, i.e. the tokens before the first '|' field."""
    codes = []
    for tok in fields:
        if tok.startswith('|'):
            break
        if SCCS.match(tok):
            codes.append(tok)
    return codes


def annotated_headers(db):
    """Yield the header lines of labeled sequences (grep when available)."""
    try:
        p = subprocess.Popen(['grep', '^>annotated_', db], stdout=subprocess.PIPE,
                             env=dict(os.environ, LC_ALL='C'))
    except OSError:
        with open(db) as fh:
            for line in fh:
                if line.startswith('>annotated_'):
                    yield line
        return
    for line in p.stdout:
        yield line.decode('ascii', 'replace')
    p.wait()


def load_labels(db):
    """-> id -> domains(); superfamily -> member count."""
    labels = {}
    sf_size = collections.Counter()
    for line in annotated_headers(db):
        f = line.split()
        lab = labels[f[0][1:]] = domains(header_codes(f[1:]))
        for s in lab[0]:
            sf_size[s] += 1
    return labels, sf_size


def load_queries(qdir):
    """-> query id -> domains(), from the query headers."""
    queries = {}
    for path in sorted(glob.glob(os.path.join(qdir, '*.fasta'))):
        with open(path) as fh:
            f = fh.readline()[1:].split()
        codes = header_codes(f[1:])
        if codes:
            queries[f[0]] = domains(codes)
    return queries


def read_hits(paths, fmt):
    """-> query -> target ids in file (rank) order, deduplicated."""
    hits = collections.defaultdict(list)
    seen = collections.defaultdict(set)
    for path in paths:
        with open(path) as fh:
            for line in fh:
                if not line.strip() or line.startswith('#'):
                    continue
                f = line.split()
                q, t = (f[0], f[1]) if fmt == 'm8' else (f[2], f[0])
                if t not in seen[q]:
                    seen[q].add(t)
                    hits[q].append(t)
    return hits


def score_query(q, qlab, targets, labels, sf_size):
    qsf, qfold, q_e, q_prop = qlab
    n_true = sum(sf_size[s] for s in qsf)
    tp = fp = ign = 0
    first_fp = 0
    tp_above_fp = []          # true homologs ranked above the i-th FP
    for rank, t in enumerate(targets, 1):
        lab = labels.get(t)
        if lab is not None:
            sfs, folds, e, prop = lab
            if not sfs:
                continue
            if sfs & qsf:
                tp += 1
                continue
            if folds & qfold or e or q_e or (prop and q_prop):
                ign += 1
                continue
        fp += 1
        if not first_fp:
            first_fp = rank
        if len(tp_above_fp) < ROC_N:
            tp_above_fp.append(tp)
    while len(tp_above_fp) < ROC_N:
        tp_above_fp.append(tp)
    recall = tp / n_true if n_true else 0.0
    precision = tp / (tp + fp) if tp + fp else 0.0
    roc1 = tp_above_fp[0] / n_true if n_true else 0.0
    roc10 = sum(tp_above_fp) / (ROC_N * n_true) if n_true else 0.0
    return (q, ','.join(sorted(qsf)), n_true, len(targets), tp, fp, ign,
            first_fp, recall, precision, roc1, roc10)


def load_baseline(path):
    """-> query -> baseline ROC10, from a scores.tsv written by this script."""
    with open(path) as fh:
        cols = fh.readline().rstrip('\n').split('\t')
        qi, ri = cols.index('query'), cols.index('roc10')
        return {f[qi]: float(f[ri]) for f in (line.rstrip('\n').split('\t') for line in fh)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default=os.path.join(os.path.dirname(REPO), 'preliminary'),
                    help='released data directory (query/ + database.fasta)')
    ap.add_argument('--results', default=os.path.join(REPO, 'results'),
                    help='run_queries.sh output directory')
    ap.add_argument('--baseline', default=None,
                    help='scores.tsv of the baseline run, for the per-query correctness check')
    ap.add_argument('--format', choices=['tbl', 'm8'], default='tbl')
    ap.add_argument('-o', '--output', default=None)
    args = ap.parse_args()

    db = os.path.join(args.data, 'database.fasta')
    qdir = os.path.join(args.data, 'query')
    for p in (db, qdir):
        if not os.path.exists(p):
            sys.exit('ERROR: %s not found (set --data)' % p)
    ext = '*.m8' if args.format == 'm8' else '*.tbl'
    files = sorted(glob.glob(os.path.join(args.results, 'tbl', ext)))
    if not files:
        sys.exit('ERROR: no %s files under %s' % (ext, os.path.join(args.results, 'tbl')))

    queries = load_queries(qdir)
    print('reading labels from %s ...' % db, flush=True)
    labels, sf_size = load_labels(db)
    hits = read_hits(files, args.format)

    # A query "has a hit table" if one was written for it, even with zero hits
    # (run_queries.sh names each file <query>.tbl).
    produced = set(hits) | set(os.path.basename(p).rsplit('.', 1)[0] for p in files)
    rows = []
    missing = []
    for q in sorted(queries):
        if q not in produced:
            missing.append(q)
        rows.append(score_query(q, queries[q], hits.get(q, []), labels, sf_size))
    extra = sorted(set(hits) - set(queries))

    baseline = load_baseline(args.baseline) if args.baseline else {}
    checks = []               # (baseline ROC10, correct) per row; None if not judged
    for r in rows:
        base = baseline.get(r[0])
        checks.append(None if base is None else (base, r[11] >= PASS_RATIO * base))

    out_path = args.output or os.path.join(args.results, 'scores.tsv')
    with open(out_path, 'w') as fh:
        fh.write('query\tsuperfamily\ttrue_homologs\thits\ttp\tfp\tignored'
                 '\tfirst_fp_rank\trecall\tprecision\troc1\troc10\tbaseline_roc10\tcorrect\n')
        for r, c in zip(rows, checks):
            fh.write('%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%.4f\t%.4f\t%.4f\t%.4f' % r)
            fh.write('\t-\t-\n' if c is None else '\t%.4f\t%s\n' % c)

    print('%-16s %-12s %8s %6s %6s %5s %5s %7s %7s %7s %7s %7s  %s'
          % ('query', 'superfamily', 'homologs', 'hits', 'TP', 'FP', 'ign',
             'recall', 'prec', 'ROC1', 'ROC10', 'base', 'correct'))
    for r, c in zip(rows, checks):
        print('%-16s %-12s %8d %6d %6d %5d %5d %7.4f %7.4f %7.4f %7.4f' % (r[:7] + r[8:])
              + ('       -  -' if c is None else ' %7.4f  %s' % c))

    n = len(rows)
    mean = lambda i: sum(r[i] for r in rows) / n
    print('labeled sequences in database: %d  (%d superfamilies)' % (len(labels), len(sf_size)))
    print('official queries: %d  |  with hit table: %d  |  detail: %s'
          % (n, n - len(missing), out_path))
    if missing:
        print('WARNING: %d official queries have no hit table and score 0: %s%s'
              % (len(missing), ' '.join(missing[:5]), ' ...' if len(missing) > 5 else ''))
    if extra:
        print('note: %d hit-table queries are not official and were ignored' % len(extra))
    print('mean recall    = %.4f' % mean(8))
    print('mean precision = %.4f' % mean(9))
    print('mean ROC1      = %.4f' % mean(10))
    print('mean ROC10     = %.4f   <- primary quality metric' % mean(11))
    judged = [c[1] for c in checks if c is not None]
    if judged:
        print('incorrect      = %d / %d queries (ROC10 < %d%% of baseline)'
              % (judged.count(False), len(judged), PASS_RATIO * 100))
    if args.baseline and len(judged) < n:
        print('WARNING: %d queries are not in the baseline file and were not judged' % (n - len(judged)))

    wall = os.path.join(args.results, 'wall_time.tsv')
    if os.path.exists(wall):
        with open(wall) as fh:
            fh.readline()
            f = fh.readline().rstrip('\n').split('\t')
        try:
            secs, ran, skipped = float(f[0]), int(f[1]), int(f[2])
        except (IndexError, ValueError):
            print('WARNING: cannot parse %s' % wall)
        else:
            print('search time    = %.1f s   <- official: wall clock from end of warm-up '
                  'to last query (%d run)' % (secs, ran))
            if skipped:
                print('WARNING: %d queries reused earlier results; this time is NOT a valid '
                      'official time (clear the output dir or set FORCE=1)' % skipped)
    else:
        print('search time    = n/a (no wall_time.tsv in %s)' % args.results)

if __name__ == '__main__':
    main()
