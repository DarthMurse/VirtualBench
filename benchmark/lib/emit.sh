#!/usr/bin/env bash
# Shared helpers for emitting normalized result records (Linux runner).
# Every metric is one JSON object appended to the run's "metrics" array via jq.
# Sourced by run.sh and the bench/*.sh scripts.

set -euo pipefail

# Append one metric object to the result file's .metrics array.
#   emit_metric <result_file> <workload> <metric> <value> <unit> [params_json]
emit_metric() {
  local file="$1" workload="$2" metric="$3" value="$4" unit="$5" params="${6:-{}}"
  local tmp
  tmp="$(mktemp)"
  jq --arg w "$workload" --arg m "$metric" --argjson v "$value" \
     --arg u "$unit" --argjson p "$params" \
     '.metrics += [{workload:$w, metric:$m, value:$v, unit:$u, params:$p}]' \
     "$file" > "$tmp" && mv "$tmp" "$file"
}

# Require a tool or fail loudly (so we never silently skip a workload).
require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "MISSING TOOL: $1 — install it before running" >&2; return 1; }
}
