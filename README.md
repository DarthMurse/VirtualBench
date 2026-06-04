# VirtualBench

Benchmark and compare the performance of different **VM hypervisors** running the
same workloads on the same physical host and the same guest OS.

The independent variable is the **hypervisor**. Everything else — host hardware,
guest image, vCPU/RAM allocation, and the workload binaries — is held constant so
measured differences are attributable to the virtualization software alone.

First targets: **VirtualBox** and **Hyper-V**, with a **Linux guest**, plus an
optional **capped Windows host** baseline. There is no central orchestrator: you
run the benchmark **manually on each machine**, and each machine commits its own
results to git.

## How it works

```
1. Copy this repo onto a target machine.
2. Run the benchmark with a label:
     Linux guest :  ./benchmark/run.sh  --label virtualbox      (or hyperv)
     Windows host:  .\benchmark\run.ps1 -Label host-baseline    (auto-capped to VM specs)
3. Results land in   results/<label>/result_<UTCstamp>.json
4. The runner PRINTS the git commands — run them to publish that machine's results.
5. After every machine has pushed:
     python analyze/analyze.py results
```

The Windows host run caps itself (CPU affinity + memory) to the same `vm_spec` as
the VMs via a Windows Job Object, so the bare-metal baseline is a fair reference.

## Layout

```
config.json              # vm_spec (vcpus/mem), workload params, repetitions
benchmark/               # the self-contained payload — copied to each machine
  run.sh                 # Linux guest runner
  run.ps1                # Windows host runner (resource-capped baseline)
  restrict.ps1           # Job Object CPU+RAM cap used by run.ps1
  lib/emit.sh            # JSON result helpers
  bench/{cpu,mem,disk,net,app}.sh
analyze/analyze.py       # aggregate results across machines, compute overhead %
results/<label>/         # per-machine result JSON, committed to git
docs/DESIGN.md           # methodology, fairness rules, result schema
```

## Prerequisites

- **Linux guests:** `sudo apt-get install -y p7zip-full sysbench fio iperf3 jq bc`
- **Windows host:** `7z.exe`, `fio` (Windows build), `iperf3` (Windows build) on PATH; run PowerShell as admin.
- **Network workload:** a separate physical box on the LAN running `iperf3 -s`
  (set its IP in `config.json` → `workloads.net.server`).

See [docs/DESIGN.md](docs/DESIGN.md) for the full methodology, the
host-vs-guest comparability caveat, and the result schema.

> Status: scaffold. The runners and bench scripts are complete; you still need to
> create the VMs, install a Linux guest image, and (for fairness) the matching
> paravirtual guest tools on both hypervisors.
