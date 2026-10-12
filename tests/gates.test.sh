#!/usr/bin/env bash
# Tests for cortex/bin/gates.sh (spec Amendment 1, A4, and Amendment 2,
# B2/B3; acceptance criteria 12 and 17). gates.sh runs tests-locked, tasks,
# BUILD_CMD, TEST_CMD, LINT_CMD and check.sh, every one of them even after a
# failure. The tasks gate is spec 3.1.0's G3
# (docs/specs/2026-10-09-v3.1-pilot-followups.md, criteria 8 and 9).
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

# spec 3.1.0 G3, criterion 9: the tasks gate runs after tests-locked, before
# build (was: "tests-locked build test lint check")
GATE_NAMES="tests-locked tasks build test lint check"

# A tasks.md whose every task is ticked: the tasks gate passes on it (G3)
TICKED_TASKS='# Tasks: x\n\n- [x] the change -- done when: its test passes\n'

# gated_repo [KEY=VALUE...] -> a filled install (check: ok; BUILD/TEST/LINT_CMD
# =true, TEST_GLOBS=*.test.sh) with tests/a.test.sh locked in the Amendment 2
# layout: the tests are committed (T), then cortex/changes/x/lock.md naming T in its
# own commit (L). Each KEY=VALUE is set in cortex/config BEFORE the lock,
# because the config is itself locked (B2): editing it afterwards would fail
# the tests-locked gate.
gated_repo() {
  local d kv
  d="$(filled_install)" || return 1
  for kv in "$@"; do
    case "$kv" in
      +*) append "$d/cortex/config" "${kv#+}" ;;
      *) set_config "$d/cortex/config" "${kv%%=*}" "${kv#*=}" ;;
    esac
  done
  lock_a "$d"
  printf '%s\n' "$d"
}

# lock_a DIR : add tests/a.test.sh, src/app.txt and cortex/changes/x/tasks.md
# (every task ticked: spec 3.1.0 G3 fails a missing tasks.md), and lock
# cortex/changes/x on them
lock_a() {
  mkdir -p "$1/tests" "$1/src" "$1/cortex/changes/x"
  printf 'echo a\n' > "$1/tests/a.test.sh"
  printf 'app\n' > "$1/src/app.txt"
  printf '%b' "$TICKED_TASKS" > "$1/cortex/changes/x/tasks.md"
  lock_tests "$1" cortex/changes/x tests/a.test.sh
}

# write_tasks DIR TEXT : cortex/changes/x/tasks.md is TEXT (printf %b)
write_tasks() { printf '%b' "$2" > "$1/cortex/changes/x/tasks.md"; }

gates() { # dir [change-folder...] -> run installed gates.sh from the repo root
  local d="$1"; shift
  run bash -c 'd="$1"; shift; cd "$d" && ./cortex/bin/gates.sh "$@"' _ "$d" "$@"
}

# line number of the first exact line, or empty
line_no() { grep -nxF -- "$2" <<<"$1" | sed -n '1s/:.*//p' || true; }

# expect_order OUT : the six gate lines appear, each once, in the spec order
# (spec 3.1.0 G3: was five, without tasks)
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
  assert_file_exists "$ROOT/template/cortex/bin/gates.sh" "template ships gates.sh"
  assert_true "installed gates.sh is executable" test -x "$d/cortex/bin/gates.sh"
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
  run bash -c 'cd "$1" && ./cortex/bin/check.sh' _ "$d"
  assert_exit 0 "$CODE" "fixture: check.sh passes"
  run bash -c 'cd "$1" && ./cortex/bin/tests-locked.sh cortex/changes/x' _ "$d"
  assert_exit 0 "$CODE" "fixture: tests-locked.sh passes"
  gates "$d" cortex/changes/x
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
  gates "$d" cortex/changes/x
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
  gates "$d" cortex/changes/x
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
  gates "$d" cortex/changes/x
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
  gates "$d" cortex/changes/x
  assert_exit 1 "$CODE" "unset LINT_CMD -> exit 1"
  assert_line "$OUT" "gate lint: FAIL (not set in cortex/config)" "unset command fails as not set"
  assert_line "$OUT" "gate test: ok" "other commands still run"
  # check.sh itself also fails C11 for the unset key (A2)
  assert_line "$OUT" "gate check: FAIL (exit 1)" "check gate fails on the unset key (C11)"
  assert_contains "$OUT" "FAIL [C11] cortex/config: LINT_CMD is not set" "check's output shown above its gate line"
  assert_line "$OUT" "gates: 2 failed" "lint + check counted"
}

