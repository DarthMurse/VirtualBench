#!/usr/bin/env python3
"""
VirtualBench — aggregate per-machine results into a comparison.

Reads every results/<label>/result_*.json (produced by run.sh / run.ps1),
groups metrics by (workload, metric, params), and reports median + spread per
machine label. If a 'host-baseline' label exists, also reports each VM's value
as a percentage of that baseline (the virtualization overhead).

Usage:
    python analyze/analyze.py [results_dir]   # default: ./results

No third-party deps — stdlib only.
"""
import json, sys, glob, os, statistics
from collections import defaultdict

BASELINE_LABELS = ("host-baseline", "host", "baremetal")


def load(results_dir):
    # records[(workload, metric, params_key)][label] = [values...]
    records = defaultdict(lambda: defaultdict(list))
    meta_by_label = {}
    for path in glob.glob(os.path.join(results_dir, "*", "result_*.json")):
        with open(path) as f:
            doc = json.load(f)
        label = doc["meta"]["label"]
        meta_by_label[label] = doc["meta"]
        for m in doc["metrics"]:
            if m["unit"] in ("skipped",):
                continue
            pkey = json.dumps(m.get("params", {}), sort_keys=True)
            key = (m["workload"], m["metric"], pkey, m["unit"])
            try:
                records[key][label].append(float(m["value"]))
            except (TypeError, ValueError):
                pass
    return records, meta_by_label


def summarize(values):
    med = statistics.median(values)
    cv = (statistics.pstdev(values) / med * 100) if med and len(values) > 1 else 0.0
    return med, cv, len(values)


def find_baseline(labels):
    for b in BASELINE_LABELS:
        if b in labels:
            return b
    return None


def main():
    results_dir = sys.argv[1] if len(sys.argv) > 1 else "results"
    records, meta = load(results_dir)
    if not records:
        print(f"No results found under {results_dir}/<label>/result_*.json")
        return

    labels = sorted(meta.keys())
    baseline = find_baseline(labels)
    print(f"Machines: {', '.join(labels)}")
    if baseline:
        print(f"Baseline for overhead %: '{baseline}'")
    print("=" * 88)

    for key in sorted(records):
        workload, metric, pkey, unit = key
        params = json.loads(pkey)
        pstr = " ".join(f"{k}={v}" for k, v in params.items() if not k.startswith("_"))
        print(f"\n[{workload}] {metric} ({unit})  {pstr}")
        base_med = None
        if baseline and baseline in records[key]:
            base_med, _, _ = summarize(records[key][baseline])
        for label in labels:
            if label not in records[key]:
                continue
            med, cv, n = summarize(records[key][label])
            line = f"  {label:16s} median={med:14.2f}  cv={cv:5.1f}%  n={n}"
            if base_med and label != baseline and base_med != 0:
                line += f"  ({med / base_med * 100:5.1f}% of baseline)"
            print(line)


if __name__ == "__main__":
    main()
