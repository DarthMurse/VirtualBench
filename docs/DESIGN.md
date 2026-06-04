# VirtualBench — Design & Methodology

## Goal

Compare the performance overhead of different **VM hypervisors** (first:
VirtualBox vs Hyper-V) running identical workloads on the same physical host and
the same guest OS. The independent variable is the **hypervisor**; everything
else is a control.

## Workflow (manual, per machine)

There is **no central orchestrator and no SSH**. The benchmark is a
self-contained payload you run by hand on each target:

1. Copy this repo onto the target (or clone it).
2. Run the appropriate runner with a machine label:
   - Linux guest (VirtualBox / Hyper-V VM): `./benchmark/run.sh --label virtualbox`
   - Windows host (bare-metal baseline): `.\benchmark\run.ps1 -Label host-baseline`
3. The runner writes `results/<label>/result_<UTCstamp>.json`.
4. The runner **prints** the `git add/commit/push` commands. Run them to publish
   that machine's results. (Auto-push is intentionally off.)
5. Once every machine has pushed, run `python analyze/analyze.py results`.

## Controls (must be identical everywhere)

| Variable | Value | Where enforced |
|---|---|---|
| vCPUs | `config.vm_spec.vcpus` | VM settings; host run capped via Job Object |
| RAM | `config.vm_spec.memory_mb` | VM settings; host run capped via Job Object |
| Guest OS | same Ubuntu image | manual |
| Workload params | `config.workloads.*` | shared config, both runners |
| Repetitions / warmup | `config.run.*` | both runners |

### The capped host baseline

The host has far more CPU/RAM than a VM, so running the suite on the full host
would be meaningless. `benchmark/restrict.ps1` creates a **Windows Job Object**
that limits the runner (and every tool it spawns) to:
- the first *N* logical processors (affinity mask), and
- a total committed-memory ceiling of `memory_mb`.

This makes the bare-metal run a fair reference point for "what does the
hypervisor cost vs. the same resources with no virtualization."

## Tool choices (cross-platform where possible)

| Workload | Linux (guest) | Windows (host) | Comparable? |
|---|---|---|---|
| CPU | `7z b` (MIPS) | `7z b` (MIPS) | Yes |
| Disk | `fio` (libaio) | `fio` (windowsaio) | Mostly — different ioengine |
| Network | `iperf3` + `ping` | `iperf3` | Yes |
| App | `7z a` timed compress | `7z a` timed compress | Yes |
| Memory | `sysbench memory` | (approximated by CPU) | **No** — Windows lacks a matching tool here |

> **Caveat (accepted):** the host runs Windows while guests run Linux. Most
> tools have native builds on both, but OS scheduler/filesystem/driver
> differences mean **host-vs-guest absolute numbers are not strictly
> comparable**. They are a directional baseline. **VM-vs-VM** comparisons (both
> Linux) are fully apples-to-apples and are the primary result.

## Methodology rules

- **Repetitions:** `config.run.repetitions` (default 7). Report **median** and
  **coefficient of variation**, never a single number. A gap smaller than the CV
  is not a real difference.
- **Warm-up:** first `warmup_runs` are discarded (page cache, JIT, CPU freq ramp).
- **Interleave manually:** run a round on VirtualBox, then Hyper-V, then repeat,
  rather than finishing all of one first — so slow host/thermal drift is shared.
- **Fair guest tooling:** install paravirtual drivers (Guest Additions /
  Integration Services + virtio) for **both** hypervisors, or neither. Mixing
  (e.g. virtio-net on one, emulated NIC on the other) invalidates the network and
  disk comparison.
- **Network target:** point `config.workloads.net.server` at a **separate**
  physical box on the same switch running `iperf3 -s`. Testing against the host
  measures loopback, not the virtual NIC.
- **Quiesce:** nothing else running on the host during a run; fixed BIOS/power
  settings; disable turbo/freq-scaling or document that it's on.
- **Reset between runs:** restore the VM to a clean snapshot so caches/logs/disk
  fragmentation don't accumulate across runs.

## Result schema

```jsonc
{
  "meta": {
    "label": "virtualbox",
    "timestamp": "20260604T203000Z",
    "hostname": "...", "os": "...", "kernel": "...",
    "allocated_vcpus": 4, "total_mem_mb": 8192,
    "capped": false,            // true only for the host run
    "repetitions": 7, "runner": "linux"
  },
  "metrics": [
    { "workload": "disk", "metric": "iops", "value": 41234.0,
      "unit": "IOPS", "params": { "bs": "4k", "pattern": "randread", "iodepth": 32 } }
  ]
}
```

Metrics are flat and self-describing so `analyze.py` can group by
`(workload, metric, params)` across machines without special-casing.

## Adding a hypervisor

No code change needed — it's just a new label. Allocate the same `vm_spec`,
install a Linux guest, run `./benchmark/run.sh --label <name>`, push. The
analysis picks it up automatically.

## Future work

- A real Windows memory-bandwidth bench (e.g. a small STREAM port) to close the
  one non-comparable workload.
- Optional plots from `analyze.py` (bar charts with error bars).
- Boot the host into the same Linux for a fully apples-to-apples baseline.
