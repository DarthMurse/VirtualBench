#!/usr/bin/env bash
#
# VirtualBench — Linux guest runner.
#
# Run this MANUALLY inside each Linux guest (VirtualBox VM, Hyper-V VM).
# It runs the workload suite, writes results to results/<label>/, and prints
# the git commands to commit + push that machine's results.
#
# Usage:
#   ./run.sh --label virtualbox          # one of: virtualbox | hyperv | <your label>
#   ./run.sh --label hyperv --reps 5
#
# Prereqs in guest: p7zip-full, sysbench, fio, iperf3, jq, bc.
#   sudo apt-get install -y p7zip-full sysbench fio iperf3 jq bc
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO_ROOT/config.json"
LABEL=""; REPS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --label) LABEL="$2"; shift 2;;
    --reps)  REPS="$2";  shift 2;;
    --config) CONFIG="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$LABEL" ] || { echo "ERROR: --label <name> is required (e.g. virtualbox, hyperv)" >&2; exit 2; }

command -v jq >/dev/null || { echo "install jq first"; exit 1; }
cfg="$(cat "$CONFIG")"
vcpus="$(echo "$cfg" | jq -r '.vm_spec.vcpus')"
reps="${REPS:-$(echo "$cfg" | jq -r '.run.repetitions')}"
warmup="$(echo "$cfg" | jq -r '.run.warmup_runs')"
results_dir="$REPO_ROOT/$(echo "$cfg" | jq -r '.run.results_dir')/$LABEL"
mkdir -p "$results_dir"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
result_file="$results_dir/result_${stamp}.json"

# --- metadata header: every result is self-describing ---
jq -n \
  --arg label "$LABEL" \
  --arg stamp "$stamp" \
  --arg host "$(hostname)" \
  --arg kernel "$(uname -sr)" \
  --arg os "$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")" \
  --argjson vcpus "$vcpus" \
  --argjson nproc "$(nproc)" \
  --argjson mem_mb "$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)" \
  --argjson reps "$reps" \
  '{meta:{label:$label, timestamp:$stamp, hostname:$host, os:$os, kernel:$kernel,
          allocated_vcpus:$vcpus, visible_nproc:$nproc, total_mem_mb:$mem_mb,
          repetitions:$reps, runner:"linux", capped:false}, metrics:[]}' \
  > "$result_file"

echo "=== VirtualBench :: $LABEL :: $stamp ==="
echo "vcpus=$vcpus reps=$reps warmup=$warmup -> $result_file"

run_enabled() { [ "$(echo "$cfg" | jq -r ".workloads.$1.enabled")" = "true" ]; }

# Warm-up rounds (discarded): JITs, page cache, CPU freq ramp.
for ((w=1; w<=warmup; w++)); do
  echo "--- warmup $w/$warmup (discarded) ---"
  run_enabled cpu && bash "$REPO_ROOT/benchmark/bench/cpu.sh" /dev/null "$vcpus" >/dev/null 2>&1 || true
done

# Measured repetitions. Interleaving across hypervisors is handled by you running
# each machine in rotation; within a machine we repeat back-to-back.
for ((r=1; r<=reps; r++)); do
  echo "--- rep $r/$reps ---"
  run_enabled cpu  && bash "$REPO_ROOT/benchmark/bench/cpu.sh"  "$result_file" "$vcpus"
  run_enabled mem  && bash "$REPO_ROOT/benchmark/bench/mem.sh"  "$result_file" "$vcpus"
  run_enabled disk && bash "$REPO_ROOT/benchmark/bench/disk.sh" "$result_file" "$cfg"
  run_enabled net  && bash "$REPO_ROOT/benchmark/bench/net.sh"  "$result_file" "$cfg"
  run_enabled app  && bash "$REPO_ROOT/benchmark/bench/app.sh"  "$result_file" "$vcpus"
done

echo
echo "=== DONE. Results: $result_file ==="
echo
echo "To save these results, run:"
echo "  cd \"$REPO_ROOT\""
echo "  git add \"results/$LABEL/\""
echo "  git commit -m \"results($LABEL): run $stamp\""
echo "  git push $(echo "$cfg" | jq -r '.git.remote') $(echo "$cfg" | jq -r '.git.branch')"
