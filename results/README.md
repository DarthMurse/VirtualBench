# Results

Each machine writes one JSON file per run to `results/<label>/result_<UTCstamp>.json`
and commits it. The schema is flat and self-describing:

```json
{
  "meta": { "label": "virtualbox", "timestamp": "20260605T120000Z", "hostname": "...",
            "os": "...", "kernel": "...", "allocated_vcpus": 4, "visible_nproc": 4,
            "total_mem_mb": 8192, "repetitions": 7, "runner": "linux", "capped": false },
  "metrics": [
    { "workload": "cpu", "metric": "7z_total_mips", "value": 12345, "unit": "MIPS",
      "params": { "threads": 4 } }
  ]
}
```

Suggested labels: `host-baseline` (Windows host), `virtualbox`, `hyperv`. The analyzer
treats `host-baseline` / `host` / `baremetal` as the baseline for %-of-baseline columns.

Aggregate everything with:

```bash
python3 analyze/analyze.py results
```
