# results/

One subdirectory per machine label; one JSON file per run.

```
results/
  virtualbox/    result_<UTCstamp>.json   # from the VirtualBox VM
  hyperv/        result_<UTCstamp>.json   # from the Hyper-V VM
  host-baseline/ result_<UTCstamp>.json   # from the capped bare-metal host
```

These files are **committed to git** — that's how results from each machine are
collected into one place. After a run, the runner prints the exact
`git add / commit / push` commands for that machine's folder.

Each file is self-describing: a `meta` block (label, OS, allocated vcpus, capped
flag, timestamp) plus a flat `metrics` array. Aggregate across machines with:

```
python analyze/analyze.py results
```

If a `host-baseline/` folder is present, the analysis reports each VM's numbers
as a percentage of the bare-metal baseline (the virtualization overhead).
