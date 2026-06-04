#!/usr/bin/env bash
# Application-level workload: compress a fixed-size synthetic corpus with 7-Zip
# and time it. Cross-platform with the Windows runner. Catches interaction
# effects (CPU + memory + disk together) that micro-benchmarks miss.
# Args: <result_file> <vcpus>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/emit.sh"

result_file="$1"; vcpus="$2"
require_tool 7z || require_tool 7za || { echo "install p7zip-full"; exit 1; }
SEVENZ="$(command -v 7z || command -v 7za)"

workdir="$(mktemp -d)"; trap 'rm -rf "$workdir"' EXIT
# Deterministic, compressible-ish 1 GiB corpus from /dev/urandom + text mix.
dd if=/dev/urandom of="$workdir/blob.bin" bs=1M count=512 status=none
yes "the quick brown fox jumps over the lazy dog 0123456789" | head -c 512M > "$workdir/text.txt"

start="$(date +%s.%N)"
"$SEVENZ" a -mmt"$vcpus" -mx5 "$workdir/out.7z" "$workdir/blob.bin" "$workdir/text.txt" >/dev/null 2>&1
end="$(date +%s.%N)"

elapsed="$(echo "$end - $start" | bc)"
emit_metric "$result_file" app "7z_compress_time" "$elapsed" "s" \
  "$(jq -n --argjson t "$vcpus" '{threads:$t, level:5, corpus_mb:1024}')"
echo "app: 7z compress ${elapsed}s"