case_empty_build() {
  local d; d="$(gated_repo "BUILD_CMD=")"
  gates "$d" cortex/changes/x
  assert_exit 1 "$CODE" "empty BUILD_CMD -> exit 1"
  assert_line "$OUT" "gate build: FAIL (not set in cortex/config)" "empty command fails as not set"
}

case_broken_lock() {
  local d; d="$(gated_repo)"
  printf 'echo weakened\n' > "$d/tests/a.test.sh"
  gates "$d" cortex/changes/x
  assert_exit 1 "$CODE" "broken lock -> exit 1"
  assert_line "$OUT" "gate tests-locked: FAIL (exit 1)" "tests-locked gate fails"
  assert_contains "$OUT$ERR" "LOCK modified: tests/a.test.sh" "tests-locked output is shown"
  assert_line "$OUT" "gate build: ok" "build runs after a failed lock"
  assert_line "$OUT" "gate check: ok" "check runs after a failed lock"
  assert_line "$OUT" "gates: 1 failed" "one failure counted"
}

case_commands_run_from_repo_root() {
  local d; d="$(gated_repo "BUILD_CMD=test -f AGENTS.md && test -d cortex")"
  gates "$d" cortex/changes/x
  assert_line "$OUT" "gate build: ok" "commands run with cwd = repo root"
}

case_config_not_sourced() {
  local d
  d="$(gated_repo '+ZZ_SOURCED=$(touch sourced-marker)' '+touch sourced-marker-2')"
  assert_file_contains "$d/cortex/config" 'ZZ_SOURCED=$(touch sourced-marker)' "fixture: plant is in the config"
  gates "$d" cortex/changes/x
  assert_file_absent "$d/sourced-marker" "config is parsed, never sourced"
  assert_file_absent "$d/sourced-marker-2" "config lines are never executed"
}

# ---- Amendment 2 --------------------------------------------------------------

case_config_edited_after_lock() {
  # B2: the gate commands are frozen for the change; weakening TEST_CMD after
  # the lock fails the tests-locked gate (the edited command still runs)
  local d; d="$(gated_repo)"
  set_config "$d/cortex/config" TEST_CMD "true # weakened"
  gates "$d" cortex/changes/x
  assert_exit 1 "$CODE" "config edited after the lock -> exit 1"
  assert_line "$OUT" "gate tests-locked: FAIL (exit 1)" "tests-locked gate fails"
  assert_contains "$OUT$ERR" "LOCK modified: cortex/config" "the config edit is named"
  assert_line "$OUT" "gate test: ok" "later gates still run"
  assert_line "$OUT" "gates: 1 failed" "one failure counted"
}

