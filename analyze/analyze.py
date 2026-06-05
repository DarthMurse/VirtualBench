#!/usr/bin/env python3
"""Aggregate VirtualBench results into a comparison table.

Scans results/<label>/result_*.json, groups every metric by
(workload, metric, unit, params), and reports the median and coefficient of
variation (CV%) per label. If a baseline label is present (host-baseline / host /
baremetal), each VM's median is also shown as a percentage of that baseline.

Usage: python3 analyze/analyze.py [results_dir]   (default: results)
Stdlib only — no third-party dependencies.
"""
import glob
import json
import os
import statistics
import sys
from collections import defaultdict

BASELINE_LABELS = ("host-baseline", "host", "baremetal")


def params_str(params):
    if not params:
        return ""
    return " ".join(f"{k}={params[k]}" for k in sorted(params))


def load(results_dir):
    # data[(workload, metric, unit, pstr)][label] = [values...]
    data = defaultdict(lambda: defaultdict(list))
    for path in sorted(glob.glob(os.path.join(results_dir, "*", "result_*.json"))):
        try:
            # utf-8-sig tolerates a leading BOM (the Windows runner used to emit one).
            with open(path, encoding="utf-8-sig") as fh:
                doc = json.load(fh)
        except (OSError, json.JSONDecodeError) as exc:
            print(f"warning: skipping {path}: {exc}", file=sys.stderr)
            continue
        label = doc.get("meta", {}).get("label", os.path.basename(os.path.dirname(path)))
        for m in doc.get("metrics", []):
            value = m.get("value")
            if not isinstance(value, (int, float)):  # "skipped" etc.
                continue
            key = (m["workload"], m["metric"], m.get("unit", ""), params_str(m.get("params")))
            data[key][label].append(value)
    return data


def find_baseline(labels):
    for cand in BASELINE_LABELS:
        if cand in labels:
            return cand
    return None


def main():
    results_dir = sys.argv[1] if len(sys.argv) > 1 else "results"
    data = load(results_dir)
    if not data:
        print(f"no numeric metrics found under {results_dir}/", file=sys.stderr)
        return 1

    for (workload, metric, unit, pstr) in sorted(data):
        per_label = data[(workload, metric, unit, pstr)]
        header = f"[{workload}] {metric} ({unit})"
        if pstr:
            header += f"  {pstr}"
        print(header)

        medians = {lab: statistics.median(v) for lab, v in per_label.items()}
        baseline = find_baseline(per_label.keys())
        base_med = medians.get(baseline)

        for label in sorted(per_label):
            vals = per_label[label]
            med = medians[label]
            cv = (statistics.pstdev(vals) / med * 100) if len(vals) > 1 and med else 0.0
            line = f"  {label:<16} median={med:<12.2f} cv={cv:>5.1f}%  n={len(vals)}"
            if base_med and label != baseline:
                line += f"   ({med / base_med * 100:.1f}% of baseline)"
            print(line)
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
