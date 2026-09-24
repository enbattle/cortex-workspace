#!/usr/bin/env bash
# Tests for scripts/cortex/gates.sh (spec Amendment 1, A4, and Amendment 2,
# B2/B3; acceptance criteria 12 and 17). gates.sh runs tests-locked, BUILD_CMD,
# TEST_CMD, LINT_CMD and check.sh, every one of them even after a failure.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

GATE_NAMES="tests-locked build test lint check"

commit_all() { # dir msg
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}

# gated_repo [KEY=VALUE...] -> a filled install (check: ok; BUILD/TEST/LINT_CMD
# =true, TEST_GLOBS=*.test.sh) with tests/a.test.sh locked in the Amendment 2
# layout: the tests are committed (T), then changes/x/lock.md naming T in its
# own commit (L). Each KEY=VALUE is set in .cortex/config BEFORE the lock,
# because the config is itself locked (B2): editing it afterwards would fail
# the tests-locked gate.
gated_repo() {
  local d sha kv
  d="$(filled_install Zqxproj)" || return 1
  for kv in "$@"; do
    case "$kv" in
      +*) append "$d/.cortex/config" "${kv#+}" ;;
      *) set_config "$d/.cortex/config" "${kv%%=*}" "${kv#*=}" ;;
    esac
  done
  mkdir -p "$d/tests" "$d/src"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  printf 'app\n' > "$d/src/app.txt"
  commit_all "$d" "add tests"
  sha="$(git -C "$d" rev-parse HEAD)"
  mkdir -p "$d/changes/x"
  cat > "$d/changes/x/lock.md" <<EOF2
Tests-locked-at: $sha

## Locked tests

- tests/a.test.sh
EOF2
  commit_all "$d" "lock tests"
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
  local d; d="$(gated_repo "TEST_CMD=false")"
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
  local d; d="$(gated_repo "BUILD_CMD=exit 4" "LINT_CMD=false")"
  gates "$d" changes/x
  assert_exit 1 "$CODE" "failing gates -> exit 1"
  assert_line "$OUT" "gate build: FAIL (exit 4)" "exit code of the failing build"
  assert_line "$OUT" "gate test: ok" "test runs after a failed build"
  assert_line "$OUT" "gate lint: FAIL (exit 1)" "lint failure reported"
  assert_line "$OUT" "gate check: ok" "check runs last"
  assert_line "$OUT" "gates: 2 failed" "two failures counted"
}

case_failing_output_shown_above() {
  local d m f
  d="$(gated_repo "TEST_CMD=echo boom-marker-out; echo boom-marker-err >&2; exit 3")"
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
  local d; d="$(gated_repo "LINT_CMD=<lint command>")"
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
  local d; d="$(gated_repo "BUILD_CMD=")"
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
  local d; d="$(gated_repo "BUILD_CMD=test -f AGENTS.md && test -d .cortex")"
  gates "$d" changes/x
  assert_line "$OUT" "gate build: ok" "commands run with cwd = repo root"
}

case_config_not_sourced() {
  local d
  d="$(gated_repo '+ZZ_SOURCED=$(touch sourced-marker)' '+touch sourced-marker-2')"
  assert_file_contains "$d/.cortex/config" 'ZZ_SOURCED=$(touch sourced-marker)' "fixture: plant is in the config"
  gates "$d" changes/x
  assert_file_absent "$d/sourced-marker" "config is parsed, never sourced"
  assert_file_absent "$d/sourced-marker-2" "config lines are never executed"
}

# ---- Amendment 2 --------------------------------------------------------------

case_config_edited_after_lock() {
  # B2: the gate commands are frozen for the change; weakening TEST_CMD after
  # the lock fails the tests-locked gate (the edited command still runs)
  local d; d="$(gated_repo)"
  set_config "$d/.cortex/config" TEST_CMD "true # weakened"
  gates "$d" changes/x
  assert_exit 1 "$CODE" "config edited after the lock -> exit 1"
  assert_line "$OUT" "gate tests-locked: FAIL (exit 1)" "tests-locked gate fails"
  assert_contains "$OUT$ERR" "LOCK modified: .cortex/config" "the config edit is named"
  assert_line "$OUT" "gate test: ok" "later gates still run"
  assert_line "$OUT" "gates: 1 failed" "one failure counted"
}

case_no_exec_bit() {
  # AC17 (B3): gates.sh invokes the other scripts through bash, so a lost
  # executable bit (e.g. a Windows commit with core.filemode=false) is harmless.
  # (On filesystems without exec bits chmod is a no-op and this still passes.)
  local d g; d="$(gated_repo)"
  chmod -x "$d"/scripts/cortex/*.sh
  run bash -c 'cd "$1" && bash scripts/cortex/gates.sh changes/x' _ "$d"
  assert_exit 0 "$CODE" "gates pass with non-executable scripts"
  for g in $GATE_NAMES; do
    assert_line "$OUT" "gate $g: ok" "gate $g: ok without exec bits"
  done
  assert_line "$OUT" "gates: ok" "gates: ok without exec bits"
  assert_not_contains "$OUT$ERR" "Permission denied" "no permission errors"
}

case_from_subdir_relative() {
  # AC17: run from a subdirectory with a relative change-folder path
  local d g
  d="$(gated_repo "BUILD_CMD=test -f AGENTS.md && test -d .cortex")"
  run bash -c 'cd "$1/src" && ../scripts/cortex/gates.sh ../changes/x' _ "$d"
  assert_exit 0 "$CODE" "gates pass from a subdirectory"
  for g in $GATE_NAMES; do
    assert_line "$OUT" "gate $g: ok" "gate $g: ok from a subdirectory"
  done
  assert_line "$OUT" "gates: ok" "gates: ok from a subdirectory"
}

case_from_subdir_relative_broken_lock() {
  # the relative folder really is the one checked: a broken lock still fails
  local d; d="$(gated_repo)"
  printf 'echo weakened\n' > "$d/tests/a.test.sh"
  run bash -c 'cd "$1/src" && bash ../scripts/cortex/gates.sh ../changes/x' _ "$d"
  assert_exit 1 "$CODE" "broken lock from a subdirectory -> exit 1"
  assert_line "$OUT" "gate tests-locked: FAIL (exit 1)" "tests-locked fails from a subdirectory"
  assert_contains "$OUT$ERR" "LOCK modified: tests/a.test.sh" "the modified test is named"
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
run_case "B2 config edited after the lock fails tests-locked" case_config_edited_after_lock
run_case "AC17 scripts without exec bit still work" case_no_exec_bit
run_case "AC17 from a subdirectory, relative folder" case_from_subdir_relative
run_case "AC17 subdirectory + relative folder, broken lock" case_from_subdir_relative_broken_lock
summary