case_no_exec_bit() {
  # AC17 (B3): gates.sh invokes the other scripts through bash, so a lost
  # executable bit (e.g. a Windows commit with core.filemode=false) is harmless.
  # (On filesystems without exec bits chmod is a no-op and this still passes.)
  local d g; d="$(gated_repo)"
  chmod -x "$d"/cortex/bin/*.sh
  run bash -c 'cd "$1" && bash cortex/bin/gates.sh cortex/changes/x' _ "$d"
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
  d="$(gated_repo "BUILD_CMD=test -f AGENTS.md && test -d cortex")"
  run bash -c 'cd "$1/src" && ../cortex/bin/gates.sh ../cortex/changes/x' _ "$d"
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
  run bash -c 'cd "$1/src" && bash ../cortex/bin/gates.sh ../cortex/changes/x' _ "$d"
  assert_exit 1 "$CODE" "broken lock from a subdirectory -> exit 1"
  assert_line "$OUT" "gate tests-locked: FAIL (exit 1)" "tests-locked fails from a subdirectory"
  assert_contains "$OUT$ERR" "LOCK modified: tests/a.test.sh" "the modified test is named"
}

# ---- AC32/AC34 (Amendment 6, F1/F2): one config parser --------------------------

# variant_gated_repo KIND -> like gated_repo, with BUILD_CMD written per KIND
# (set before the lock, since the config is locked)
variant_gated_repo() {
  local d
  d="$(filled_install)" || return 1
  config_variant "$d/cortex/config" "$1" BUILD_CMD \
    "touch build-real-ran" "touch build-other-ran; exit 7" || return 1
  lock_a "$d"
  printf '%s\n' "$d"
}

ac32_gates() { # KIND : BUILD_CMD parsed per the format section
  local kind="$1" d; d="$(variant_gated_repo "$kind")"
  gates "$d" cortex/changes/x
  assert_exit 0 "$CODE" "$kind: gates pass"
  assert_line "$OUT" "gate build: ok" "$kind: the real BUILD_CMD runs and passes"
  assert_file_exists "$d/build-real-ran" "$kind: the real BUILD_CMD ran"
  assert_file_absent "$d/build-other-ran" "$kind: the other value never ran"
  assert_line "$OUT" "gates: ok" "$kind: gates: ok"
}

case_AC32_spaced() { ac32_gates spaced; }
case_AC32_comment() { ac32_gates comment; }
case_AC32_no_equals() { ac32_gates no-equals; }
case_AC32_twice() { ac32_gates twice; }

case_AC34_stub_parser() {
  local d g; d="$(gated_repo)"
  write_stub_parser "$d"
  gates "$d" cortex/changes/x
  assert_exit 1 "$CODE" "a parser that prints nothing -> exit 1"
  for g in build test lint; do
    assert_line "$OUT" "gate $g: FAIL (not set in cortex/config)" "gates.sh reads $g's command through _config.sh"
  done
}

# ---- spec 3.1.0 G3 (criteria 8 and 9): the tasks gate -----------------------------

TASKS_FAIL="gate tasks: FAIL (exit 1)"

# names_open_task LINE-NO TEXT msg : a line of OUT above the tasks gate's
# FAIL line holds TEXT and LINE-NO (as a number of its own)
names_open_task() {
  local n="$1" t="$2" f hit=""
  f="$(line_no "$OUT" "$TASKS_FAIL")"
  if [ -n "$f" ] && [ "$f" -gt 1 ]; then
    hit="$(head -n "$((f - 1))" <<<"$OUT" | grep -F -- "$t" | grep -E "(^|[^0-9])$n([^0-9]|\$)" || true)"
  fi
  if [ -n "$hit" ]; then pass; else fail "$3 (no line naming line $n and '$t' above '$TASKS_FAIL')"; show_output; fi
}

# expect_only_tasks_fails : the tasks gate fails, every other gate runs and
# passes, in order, and one failure is counted
expect_only_tasks_fails() {
  local g
  assert_exit 1 "$CODE" "an open task -> exit 1"
  assert_line "$OUT" "$TASKS_FAIL" "the tasks gate fails"
  for g in tests-locked build test lint check; do
    assert_line "$OUT" "gate $g: ok" "gate $g still runs and passes"
  done
  expect_order "$OUT"
  assert_line "$OUT" "gates: 1 failed" "one failure counted"
  assert_not_contains "$OUT" "gates: ok" "does not claim ok"
}

# expect_tasks_ok : the tasks gate and every other gate pass
expect_tasks_ok() {
  assert_exit 0 "$CODE" "$1: exit 0"
  assert_line "$OUT" "gate tasks: ok" "$1: gate tasks: ok"
  assert_line "$OUT" "gates: ok" "$1: gates: ok"
  expect_order "$OUT"
}

case_G3_open_dash_task_fails() {
  local d; d="$(gated_repo)"
  write_tasks "$d" '# Tasks: x\n\n- [x] zz-done-one\n- [ ] zz-open-dash -- done when: it runs\n\n## Manual verification\n'
  gates "$d" cortex/changes/x
  expect_only_tasks_fails
  names_open_task 4 "zz-open-dash" "the open '- [ ]' task is named with its line number"
  assert_not_contains "$OUT" "zz-done-one" "a ticked task is not listed"
}

case_G3_open_star_task_fails() {
  local d; d="$(gated_repo)"
  write_tasks "$d" '# Tasks: x\n\n* [ ] zz-open-star\n'
  gates "$d" cortex/changes/x
  expect_only_tasks_fails
  names_open_task 3 "zz-open-star" "the open '* [ ]' task is named with its line number"
}

case_G3_open_indented_task_fails() {
  local d; d="$(gated_repo)"
  write_tasks "$d" '# Tasks: x\n\n- [x] zz-parent\n    - [ ] zz-open-indented\n'
  gates "$d" cortex/changes/x
  expect_only_tasks_fails
  names_open_task 4 "zz-open-indented" "the indented open task is named with its line number"
}

case_G3_every_open_task_listed() {
  local d; d="$(gated_repo)"
  write_tasks "$d" '# Tasks: x\n\n- [ ] zz-open-a\n- [x] zz-done\n* [ ] zz-open-b\n  - [ ] zz-open-c\n\t* [ ] zz-open-d\n\n## Gate output\n\n- [ ] zz-later\n'
  gates "$d" cortex/changes/x
  expect_only_tasks_fails
  names_open_task 3 "zz-open-a" "first open task listed"
  names_open_task 5 "zz-open-b" "second open task listed"
  names_open_task 6 "zz-open-c" "third open task listed"
  names_open_task 7 "zz-open-d" "a tab-indented open task listed"
  assert_not_contains "$OUT" "zz-later" "a task under a later heading is not listed"
}

case_G3_missing_tasks_fails() {
  local d; d="$(gated_repo)"
  rm "$d/cortex/changes/x/tasks.md"
  gates "$d" cortex/changes/x
  expect_only_tasks_fails
}

case_G3_ticked_tasks_pass() {
  local d; d="$(gated_repo)"
  write_tasks "$d" '# Tasks: x\n\n- [x] zz-lower\n- [X] zz-upper\n  * [x] zz-star-indented\n'
  gates "$d" cortex/changes/x
  expect_tasks_ok "ticked with x and X"
  assert_not_contains "$OUT" "zz-" "no task listed"
}

case_G3_open_under_later_heading_passes() {
  local d; d="$(gated_repo)"
  write_tasks "$d" '# Tasks: x\n\n- [x] zz-done\n\n## Manual verification\n\n- [ ] zz-manual\n\n## Gate output\n\n* [ ] zz-gate\n'
  gates "$d" cortex/changes/x
  expect_tasks_ok "open tasks only under later headings"
  assert_not_contains "$OUT" "zz-manual" "a manual-verification task is not listed"
}

case_G3_other_gates_still_run() {
  # criterion 8: every other gate still runs; gates: N failed counts both
  local d; d="$(gated_repo "TEST_CMD=false")"
  write_tasks "$d" '# Tasks: x\n\n- [ ] zz-open\n'
  gates "$d" cortex/changes/x
  assert_exit 1 "$CODE" "two failing gates -> exit 1"
  assert_line "$OUT" "gate tests-locked: ok" "tests-locked runs"
  assert_line "$OUT" "$TASKS_FAIL" "tasks fails"
  assert_line "$OUT" "gate build: ok" "build runs after the tasks gate fails"
  assert_line "$OUT" "gate test: FAIL (exit 1)" "test fails"
  assert_line "$OUT" "gate lint: ok" "lint runs"
  assert_line "$OUT" "gate check: ok" "check runs"
  expect_order "$OUT"
  assert_line "$OUT" "gates: 2 failed" "both failures counted"
}

case_G3_gate_order() {
  # criterion 9: tests-locked, tasks, build, test, lint, check, every one
  # reported once, whether they pass or fail
  local d; d="$(gated_repo "BUILD_CMD=false" "LINT_CMD=false")"
  rm "$d/cortex/changes/x/tasks.md"
  printf 'echo weakened\n' > "$d/tests/a.test.sh"
  gates "$d" cortex/changes/x
  assert_exit 1 "$CODE" "failing gates -> exit 1"
  assert_line "$OUT" "gate tests-locked: FAIL (exit 1)" "tests-locked fails"
  assert_line "$OUT" "$TASKS_FAIL" "tasks fails"
  assert_line "$OUT" "gate build: FAIL (exit 1)" "build fails"
  assert_line "$OUT" "gate lint: FAIL (exit 1)" "lint fails"
  expect_order "$OUT"
  assert_true "the gate lines are exactly tests-locked, tasks, build, test, lint, check" \
    test "$(grep -E '^gate [a-z-]+: ' <<<"$OUT" | sed 's/^gate \([a-z-]*\):.*/\1/' | tr '\n' ' ')" = "tests-locked tasks build test lint check "
  assert_line "$OUT" "gates: 4 failed" "four failures counted"
}

