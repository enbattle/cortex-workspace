#!/usr/bin/env bash
# Runs every gate a change must pass before review (R11), in order:
# the test lock, the build, test and lint commands from .cortex/config, and
# the harness check. Every gate runs even after one fails, so the output is
# the full picture; a failing gate's own output is printed above its line.
#
# The commands come from .cortex/config, the repository's own file: they are
# read by parsing (the file is never sourced) and run with `bash -c` from the
# repository root. Running them is the point of this script.
#
# Usage: scripts/cortex/gates.sh <change-folder>
# Exit:  0 all gates pass, 1 any gate failed, 2 usage error.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: scripts/cortex/gates.sh <change-folder>" >&2
  exit 2
fi
folder="$(cd "$1" 2>/dev/null && pwd || printf '%s' "$1")"
root="$(git rev-parse --show-toplevel)"
cd "$root"
here="$root/scripts/cortex"

config_get() { # KEY -> value, empty if unset or a <placeholder>
  [ -f .cortex/config ] || return 0
  local value
  value="$(tr -d '\r' < .cortex/config | awk -v k="$1" '
    /^[[:space:]]*#/ { next }
    { eq = index($0, "="); if (eq == 0) next
      key = substr($0, 1, eq - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key != k) next
      val = substr($0, eq + 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", val); print val; exit }')"
  case "$value" in "<"*">") value="" ;; esac
  printf '%s' "$value"
}

failed=0
out="$(mktemp)"
trap 'rm -f "$out"' EXIT

gate() { # name command... : run it, show its output if it fails
  local name="$1" code
  shift
  set +e
  "$@" >"$out" 2>&1
  code=$?
  set -e
  if [ "$code" -eq 0 ]; then
    echo "gate $name: ok"
  else
    cat "$out"
    echo "gate $name: FAIL (exit $code)"
    failed=$((failed + 1))
  fi
}

config_gate() { # name KEY
  local cmd
  cmd="$(config_get "$2")"
  if [ -z "$cmd" ]; then
    echo "gate $1: FAIL (not set in .cortex/config)"
    failed=$((failed + 1))
  else
    gate "$1" bash -c "$cmd"
  fi
}

gate tests-locked "$here/tests-locked.sh" "$folder"
config_gate build BUILD_CMD
config_gate test TEST_CMD
config_gate lint LINT_CMD
gate check "$here/check.sh" "$root"

if [ "$failed" -eq 0 ]; then
  echo "gates: ok"
else
  echo "gates: $failed failed"
  exit 1
fi
