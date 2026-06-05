#!/usr/bin/env bash
# cpu.sh — CPU benchmark via the 7-Zip internal benchmark (LZMA compress/decompress).
# Reports the total rating in MIPS. Cross-platform comparable with the Windows runner.
#
# Usage: cpu.sh <result_file> <vcpus>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/emit.sh
source "$HERE/../lib/emit.sh"

result_file="$1"; vcpus="$2"

if ! command -v 7z >/dev/null 2>&1; then
  vlog "cpu: 7z not found — skipping"
  emit_metric "$result_file" cpu 7z_total_mips skipped MIPS "{\"threads\": $vcpus}"
  exit 0
fi

vlog "cpu: 7z b -mmt$vcpus"
out="$(7z b -mmt"$vcpus" 2>/dev/null || true)"
# The summary line looks like:  "Tot:        4567   100   4567"  -> last column is total MIPS.
mips="$(printf '%s\n' "$out" | awk '/^Tot:/ {print $NF; exit}')"

if [[ -n "${mips:-}" ]]; then
  emit_metric "$result_file" cpu 7z_total_mips "$mips" MIPS "{\"threads\": $vcpus}"
  vlog "cpu: ${mips} MIPS"
else
  vlog "cpu: could not parse 7z output — skipping"
  emit_metric "$result_file" cpu 7z_total_mips skipped MIPS "{\"threads\": $vcpus}"
fi