# ---- 2026-10-12 spec V4: CORTEX_GATES_LOCK_ONLY=1 ------------------------------------
#
# docs/specs/2026-10-12-verified-review-findings.md, V4: with
# CORTEX_GATES_LOCK_ONLY=1, gates.sh runs tests-locked, tasks and check, and
# prints "gate build: skipped (lock only)" (and the same for test and lint)
# without running them. Its exit code and final line are as today. Unset, its
# output is unchanged.

SKIPPED_GATES="build test lint"

# marker_gated_repo -> gated_repo whose BUILD/TEST/LINT_CMD each create a
# marker file in the repository root (set before the lock: the config is locked)
marker_gated_repo() {
  gated_repo "BUILD_CMD=touch zz-build-ran" "TEST_CMD=touch zz-test-ran" "LINT_CMD=touch zz-lint-ran"
}

lock_only_gates() { # dir [change-folder...] -> gates() with CORTEX_GATES_LOCK_ONLY=1
  local d="$1"; shift
  run env CORTEX_GATES_LOCK_ONLY=1 bash -c 'd="$1"; shift; cd "$d" && ./cortex/bin/gates.sh "$@"' _ "$d" "$@"
}

last_out_line() { printf '%s\n' "$OUT" | sed -n '$p'; }

# expect_skipped DIR : build, test and lint are reported skipped, none of
# them reported ok or FAIL, and none of their commands ran
expect_skipped() {
  local d="$1" g
  for g in $SKIPPED_GATES; do
    assert_line "$OUT" "gate $g: skipped (lock only)" "gate $g: skipped (lock only)"
    assert_true "gate $g not reported ok or FAIL" \
      test "$(grep -cE "^gate $g: (ok|FAIL)" <<<"$OUT" || true)" = 0
    assert_file_absent "$d/zz-$g-ran" "the $g command did not run"
  done
  # each skipped line where that gate's line is today: the order is unchanged
  assert_true "the gate lines are exactly tests-locked, tasks, build, test, lint, check, in that order" \
    test "$(grep -E '^gate [a-z-]+: ' <<<"$OUT" | sed 's/^gate \([a-z-]*\):.*/\1/' | tr '\n' ' ')" = "tests-locked tasks build test lint check "
}

