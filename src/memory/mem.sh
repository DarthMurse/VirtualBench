#!/usr/bin/env bash
# mem.sh — memory bandwidth benchmark via sysbench (read + write passes).
# Reports throughput in MiB/s for each direction.
#
# Usage: mem.sh <result_file> <vcpus> [block_size] [total_size]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/emit.sh
source "$HERE/../lib/emit.sh"

result_file="$1"; vcpus="$2"; block="${3:-1M}"; total="${4:-4G}"
params="{\"threads\": $vcpus, \"block\": \"$block\", \"total\": \"$total\"}"

if ! command -v sysbench >/dev/null 2>&1; then
  vlog "mem: sysbench not found — skipping"
  emit_metric "$result_file" mem sysbench_read_MiBps  skipped MiB/s "$params"
  emit_metric "$result_file" mem sysbench_write_MiBps skipped MiB/s "$params"
  exit 0
fi

run_one() {
  local oper="$1"
  # Example line: "1024.00 MiB transferred (5678.90 MiB/sec)"
  sysbench memory \
    --memory-oper="$oper" \
    --memory-block-size="$block" \
    --memory-total-size="$total" \
    --threads="$vcpus" run 2>/dev/null \
    | awk -F'[()]' '/MiB transferred/ {split($2,a," "); print a[1]; exit}'
}

for oper in read write; do
  vlog "mem: sysbench memory --memory-oper=$oper"
  val="$(run_one "$oper" || true)"
  metric="sysbench_${oper}_MiBps"
  if [[ -n "${val:-}" ]]; then
    emit_metric "$result_file" mem "$metric" "$val" MiB/s "$params"
    vlog "mem: $oper ${val} MiB/s"
  else
    emit_metric "$result_file" mem "$metric" skipped MiB/s "$params"
    vlog "mem: $oper could not parse — skipping"
  fi
done
