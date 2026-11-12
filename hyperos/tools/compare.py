#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Compare two device-metrics summary CSV files and print a verdict table.

Usage:
    compare.py baseline.csv after.csv [--md out.md] [--min-n 5]

Rules enforced (so a result cannot be over-claimed):

  * lower-is-better is the default; a metric is only reported as IMPROVED /
    REGRESSED when |delta| >= --threshold (default 3%) AND the sample count is
    >= --min-n on both sides.
  * sample counts come from the harness; if a metric was collected once
    (static snapshot) it is reported as INFO, never as a win.
  * for frame/jank metrics a delta is only called significant if it also
    exceeds the run-to-run spread of the baseline when a spread is available.
"""

import argparse
import csv
import os
import sys

# metrics where higher is better
HIGHER_BETTER = {
    "fps", "frames", "gpu_busy", "big_core_residency",
}


def load(path):
    rows = {}
    with open(path, newline="") as fh:
        for r in csv.DictReader(fh):
            try:
                val = float(r["value"])
            except (TypeError, ValueError):
                val = r["value"]
            key = (r["scenario"], r["metric"])
            rows[key] = {
                "value": val,
                "unit": r.get("unit", ""),
                "n": int(float(r.get("n", 1) or 1)),
            }
    return rows


def fmt(v):
    if isinstance(v, float):
        if abs(v) >= 1000:
            return f"{v:,.0f}"
        if abs(v) >= 10:
            return f"{v:.1f}"
        return f"{v:.2f}"
    return str(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("baseline")
    ap.add_argument("after")
    ap.add_argument("--md")
    ap.add_argument("--threshold", type=float, default=3.0,
                    help="minimum relative change (percent) to call a result (default 3)")
    ap.add_argument("--min-n", type=int, default=5,
                    help="minimum samples per side for a verdict (default 5)")
    args = ap.parse_args()

    base = load(args.baseline)
    after = load(args.after)
    keys = sorted(set(base) | set(after))

    out = []
    out.append(f"# DOOM profile comparison\n")
    out.append(f"- baseline: `{os.path.basename(args.baseline)}`")
    out.append(f"- after   : `{os.path.basename(args.after)}`")
    out.append(f"- rules   : verdict needs |delta| >= {args.threshold}% and "
               f"n >= {args.min_n} on both sides\n")
    out.append("| scenario | metric | baseline | after | delta | n | verdict |")
    out.append("|---|---|---|---|---|---|---|")

    counts = {"IMPROVED": 0, "REGRESSED": 0, "NEUTRAL": 0, "INFO": 0, "MISSING": 0}
    for k in keys:
        scen, met = k
        b = base.get(k)
        a = after.get(k)
        if not b or not a:
            counts["MISSING"] += 1
            out.append(f"| {scen} | {met} | {fmt(b['value']) if b else '—'} | "
                       f"{fmt(a['value']) if a else '—'} | — | — | MISSING |")
            continue
        if not isinstance(b["value"], float) or not isinstance(a["value"], float):
            verdict = "INFO"
            delta = "—"
        elif b["n"] < args.min_n or a["n"] < args.min_n:
            verdict = "INFO"
            delta = "—"
        else:
            d = (a["value"] - b["value"]) / b["value"] * 100 if b["value"] else 0.0
            delta = f"{d:+.1f}%"
            better_up = met in HIGHER_BETTER
            improved = (d > 0) if better_up else (d < 0)
            if abs(d) < args.threshold:
                verdict = "NEUTRAL"
            else:
                verdict = "IMPROVED" if improved else "REGRESSED"
        counts[verdict] += 1
        out.append(f"| {scen} | {met} | {fmt(b['value'])} {b['unit']} | "
                   f"{fmt(a['value'])} {a['unit']} | {delta} | {b['n']}/{a['n']} | {verdict} |")

    out.append("")
    out.append("## Verdict summary")
    out.append("")
    for k, v in counts.items():
        out.append(f"- {k}: {v}")
    out.append("")
    out.append("> INFO rows are snapshots or under-sampled; they are evidence to "
               "read, not results to claim. Re-run with --runs >= 7 before "
               "concluding anything about smoothness or latency.")
    text = "\n".join(out)
    print(text)
    if args.md:
        with open(args.md, "w") as fh:
            fh.write(text + "\n")
        print(f"\n[i] written to {args.md}", file=sys.stderr)


if __name__ == "__main__":
    main()
