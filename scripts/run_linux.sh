#!/usr/bin/env bash
# run_linux.sh — VirtualBench Linux runner (use inside the Ubuntu guests, or on a
# bare-metal Linux baseline). Reads config.json, runs warmup + measured repetitions
# of each enabled workload, and writes one self-describing JSON result file.
#
# Usage: scripts/run_linux.sh --label <name> [--reps N] [--config path]
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/src"

label=""; reps=""; config="$REPO/config.json"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)  label="$2";  shift 2 ;;
    --reps)   reps="$2";   shift 2 ;;
    --config) config="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$label" ]]   || { echo "error: --label is required" >&2; exit 2; }
[[ -f "$config" ]]  || { echo "error: config not found: $config" >&2; exit 2; }
command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 2; }

export VBENCH_LABEL="$label"

# --- read config -----------------------------------------------------------
vcpus="$(jq -r '.vm_spec.vcpus' "$config")"
[[ -n "$reps" ]] || reps="$(jq -r '.run.repetitions' "$config")"
warmup="$(jq -r '.run.warmup_runs' "$config")"
results_dir="$REPO/$(jq -r '.run.results_dir' "$config")"

en() { jq -r ".workloads.$1.enabled" "$config"; }

# --- prepare result file ---------------------------------------------------
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
outdir="$results_dir/$label"
mkdir -p "$outdir"
result_file="$outdir/result_${stamp}.json"

os_pretty="$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
total_mem_mb="$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)"

jq -n \
  --arg label "$label" --arg ts "$stamp" --arg host "$(hostname)" \
  --arg os "$os_pretty" --arg kernel "$(uname -sr)" \
  --argjson vcpus "$vcpus" --arg nproc "$(nproc)" \
  --argjson mem "$total_mem_mb" --argjson reps "$reps" \
  '{meta: {label:$label, timestamp:$ts, hostname:$host, os:$os, kernel:$kernel,
           allocated_vcpus:$vcpus, visible_nproc:($nproc|tonumber), total_mem_mb:$mem,
           repetitions:$reps, runner:"linux", capped:false},
    metrics: []}' > "$result_file"

echo "==> VirtualBench linux | label=$label vcpus=$vcpus reps=$reps warmup=$warmup"
echo "==> writing $result_file"

# --- workload dispatch -----------------------------------------------------
# $1 = scratch file to write into (discarded for warmup), used by all modules.
run_cpu()  { bash "$SRC/cpu/cpu.sh"  "$1" "$vcpus"; }
run_mem()  { bash "$SRC/memory/mem.sh" "$1" "$vcpus" \
               "$(jq -r '.workloads.mem.block_size' "$config")" \
               "$(jq -r '.workloads.mem.total_size' "$config")"; }
run_disk() { bash "$SRC/disk/disk.sh" "$1" "$config"; }
run_net()  { bash "$SRC/network/net.sh" "$1" "$config"; }
run_app()  { bash "$SRC/workload/app.sh" "$1" "$vcpus" \
               "$(jq -r '.workloads.app.level' "$config")" \
               "$(jq -r '.workloads.app.corpus_mb' "$config")"; }

run_all() {
  local target="$1"
  [[ "$(en cpu)"  == "true" ]] && run_cpu  "$target"
  [[ "$(en mem)"  == "true" ]] && run_mem  "$target"
  [[ "$(en disk)" == "true" ]] && run_disk "$target"
  [[ "$(en net)"  == "true" ]] && run_net  "$target"
  [[ "$(en app)"  == "true" ]] && run_app  "$target"
  return 0
}

# --- warmup (discarded) ----------------------------------------------------
scratch="$(mktemp)"
for ((w=1; w<=warmup; w++)); do
  echo "--- warmup $w/$warmup ---"
  echo '{"metrics":[]}' > "$scratch"
  run_all "$scratch"
done
rm -f "$scratch"

# --- measured repetitions --------------------------------------------------
for ((r=1; r<=reps; r++)); do
  echo "--- rep $r/$reps ---"
  run_all "$result_file"
done

echo "==> done. results in $result_file"
echo "==> analyze with: python3 analyze/analyze.py results"