case_V4_lock_only_clean() {
  local d; d="$(marker_gated_repo)"
  lock_only_gates "$d" cortex/changes/x
  assert_exit 0 "$CODE" "lock only, clean locked change -> exit 0"
  assert_line "$OUT" "gate tests-locked: ok" "tests-locked runs"
  assert_line "$OUT" "gate tasks: ok" "tasks runs"
  assert_line "$OUT" "gate check: ok" "check runs"
  expect_skipped "$d"
  assert_true "gates: ok is the last line, as today" test "$(last_out_line)" = "gates: ok"
}

case_V4_lock_only_weakened_test() {
  local d; d="$(marker_gated_repo)"
  printf 'echo weakened\n' > "$d/tests/a.test.sh"
  lock_only_gates "$d" cortex/changes/x
  assert_exit 1 "$CODE" "lock only, weakened locked test -> exit 1"
  assert_line "$OUT" "gate tests-locked: FAIL (exit 1)" "the lock fails"
  assert_contains "$OUT$ERR" "LOCK modified: tests/a.test.sh" "tests-locked output is shown"
  assert_line "$OUT" "gate tasks: ok" "tasks still runs"
  assert_line "$OUT" "gate check: ok" "check still runs"
  expect_skipped "$d"
  assert_true "gates: 1 failed is the last line, as today" test "$(last_out_line)" = "gates: 1 failed"
}

