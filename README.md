# VirtualBench

Benchmark the performance overhead of **VirtualBox** and **Hyper-V** Ubuntu VMs against
a **Windows host** baseline, under identical hardware resources. Each target runs the same
five workloads with standard, cross-platform tools and emits a self-describing JSON result;
`analyze.py` aggregates them into a median + CV comparison table.

| Workload | Tool (Linux / Windows) | Metrics |
|----------|------------------------|---------|
| CPU      | `7z b` / `7z b`        | total rating (MIPS) |
| Memory   | `sysbench memory` / *(no Windows equivalent — skipped)* | read/write bandwidth (MiB/s) |
| Disk     | `fio` (libaio / windowsaio) | IOPS, bandwidth (KiB/s), avg latency (us) |
| Network  | `iperf3` + `ping`      | throughput (Mbit/s), retransmits, avg RTT (ms) |
| App (e2e)| `7z a` timed           | compression time (s) |

## ⚠️ Fairness caveat: VirtualBox and Hyper-V cannot both run natively at once

Enabling Hyper-V turns Windows into a hypervisor root partition, so the "host" is no longer
bare metal, and VirtualBox falls back to a slower nested backend. Measure across **two boot
configurations** and record which one each result came from:

| Boot config | `bcdedit /set hypervisorlaunchtype` | Measure |
|-------------|-------------------------------------|---------|
| A | `off` (reboot) | bare-metal Windows host baseline + **VirtualBox (native)** |
| B | `auto` (reboot) | **Hyper-V VM (native)** + optional VirtualBox-under-Hyper-V (coexistence penalty) |

Additional controls: identical vCPU/RAM on both VMs (disable dynamic memory/ballooning),
same virtual-disk type on the same SSD, Hyper-V Gen 2 + paravirtual drivers, record Guest
Additions / Integration Services versions, High Performance power plan, >=5 reps with warmup
discarded. The **network test needs a separate physical box** on the LAN running `iperf3 -s`
(set its IP in `config.json` -> `workloads.net.server`).

## Setup

**Linux (each Ubuntu guest, or a bare-metal Linux baseline):**
```bash
make deps          # apt-get install sysbench fio iperf3 p7zip-full jq bc   (needs sudo)
```

**Windows host:** install [7-Zip](https://www.7-zip.org/), [fio](https://github.com/axboe/fio),
and [iperf3](https://iperf.fr/) and put them on `PATH`. Python 3 (for analysis) via `uv`.

## Run

```bash
# Linux guest
scripts/run_linux.sh --label virtualbox --config config.json
scripts/run_linux.sh --label hyperv     --config config.json

# Windows host (PowerShell, elevated for the resource cap)
scripts\run_windows.ps1 -Label host-baseline -Config config.json
# or: scripts\run_windows.bat -Label host-baseline

# Aggregate
python3 analyze/analyze.py results
```

Edit `config.json` to set `vm_spec` (vcpus/memory_mb), `run` (repetitions/warmup), and the
per-workload parameters. `config.smoke.json` holds tiny values for a quick `make smoke` check.

## Layout

```
config.json / config.smoke.json   benchmark parameters
scripts/run_linux.sh              Linux runner (warmup + measured reps)
scripts/run_windows.ps1 (+ .bat)  Windows host runner (Job-Object resource cap)
src/{cpu,memory,disk,network,workload}/   per-workload modules
src/lib/emit.sh, src/lib/restrict.ps1     metric emitter / resource capper
analyze/analyze.py                median + CV + %-of-baseline aggregator
results/<label>/result_*.json     committed results
```
