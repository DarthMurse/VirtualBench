#!/usr/bin/env bash
# net.sh — network benchmark via iperf3 (TCP throughput + retransmits) and ping (RTT).
# Requires an iperf3 server reachable at workloads.net.server. For real measurements
# this must be a SEPARATE physical box on the LAN running `iperf3 -s`. Gracefully
# skips (status recorded) when the server is unreachable.
#
# Usage: net.sh <result_file> <config_json>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/emit.sh
source "$HERE/../lib/emit.sh"

result_file="$1"; cfg="$2"
server="$(jq -r '.workloads.net.server'     "$cfg")"
dur="$(jq -r '.workloads.net.duration_s'    "$cfg")"
pings="$(jq -r '.workloads.net.ping_count'  "$cfg")"
params="{\"server\": \"$server\", \"duration_s\": $dur, \"proto\": \"tcp\"}"

if ! command -v iperf3 >/dev/null 2>&1; then
  vlog "net: iperf3 not found — skipping"
  emit_metric "$result_file" net throughput skipped Mbit/s "$params"
  emit_metric "$result_file" net retransmits skipped count "$params"
else
  vlog "net: iperf3 -c $server -t $dur"
  json="$(iperf3 -c "$server" -t "$dur" -J 2>/dev/null || true)"
  if [[ -n "$json" ]] && printf '%s' "$json" | jq -e '.end.sum_received' >/dev/null 2>&1; then
    bps="$(printf '%s' "$json" | jq -r '.end.sum_received.bits_per_second')"
    retr="$(printf '%s' "$json" | jq -r '.end.sum_sent.retransmits // 0')"
    mbps="$(awk -v b="$bps" 'BEGIN{printf "%.2f", b/1000000}')"
    emit_metric "$result_file" net throughput "$mbps" Mbit/s "$params"
    emit_metric "$result_file" net retransmits "$retr" count "$params"
    vlog "net: ${mbps} Mbit/s, ${retr} retransmits"
  else
    vlog "net: iperf3 server $server unreachable — skipping"
    emit_metric "$result_file" net throughput skipped Mbit/s "$params"
    emit_metric "$result_file" net retransmits skipped count "$params"
  fi
fi

# latency proxy via ping
pparams="{\"server\": \"$server\", \"count\": $pings}"
if command -v ping >/dev/null 2>&1; then
  vlog "net: ping -c $pings $server"
  # parse the "min/avg/max/..." summary line; field 2 = avg
  rtt="$(ping -c "$pings" -q "$server" 2>/dev/null \
        | awk -F'/' '/min\/avg\/max/ {print $5; exit}')"
  if [[ -n "${rtt:-}" ]]; then
    emit_metric "$result_file" net rtt_avg "$rtt" ms "$pparams"
    vlog "net: rtt_avg ${rtt} ms"
  else
    emit_metric "$result_file" net rtt_avg skipped ms "$pparams"
  fi
else
  emit_metric "$result_file" net rtt_avg skipped ms "$pparams"
fi