case_V4_unset_runs_commands() {
  # unset, the output is unchanged: every command runs, nothing is skipped
  local d g; d="$(marker_gated_repo)"
  run env -u CORTEX_GATES_LOCK_ONLY bash -c 'cd "$1" && ./cortex/bin/gates.sh cortex/changes/x' _ "$d"
  assert_exit 0 "$CODE" "unset: all gates pass -> exit 0"
  for g in $GATE_NAMES; do
    assert_line "$OUT" "gate $g: ok" "unset: gate $g: ok"
  done
  for g in $SKIPPED_GATES; do
    assert_file_exists "$d/zz-$g-ran" "unset: the $g command ran"
  done
  assert_not_contains "$OUT" "skipped" "unset: nothing skipped"
  expect_order "$OUT"
  assert_true "unset: gates: ok is the last line" test "$(last_out_line)" = "gates: ok"
}

# ---- 2026-10-12 spec V11: a suite with no assertions fails -------------------------
#
# summary (lib.sh) fails when no assertion ran. Planted: suites sourcing this
# checkout's lib.sh, written to a temporary directory and run on their own.

# planted_suite NAME BODY -> path of a suite sourcing lib.sh, then BODY, then summary
planted_suite() {
  local f="$TEST_TMP/v11/$1.test.sh"
  mkdir -p "$TEST_TMP/v11"
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n. %q\n' "$ROOT/tests/lib.sh"
    printf '%s\n' "$2"
    printf 'summary\n'
  } > "$f"
  printf '%s\n' "$f"
}

case_V11_no_assertion_fails() {
  local f
  f="$(planted_suite one-pass 'c() { assert_true "planted" true; }; run_case "one assertion" c')"
  run bash "$f"
  assert_exit 0 "$CODE" "fixture: a planted suite with one passing assertion exits 0"
  f="$(planted_suite no-case '')"
  run bash "$f"
  assert_true "a suite that runs no case exits nonzero (got $CODE)" test "$CODE" -ne 0
  f="$(planted_suite empty-case 'c() { :; }; run_case "no assertion" c')"
  run bash "$f"
  assert_true "a suite whose only case asserts nothing exits nonzero (got $CODE)" test "$CODE" -ne 0
}

# ---- 2026-10-12 spec Amendment 1, A1: a suite that dies before its summary fails ---
#
# run.sh fails a suite whose output has no `<suite>.test.sh: <n> passed, <m>
# failed` line, whatever its exit code. Planted: a scratch copy of run.sh and
# lib.sh (run.sh finds its suites as *.test.sh beside itself), with a suite
# that passes normally and one that exits 0 before its summary.

