#!/usr/bin/env bash
# Tests for scripts/cortex/gates.sh (spec Amendment 1, A4; acceptance
# criterion 12). gates.sh runs tests-locked, BUILD_CMD, TEST_CMD, LINT_CMD and
# check.sh, every one of them even after a failure.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

GATE_NAMES="tests-locked build test lint check"

commit_all() { # dir msg
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}

# gated_repo -> a filled install (check: ok; BUILD/TEST/LINT_CMD=true,
# TEST_GLOBS=*.test.sh) with tests/a.test.sh locked in changes/x/tasks.md
gated_repo() {
  local d sha
  d="$(filled_install Zqxproj)" || return 1
  mkdir -p "$d/tests"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  commit_all "$d" "lock tests"
  sha="$(git -C "$d" rev-parse HEAD)"
  mkdir -p "$d/changes/x"
  cat > "$d/changes/x/tasks.md" <<EOF
# Tasks

Tests-locked-at: $sha

## Locked tests

- tests/a.test.sh
EOF
  commit_all "$d" "tasks"
  printf '%s\n' "$d"
}

gates() { # dir [change-folder...] -> run installed gates.sh from the repo root
  local d="$1"; shift
  run bash -c 'd="$1"; shift; cd "$d" && ./scripts/cortex/gates.sh "$@"' _ "$d" "$@"
}

# line number of the first exact line, or empty
line_no() { grep -nxF -- "$2" <<<"$1" | sed -n '1s/:.*//p' || true; }

# expect_order OUT : the five gate lines appear, each once, in the spec order
expect_order() {
  local prev=0 n g ln
  for g in $GATE_NAMES; do
    n=$(grep -cE "^gate $g: (ok|FAIL)" <<<"$1" || true)
    assert_true "gate $g reported exactly once" test "$n" = 1
    ln="$(grep -nE "^gate $g: (ok|FAIL)" <<<"$1" | sed -n '1s/:.*//p' || true)"
    if [ -n "$ln" ] && [ "$ln" -gt "$prev" ]; then pass; prev="$ln"
    else fail "gate $g out of order"; show_output; fi
  done
}

case_installed_executable() {
  local d; d="$(fresh_install)"
  assert_file_exists "$ROOT/template/scripts/cortex/gates.sh" "template ships gates.sh"
  assert_true "installed gates.sh is executable" test -x "$d/scripts/cortex/gates.sh"
}

case_usage_error() {
  local d; d="$(gated_repo)"
  gates "$d"
  assert_exit 2 "$CODE" "no argument is a usage error (exit 2)"
  assert_not_contains "$OUT" "gate " "no gates run on a usage error"
}

case_all_pass() {
  local d g; d="$(gated_repo)"
  # guard: the fixture's own pieces pass on their own
  run bash -c 'cd "$1" && ./scripts/cortex/check.sh' _ "$d"
  assert_exit 0 "$CODE" "fixture: check.sh passes"
  run bash -c 'cd "$1" && ./scripts/cortex/tests-locked.sh changes/x' _ "$d"
  assert_exit 0 "$CODE" "fixture: tests-locked.sh passes"
  gates "$d" changes/x
  assert_exit 0 "$CODE" "all gates pass -> exit 0"
  for g in $GATE_NAMES; do
    assert_line "$OUT" "gate $g: ok" "gate $g: ok"
  done
  expect_order "$OUT"
  assert_line "$OUT" "gates: ok" "final line gates: ok"
  assert_true "gates: ok is the last line" test "$(printf '%s\n' "$OUT" | sed -n '$p')" = "gates: ok"
  assert_not_contains "$OUT" "FAIL" "no FAIL lines"
}

case_failing_test_runs_the_rest() {
  local d; d="$(gated_repo)"
  set_config "$d/.cortex/config" TEST_CMD "false"
  gates "$d" changes/x
  assert_exit 1 "$CODE" "a failing gate -> exit 1"
  assert_line "$OUT" "gate tests-locked: ok" "tests-locked ok"
  assert_line "$OUT" "gate build: ok" "build ok"
  assert_line "$OUT" "gate test: FAIL (exit 1)" "failing TEST_CMD reported with its exit code"
  assert_line "$OUT" "gate lint: ok" "lint still runs after the failure"
  assert_line "$OUT" "gate check: ok" "check still runs after the failure"
  expect_order "$OUT"
  assert_line "$OUT" "gates: 1 failed" "final line counts 1 failure"
  assert_not_contains "$OUT" "gates: ok" "does not claim ok"
}

