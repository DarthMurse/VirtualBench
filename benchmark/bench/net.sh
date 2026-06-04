#!/usr/bin/env bash
# Network workload: iperf3 throughput + a latency proxy against a SEPARATE
# physical box on the LAN (config.workloads.net.server running `iperf3 -s`).
# Measuring against the host itself would test loopback, not the virtual NIC.
# Args: <result_file> <config_json>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/emit.sh"

result_file="$1"; cfg="$2"
require_tool iperf3 || { echo "install iperf3"; exit 1; }

server="$(echo "$cfg"   | jq -r '.workloads.net.server')"
duration="$(echo "$cfg" | jq -r '.workloads.net.duration_s')"

if ! iperf3 -c "$server" -t 1 >/dev/null 2>&1; then
  echo "net: iperf3 server $server unreachable — start 'iperf3 -s' there. Skipping." >&2
  emit_metric "$result_file" net "status" 0 "skipped" "$(jq -n --arg s "$server" '{server:$s, reason:"unreachable"}')"
  exit 0
fi

# Throughput (TCP).
j="$(iperf3 -c "$server" -t "$duration" -J 2>/dev/null)"
mbps="$(echo "$j" | jq '.end.sum_received.bits_per_second / 1000000')"
retr="$(echo "$j" | jq '.end.sum_sent.retransmits // 0')"
p="$(jq -n --arg s "$server" --argjson d "$duration" '{server:$s, duration_s:$d, proto:"tcp"}')"
emit_metric "$result_file" net "throughput" "$mbps" "Mbit/s" "$p"
emit_metric "$result_file" net "retransmits" "$retr" "count" "$p"
echo "net: ${mbps} Mbit/s"

# Latency proxy: round-trip via ping (avg ms).
if command -v ping >/dev/null 2>&1; then
  rtt="$(ping -c 20 -q "$server" 2>/dev/null | awk -F'/' '/rtt|round-trip/ {print $5}')"
  [ -n "${rtt:-}" ] && emit_metric "$result_file" net "rtt_avg" "$rtt" "ms" "$p" && echo "net rtt: ${rtt} ms"
fi
