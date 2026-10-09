# shellcheck shell=bash
# The one parser for cortex/config (spec Amendment 6). Sourced, never run,
# by the scripts next to it; each sources the copy in its own directory, so a
# base-branch script run by ci-gates.sh uses the base-branch parser too.
# The config itself is parsed, never sourced: KEY=VALUE per line, # starts a
# comment line, key and value are trimmed, the first line with a key wins,
# and a value of the form <...> counts as unset.

# config_value KEY : config text on stdin -> KEY's value, or nothing if unset
config_value() {
  local value
  value="$(tr -d '\r' | awk -v k="$1" '
    /^[[:space:]]*#/ { next }
    { eq = index($0, "="); if (eq == 0) next
      key = substr($0, 1, eq - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key != k) next
      val = substr($0, eq + 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", val); print val; exit }')"
  case "$value" in "<"*">") value="" ;; esac
  printf '%s' "$value"
}
