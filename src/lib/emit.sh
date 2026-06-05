# shellcheck shell=bash
# emit.sh — append a self-describing metric object to a result file's .metrics[] array.
#
# Usage: emit_metric <result_file> <workload> <metric> <value> <unit> [params_json]
#   params_json defaults to "{}". value is written as a JSON number when numeric,
#   otherwise as a string (e.g. "skipped").

emit_metric() {
  local file="$1" workload="$2" metric="$3" value="$4" unit="$5" params="${6:-}"
  # default to an empty object; done separately because ${6:-{}} mis-parses the
  # brace default (bash appends a stray '}'), corrupting the JSON.
  [[ -n "$params" ]] || params='{}'
  local tmp
  tmp="$(mktemp)"
  jq \
    --arg w "$workload" --arg m "$metric" --arg u "$unit" \
    --argjson p "$params" --arg v "$value" \
    '.metrics += [{
        workload: $w, metric: $m,
        value: ($v | tonumber? // $v),
        unit: $u, params: $p
     }]' \
    "$file" > "$tmp" && mv "$tmp" "$file"
}

# log a message to stderr so it never pollutes captured stdout
vlog() { printf '[%s] %s\n' "${VBENCH_LABEL:-vbench}" "$*" >&2; }
