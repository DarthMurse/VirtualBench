#!/usr/bin/env bash
# Disk workload: fio across block sizes x access patterns. This is the subsystem
# where hypervisor virtual-disk paths differ the most.
# Args: <result_file> <config_json>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/emit.sh"

result_file="$1"; cfg="$2"
require_tool fio || { echo "install fio"; exit 1; }
require_tool jq

iodepth="$(echo "$cfg"  | jq -r '.workloads.disk.iodepth')"
runtime="$(echo "$cfg"  | jq -r '.workloads.disk.runtime_s')"
fsize="$(echo "$cfg"    | jq -r '.workloads.disk.file_size')"
testdir="${VBENCH_DISK_DIR:-./fio_testdir}"
mkdir -p "$testdir"

mapfile -t sizes    < <(echo "$cfg" | jq -r '.workloads.disk.sizes[]')
mapfile -t patterns < <(echo "$cfg" | jq -r '.workloads.disk.patterns[]')

for bs in "${sizes[@]}"; do
  for pat in "${patterns[@]}"; do
    json="$(fio --name=vbench --directory="$testdir" --rw="$pat" --bs="$bs" \
                --iodepth="$iodepth" --size="$fsize" --runtime="$runtime" \
                --time_based --ioengine=libaio --direct=1 --group_reporting \
                --output-format=json 2>/dev/null)"
    # Pick the active side (read for *read, write for *write).
    side="read"; [[ "$pat" == *write* ]] && side="write"
    iops="$(echo "$json"   | jq ".jobs[0].${side}.iops")"
    bw_kbps="$(echo "$json" | jq ".jobs[0].${side}.bw")"          # KiB/s
    lat_us="$(echo "$json"  | jq ".jobs[0].${side}.lat_ns.mean / 1000")"
    p="$(jq -n --arg bs "$bs" --arg pat "$pat" --argjson qd "$iodepth" '{bs:$bs, pattern:$pat, iodepth:$qd}')"
    emit_metric "$result_file" disk "iops"        "$iops"    "IOPS"  "$p"
    emit_metric "$result_file" disk "bandwidth"   "$bw_kbps" "KiB/s" "$p"
    emit_metric "$result_file" disk "latency_avg" "$lat_us"  "us"    "$p"
    echo "disk $pat $bs: ${iops} IOPS, ${bw_kbps} KiB/s"
  done
done
rm -rf "$testdir"
