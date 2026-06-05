# Virtual Bench
This is a repo for benchmarking the performance of different Virtual Machine softwares, given the same physical resources and the same OS.

# Task
Run several hardware benchmarks (cpu, memory, disk I/O, network, end-to-end workload, etc.) on Windows host, Virtual box Ubuntu VM, Hyper-V VM respectively, given the same hardware resources.

# File Structure
+ `README.md`: how to setup and run the program.
+ `scripts/`: bash or psl script for running the benchmarks
    + `run_linux.sh`: run the benchmark with specified tasks and hardware resources on Linux
    + `run_windows.ps1`: run the benchmark on the Windows host (Job-Object resource cap + JSON need PowerShell)
    + `run_windows.bat`: thin wrapper that forwards to `run_windows.ps1`
+ `src/`: the code for benchmarks (wrappers around standard tools: 7-Zip, sysbench, fio, iperf3)
    + `cpu`: code for CPU benchmark
    + `memory`: code for memory benchmark
    + `disk`: code for disk benchmark
    + `network`: code for network benchmark
    + `workload`: code for end-to-end workload
    + `lib`: shared helpers (`emit.sh` metric writer, `restrict.ps1` resource capper)
+ `analyze/analyze.py`: aggregate results into a median + CV comparison table
+ `config.json` / `config.smoke.json`: benchmark parameters (full / fast smoke test)
+ `Makefile`: task runner (deps / smoke / run / analyze — nothing to compile, standard tools are used)
+ `results/`: saved results (`results/<label>/result_<UTCstamp>.json`)

# Notices
1. Use `uv` to manage the Python environment. 
2. The current terminal environment is WSL2 inside windows 11.

