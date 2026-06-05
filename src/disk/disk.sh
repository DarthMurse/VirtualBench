#!/usr/bin/env bash
# disk.sh — disk I/O benchmark via fio. Sweeps block sizes x access patterns and
# reports IOPS, bandwidth (KiB/s) and average latency (us) for each combination.
#
# Usage: disk.sh <result_file> <config_json>
# Honors env VBENCH_DISK_DIR to choose the test directory (default ./fio_testdir).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/emit.sh
source "$HERE/../lib/emit.sh"

result_file="$1"; cfg="$2"
testdir="${VBENCH_DISK_DIR:-./fio_testdir}"

sizes="$(jq -r '.workloads.disk.sizes[]'    "$cfg")"
patterns="$(jq -r '.workloads.disk.patterns[]' "$cfg")"
iodepth="$(jq -r '.workloads.disk.iodepth'   "$cfg")"
runtime="$(jq -r '.workloads.disk.runtime_s' "$cfg")"
filesize="$(jq -r '.workloads.disk.file_size' "$cfg")"

emit_skip() {
  local bs="$1" pat="$2" p="{\"bs\": \"$bs\", \"pattern\": \"$pat\", \"iodepth\": $iodepth}"
  emit_metric "$result_file" disk iops        skipped IOPS  "$p"
  emit_metric "$result_file" disk bandwidth   skipped KiB/s "$p"
  emit_metric "$result_file" disk latency_avg skipped us    "$p"
}

if ! command -v fio >/dev/null 2>&1; then
  vlog "disk: fio not found — skipping"
  for bs in $sizes; do for pat in $patterns; do emit_skip "$bs" "$pat"; done; done
  exit 0
fi

mkdir -p "$testdir"
trap 'rm -rf "$testdir"' EXIT

for bs in $sizes; do
  for pat in $patterns; do
    params="{\"bs\": \"$bs\", \"pattern\": \"$pat\", \"iodepth\": $iodepth}"
    vlog "disk: fio rw=$pat bs=$bs iodepth=$iodepth"
    json="$(fio --name=vbench --directory="$testdir" --rw="$pat" --bs="$bs" \
                --iodepth="$iodepth" --size="$filesize" --runtime="$runtime" --time_based \
                --ioengine=libaio --direct=1 --group_reporting --output-format=json 2>/dev/null || true)"
    if [[ -z "$json" ]]; then
      vlog "disk: fio produced no output for $pat/$bs — skipping"
      emit_skip "$bs" "$pat"; continue
    fi
    # reads report under .read, writes under .write; pick whichever did work.
    read -r iops bw lat_ns < <(printf '%s' "$json" | jq -r '
      .jobs[0] as $j
      | (if $j.read.iops  > 0 then $j.read  else $j.write end) as $d
      | "\($d.iops) \($d.bw) \($d.lat_ns.mean)"')
    lat_us="$(awk -v n="$lat_ns" 'BEGIN{printf "%.2f", n/1000}')"
    emit_metric "$result_file" disk iops        "$iops"   IOPS  "$params"
    emit_metric "$result_file" disk bandwidth   "$bw"     KiB/s "$params"
    emit_metric "$result_file" disk latency_avg "$lat_us" us    "$params"
    vlog "disk: $pat/$bs -> ${iops} IOPS, ${bw} KiB/s, ${lat_us} us"
  done
done
