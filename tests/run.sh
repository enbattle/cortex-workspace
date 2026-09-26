#!/usr/bin/env bash
# Runs the test suites, then reports each suite's output in order, per-suite
# pass/fail, and exits nonzero if any suite failed.
#
# Usage: tests/run.sh [--parallel] [suite ...]
#   --parallel runs the suites side by side. CI uses it (multi-core Linux). It
#   is off by default because on Windows the suites compete for process
#   creation: a parallel full run there was not faster than sequential.
#   With no arguments, every tests/*.test.sh runs. Name suites (for example
#   `tests/run.sh ci-gates tests-locked`) to run only those while iterating;
#   run the full set before opening a pull request. CI always runs the full
#   set.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

parallel=0
if [ "${1:-}" = --parallel ]; then
  parallel=1
  shift
fi

suites=()
if [ "$#" -eq 0 ]; then
  for t in "$DIR"/*.test.sh; do
    [ -f "$t" ] && suites+=("$t")
  done
else
  for name in "$@"; do
    t="$DIR/${name%.test.sh}.test.sh"
    if [ ! -f "$t" ]; then
      echo "no such suite: $name" >&2
      exit 2
    fi
    suites+=("$t")
  done
fi

logs="$(mktemp -d)"
trap 'rm -rf "$logs"' EXIT

# Each suite isolates itself in its own temporary directory, so they can run
# side by side; then the wall time is that of the longest suite.
pids=()
for t in "${suites[@]}"; do
  if [ "$parallel" -eq 1 ]; then
    bash "$t" > "$logs/$(basename "$t").log" 2>&1 &
    pids+=("$!")
  else
    set +e
    bash "$t" > "$logs/$(basename "$t").log" 2>&1
    echo "$?" > "$logs/$(basename "$t").rc"
    set -e
    pids+=("")
  fi
done

failed=0
failed_names=""
for i in "${!suites[@]}"; do
  name="$(basename "${suites[$i]}")"
  if [ -n "${pids[$i]}" ]; then
    set +e
    wait "${pids[$i]}"
    rc=$?
    set -e
  else
    rc="$(cat "$logs/$name.rc")"
  fi
  echo "=== $name"
  cat "$logs/$name.log"
  if [ "$rc" -eq 0 ]; then
    echo "=== PASS $name"
  else
    echo "=== FAIL $name (exit $rc)"
    failed=$((failed + 1))
    failed_names="$failed_names $name"
  fi
  echo
done

total="${#suites[@]}"
echo "suites: $((total - failed)) passed, $failed failed (of $total)"
[ "$failed" -eq 0 ] || { echo "failed:$failed_names"; exit 1; }