case_A1_no_summary_fails() {
  local t="$TEST_TMP/a1/tests" mode
  mkdir -p "$t"
  cp "$ROOT/tests/run.sh" "$ROOT/tests/lib.sh" "$t/"
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' '. "$(cd "$(dirname "$0")" && pwd)/lib.sh"' \
    'c() { assert_true "planted" true; }' 'run_case "one assertion" c' 'summary' > "$t/good.test.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' '. "$(cd "$(dirname "$0")" && pwd)/lib.sh"' \
    'c() { assert_true "planted" true; }' 'run_case "one assertion" c' \
    'echo "stopped before the summary"' 'exit 0' 'summary' > "$t/dies.test.sh"
  run bash "$t/dies.test.sh"
  assert_exit 0 "$CODE" "fixture: the planted suite exits 0"
  assert_not_contains "$OUT" "dies.test.sh: " "fixture: the planted suite prints no summary line"
  for mode in "" --parallel; do
    run bash "$t/run.sh" $mode good
    assert_exit 0 "$CODE" "run.sh ${mode:-(sequential)} good: a normal passing suite passes"
    assert_line "$OUT" "=== PASS good.test.sh" "run.sh ${mode:-(sequential)}: good.test.sh reported PASS"
    run bash "$t/run.sh" $mode dies
    assert_true "run.sh ${mode:-(sequential)} dies: a suite without its summary line exits nonzero (got $CODE)" test "$CODE" -ne 0
    assert_contains "$OUT" "=== FAIL dies.test.sh" "run.sh ${mode:-(sequential)}: dies.test.sh reported FAIL (A1)"
    assert_not_contains "$OUT" "=== PASS dies.test.sh" "run.sh ${mode:-(sequential)}: dies.test.sh not reported PASS (A1)"
    run bash "$t/run.sh" $mode
    assert_exit 1 "$CODE" "run.sh ${mode:-(sequential)}, every suite: exit 1"
    assert_line "$OUT" "suites: 1 passed, 1 failed (of 2)" "run.sh ${mode:-(sequential)}: one passed, one failed"
  done
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
run_case "AC32 BUILD_CMD with spaces around =" case_AC32_spaced
run_case "AC32 BUILD_CMD after a commented-out line" case_AC32_comment
run_case "AC32 BUILD_CMD after a line without =" case_AC32_no_equals
run_case "AC32 BUILD_CMD twice: the first wins" case_AC32_twice
run_case "AC34 a stub _config.sh changes what gates.sh reads" case_AC34_stub_parser
run_case "G3 criterion 8: an open - [ ] task fails the tasks gate" case_G3_open_dash_task_fails
run_case "G3 criterion 8: an open * [ ] task fails the tasks gate" case_G3_open_star_task_fails
run_case "G3 criterion 8: an indented open task fails the tasks gate" case_G3_open_indented_task_fails
run_case "G3 criterion 8: every open task is listed" case_G3_every_open_task_listed
run_case "G3 criterion 8: a missing tasks.md fails the tasks gate" case_G3_missing_tasks_fails
run_case "G3 criterion 8: tasks ticked with x and X pass" case_G3_ticked_tasks_pass
run_case "G3 criterion 8: open tasks under a later heading pass" case_G3_open_under_later_heading_passes
run_case "G3 criterion 8: every other gate still runs" case_G3_other_gates_still_run
run_case "G3 criterion 9: the gate order" case_G3_gate_order
run_case "V4 lock only: a clean locked change runs no project command" case_V4_lock_only_clean
run_case "V4 lock only: a weakened locked test fails, no project command runs" case_V4_lock_only_weakened_test
run_case "V4 unset: every command runs, nothing skipped" case_V4_unset_runs_commands
run_case "V11 a suite in which no assertion runs exits nonzero" case_V11_no_assertion_fails
run_case "A1 run.sh fails a suite that prints no summary line" case_A1_no_summary_fails
summary
