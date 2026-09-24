#!/usr/bin/env bash
# Runs every tests/*.test.sh, reports per-suite pass/fail, exits nonzero if
# any suite failed.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
failed=0
total=0
failed_names=""

for t in "$DIR"/*.test.sh; do
  [ -f "$t" ] || continue
  total=$((total + 1))
  name="$(basename "$t")"
  echo "=== $name"
  set +e
  bash "$t"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "=== PASS $name"
  else
    echo "=== FAIL $name (exit $rc)"
    failed=$((failed + 1))
    failed_names="$failed_names $name"
  fi
  echo
done

echo "suites: $((total - failed)) passed, $failed failed (of $total)"
[ "$failed" -eq 0 ] || { echo "failed:$failed_names"; exit 1; }