case_failing_build_runs_the_rest() {
  local d; d="$(gated_repo)"
  set_config "$d/.cortex/config" BUILD_CMD "exit 4"
  set_config "$d/.cortex/config" LINT_CMD "false"
  gates "$d" changes/x
  assert_exit 1 "$CODE" "failing gates -> exit 1"
  assert_line "$OUT" "gate build: FAIL (exit 4)" "exit code of the failing build"
  assert_line "$OUT" "gate test: ok" "test runs after a failed build"
  assert_line "$OUT" "gate lint: FAIL (exit 1)" "lint failure reported"
  assert_line "$OUT" "gate check: ok" "check runs last"
  assert_line "$OUT" "gates: 2 failed" "two failures counted"
}

case_failing_output_shown_above() {
  local d m f; d="$(gated_repo)"
  set_config "$d/.cortex/config" TEST_CMD "echo boom-marker-out; echo boom-marker-err >&2; exit 3"
  gates "$d" changes/x
  assert_exit 1 "$CODE" "failing gate -> exit 1"
  assert_line "$OUT" "gate test: FAIL (exit 3)" "failing step reported"
  assert_contains "$OUT$ERR" "boom-marker-out" "failing step's stdout is printed"
  assert_contains "$OUT$ERR" "boom-marker-err" "failing step's stderr is printed"
  m="$(grep -n 'boom-marker-out' <<<"$OUT" | sed -n '1s/:.*//p' || true)"
  f="$(line_no "$OUT" "gate test: FAIL (exit 3)")"
  if [ -n "$m" ] && [ -n "$f" ] && [ "$m" -lt "$f" ]; then pass
  else fail "failing step's output appears above its gate line"; show_output; fi
}

case_unset_lint() {
  local d; d="$(gated_repo)"
  set_config "$d/.cortex/config" LINT_CMD "<lint command>"
  gates "$d" changes/x
  assert_exit 1 "$CODE" "unset LINT_CMD -> exit 1"
  assert_line "$OUT" "gate lint: FAIL (not set in .cortex/config)" "unset command fails as not set"
  assert_line "$OUT" "gate test: ok" "other commands still run"
  # check.sh itself also fails C11 for the unset key (A2)
  assert_line "$OUT" "gate check: FAIL (exit 1)" "check gate fails on the unset key (C11)"
  assert_contains "$OUT" "FAIL [C11] .cortex/config: LINT_CMD is not set" "check's output shown above its gate line"
  assert_line "$OUT" "gates: 2 failed" "lint + check counted"
}

case_empty_build() {
  local d; d="$(gated_repo)"
  set_config "$d/.cortex/config" BUILD_CMD ""
  gates "$d" changes/x
  assert_exit 1 "$CODE" "empty BUILD_CMD -> exit 1"
  assert_line "$OUT" "gate build: FAIL (not set in .cortex/config)" "empty command fails as not set"
}

case_broken_lock() {
  local d; d="$(gated_repo)"
  printf 'echo weakened\n' > "$d/tests/a.test.sh"
  gates "$d" changes/x
  assert_exit 1 "$CODE" "broken lock -> exit 1"
  assert_line "$OUT" "gate tests-locked: FAIL (exit 1)" "tests-locked gate fails"
  assert_contains "$OUT$ERR" "LOCK modified: tests/a.test.sh" "tests-locked output is shown"
  assert_line "$OUT" "gate build: ok" "build runs after a failed lock"
  assert_line "$OUT" "gate check: ok" "check runs after a failed lock"
  assert_line "$OUT" "gates: 1 failed" "one failure counted"
}

case_commands_run_from_repo_root() {
  local d; d="$(gated_repo)"
  set_config "$d/.cortex/config" BUILD_CMD "test -f AGENTS.md && test -d .cortex"
  gates "$d" changes/x
  assert_line "$OUT" "gate build: ok" "commands run with cwd = repo root"
}

case_config_not_sourced() {
  local d; d="$(gated_repo)"
  append "$d/.cortex/config" 'ZZ_SOURCED=$(touch sourced-marker)'
  append "$d/.cortex/config" 'touch sourced-marker-2'
  gates "$d" changes/x
  assert_file_absent "$d/sourced-marker" "config is parsed, never sourced"
  assert_file_absent "$d/sourced-marker-2" "config lines are never executed"
}

run_case "gates.sh shipped and installed executable" case_installed_executable
run_case "usage error -> exit 2" case_usage_error
run_case "all gates pass -> gates: ok" case_all_pass
run_case "failing TEST_CMD: later gates still run" case_failing_test_runs_the_rest
run_case "failing BUILD_CMD + LINT_CMD counted" case_failing_build_runs_the_rest
run_case "failing step's output shown above its line" case_failing_output_shown_above
run_case "unset LINT_CMD fails as not set" case_unset_lint
run_case "empty BUILD_CMD fails as not set" case_empty_build
run_case "broken lock fails gate tests-locked" case_broken_lock
run_case "commands run from the repo root" case_commands_run_from_repo_root
run_case "config is never sourced" case_config_not_sourced
summary
