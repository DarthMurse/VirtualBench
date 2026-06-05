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

**Windows host:** install the three benchmark tools with `winget` (or download them and add
each to `PATH`):

```powershell
winget install --exact --id 7zip.7zip
winget install --exact --id fio.fio
winget install --exact --id ar51an.iPerf3
```

7-Zip does **not** add itself to `PATH`; append `C:\Program Files\7-Zip` to your User or
Machine `Path` (or copy `7z.exe` somewhere already on `PATH`). After installing, open a new
shell so the updated `PATH` is picked up, then verify: `7z`, `fio`, and `iperf3` all resolve.
Analysis uses Python 3 via `uv` (run it from WSL or any box with Python).

The runner records any missing tool as `skipped` rather than failing, so a partial toolset
still produces a valid result file.

## Run

```bash
# Linux guest
scripts/run_linux.sh --label virtualbox --config config.json
scripts/run_linux.sh --label hyperv     --config config.json
```

```powershell
# Windows host — run from an ELEVATED PowerShell, with a LOCAL working directory.
cd C:\
& 'C:\path\to\VirtualBench\scripts\run_windows.ps1' -Label host-baseline -Config 'C:\path\to\VirtualBench\config.json'
# or: scripts\run_windows.bat -Label host-baseline
```

```bash
# Aggregate (from WSL or any box with Python 3)
python3 analyze/analyze.py results
```

Edit `config.json` to set `vm_spec` (vcpus/memory_mb), `run` (repetitions/warmup), and the
per-workload parameters. `config.smoke.json` holds tiny values for a quick `make smoke` check.

### Windows runner notes

- **Run elevated.** Applying the Job-Object resource cap requires administrator rights; without
  it the cap is skipped and the result records `"capped": false`.
- **Use a local working directory.** 7-Zip's benchmark fails when the process current directory
  is a UNC path (e.g. a `\\wsl.localhost\...` checkout). The script pins its own cwd to a local
  drive, but launch it from a local path (`cd C:\`) to be safe. Disk/app I/O is written to a
  local scratch dir (`%TEMP%`) when the repo lives on a network/9p share, so the disk numbers
  reflect the host SSD rather than the share.
- **CPU cap method.** CPU is limited with a Job-Object *CPU-rate hard cap* (`vcpus / total
  cores`), **not** a core-affinity mask: benchmark tools (7-Zip, fio) pin their own threads and
  abort if affinity is externally restricted. The rate cap throttles total cycles for the same
  "fewer vCPUs" effect. Compare against the Linux runner with this difference in mind.
- **Memory bandwidth is `skipped`.** sysbench has no native Windows port and there is no built-in
  equivalent, so the `mem` metrics are recorded as `skipped`. For a real figure use a standalone
  tool such as Intel MLC (`mlc --max_bandwidth`, free) or AIDA64, and convert MB/s → MiB/s
  (÷1.048576) to compare with the Linux sysbench numbers.
- **Network needs a server.** The `net` workload connects to `workloads.net.server`. Run an
  `iperf3 -s` server **on a separate physical machine** on the LAN (open inbound TCP 5201 in the
  firewall) and set its IP in `config.json`. Without a reachable server, throughput/retransmits
  record `skipped` (RTT still works if the host answers ping).

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
