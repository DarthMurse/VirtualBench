#!/usr/bin/env bash
# app.sh — end-to-end workload: build a fixed corpus (half random, half text) and
# time a 7-Zip compression pass. Exercises CPU + memory + disk together, catching
# interaction effects the micro-benchmarks miss. Reports elapsed seconds.
#
# Usage: app.sh <result_file> <vcpus> [level] [corpus_mb]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/emit.sh
source "$HERE/../lib/emit.sh"

result_file="$1"; vcpus="$2"; level="${3:-5}"; corpus_mb="${4:-1024}"
params="{\"threads\": $vcpus, \"level\": $level, \"corpus_mb\": $corpus_mb}"

if ! command -v 7z >/dev/null 2>&1; then
  vlog "app: 7z not found — skipping"
  emit_metric "$result_file" app 7z_compress_time skipped s "$params"
  exit 0
fi

workdir="${VBENCH_APP_DIR:-./app_testdir}"
mkdir -p "$workdir"
trap 'rm -rf "$workdir"' EXIT

half=$(( corpus_mb / 2 ))
vlog "app: building ${corpus_mb} MiB corpus (${half} MiB random + ${half} MiB text)"
dd if=/dev/urandom of="$workdir/blob.bin" bs=1M count="$half" status=none
# `yes` is killed by SIGPIPE once `head` has read enough; that's expected, so swallow
# the resulting pipeline failure (pipefail + set -e would otherwise abort the run).
{ yes "the quick brown fox jumps over the lazy dog" | head -c "$(( half * 1024 * 1024 ))" > "$workdir/text.txt"; } || true

vlog "app: 7z a -mmt$vcpus -mx$level"
start="$(date +%s.%N)"
7z a -mmt"$vcpus" -mx"$level" "$workdir/out.7z" "$workdir/blob.bin" "$workdir/text.txt" >/dev/null 2>&1 || true
end="$(date +%s.%N)"
elapsed="$(awk -v s="$start" -v e="$end" 'BEGIN{printf "%.3f", e-s}')"

emit_metric "$result_file" app 7z_compress_time "$elapsed" s "$params"
vlog "app: ${elapsed} s"
