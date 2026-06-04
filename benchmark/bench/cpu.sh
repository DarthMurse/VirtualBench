#!/usr/bin/env bash
# CPU workload: 7-Zip compression/decompression benchmark (MIPS).
# Cross-platform with the Windows runner so host vs guest line up.
# Args: <result_file> <vcpus>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/emit.sh"

result_file="$1"; vcpus="$2"
require_tool 7z || require_tool 7za || { echo "install p7zip-full"; exit 1; }
SEVENZ="$(command -v 7z || command -v 7za)"

# -mmt = thread count, pinned to the allocated vcpus for a fair compare.
out="$("$SEVENZ" b -mmt"$vcpus" 2>/dev/null || true)"

# The summary "Tot:" line reports combined MIPS in the last column.
total_mips="$(echo "$out" | awk '/^Tot:/ {print $NF}' | tail -1)"
[ -n "${total_mips:-}" ] || { echo "could not parse 7z output" >&2; exit 1; }

emit_metric "$result_file" cpu "7z_total_mips" "$total_mips" "MIPS" \
  "$(jq -n --argjson t "$vcpus" '{threads:$t}')"
echo "cpu: ${total_mips} MIPS (mmt=$vcpus)"
