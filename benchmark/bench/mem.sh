#!/usr/bin/env bash
# Memory workload: sysbench memory throughput (read + write passes).
# Args: <result_file> <vcpus>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/emit.sh"

result_file="$1"; vcpus="$2"
require_tool sysbench || { echo "install sysbench"; exit 1; }

run_pass() {
  local op="$1"
  # 1 GiB total transfer per thread, 1MiB block; report MiB/sec.
  local out
  out="$(sysbench memory --memory-oper="$op" --memory-block-size=1M \
         --memory-total-size=4G --threads="$vcpus" run 2>/dev/null)"
  echo "$out" | awk -F'[()]' '/transferred/ {print $2}' | awk '{print $1}'
}

for op in read write; do
  mibs="$(run_pass "$op")"
  [ -n "${mibs:-}" ] || { echo "sysbench mem parse failed ($op)" >&2; exit 1; }
  emit_metric "$result_file" mem "sysbench_${op}_MiBps" "$mibs" "MiB/s" \
    "$(jq -n --argjson t "$vcpus" '{threads:$t, block:"1M"}')"
  echo "mem $op: ${mibs} MiB/s"
done
