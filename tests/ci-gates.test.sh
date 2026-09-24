#!/usr/bin/env bash
# Tests for scripts/cortex/ci-gates.sh (spec Amendment 3, C1; acceptance
# criteria 21-25). ci-gates.sh <base-ref> runs, with the checker scripts taken
# from <base-ref>: a hidden-edit scan (skip-worktree / assume-unchanged), the
# base copy of check.sh, and the base copy of gates.sh for every change folder
# whose lock.md was added or changed on this branch (base...HEAD).
#
# Fixture: a filled install (plus tests/a.test.sh, src/app.txt) committed as
# the base, pointed to by refs/remotes/origin/main, the way CI sees it. A
# feature branch then locks changes/x in the Amendment 2 layout: the tests are
# committed (T, adds tests/b.test.sh), then changes/x/lock.md naming T in its
# own commit (L). Each case plants its violation on the feature branch.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

BASE="origin/main"

commit_all() { # dir msg
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}

# lock_folder DIR FOLDER : commit everything as T, then FOLDER/lock.md naming
# T (locking tests/b.test.sh) as its own commit L
lock_folder() {
  local d="$1" f="$2" sha
  commit_all "$d" "add tests for $f"
  sha="$(git -C "$d" rev-parse HEAD)"
  mkdir -p "$d/$f"
  cat > "$d/$f/lock.md" <<EOF2
Tests-locked-at: $sha

## Locked tests

- tests/b.test.sh
EOF2
  commit_all "$d" "lock tests for $f"
}

# base_only -> filled install committed as the base (origin/main), checked out
# on branch "feature" at the same commit; nothing locked yet
base_only() {
  local d
  d="$(filled_install Zqxproj)" || return 1
  mkdir -p "$d/tests" "$d/src"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  printf 'app\n' > "$d/src/app.txt"
  commit_all "$d" "base: cortex installed"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q -b feature
  printf '%s\n' "$d"
}

# ci_repo -> base_only plus, on the feature branch, changes/x locked
ci_repo() {
  local d
  d="$(base_only)" || return 1
  printf 'echo b\n' > "$d/tests/b.test.sh"
  lock_folder "$d" changes/x
  printf '%s\n' "$d"
}

ci_gates() { # dir [args...] -> run the working tree's ci-gates.sh from the repo root
  local d="$1"; shift
  run bash -c 'd="$1"; shift; cd "$d" && bash scripts/cortex/ci-gates.sh "$@"' _ "$d" "$@"
}

ci_lines() { grep '^ci-gates: ' <<<"$1" || true; }

last_line() { printf '%s\n' "$1" | sed -n '$p'; }

# expect_ci_lines EXPECTED msg : the "ci-gates: " lines of OUT, exactly and in order
expect_ci_lines() {
  local got; got="$(ci_lines "$OUT")"
  if [ "$got" = "$1" ]; then pass
  else fail "$2 (ci-gates lines differ)"; printf '    expected:\n%s\n' "$(sed 's/^/      /' <<<"$1")" >&2; show_output; fi
}

# ---- shipped ------------------------------------------------------------------

case_installed() {
  local d; d="$(fresh_install)"
  assert_file_exists "$ROOT/template/scripts/cortex/ci-gates.sh" "template ships ci-gates.sh"
  assert_true "installed ci-gates.sh is executable" test -x "$d/scripts/cortex/ci-gates.sh"
}

# ---- AC25 usage -----------------------------------------------------------------

case_usage_no_argument() {
  local d; d="$(ci_repo)"
  ci_gates "$d"
  assert_exit 2 "$CODE" "no argument exits 2"
  assert_not_contains "$OUT" "ci-gates: ok" "no success line on a usage error"
  assert_not_contains "$OUT" "gate " "no gates run on a usage error"
}

case_usage_bad_ref() {
  local d; d="$(ci_repo)"
  ci_gates "$d" no-such-ref/at-all
  assert_exit 2 "$CODE" "an unresolvable ref exits 2"
  assert_not_contains "$OUT" "ci-gates: ok" "no success line for a bad ref"
  assert_not_contains "$OUT" "gate " "no gates run for a bad ref"
}

# ---- AC23 which folders are gated -------------------------------------------------

case_clean_with_lock() {
  local d; d="$(ci_repo)"
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "clean branch with a new lock -> exit 0"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: changes/x ok
ci-gates: ok" "clean branch: exact ci-gates lines"
  assert_line "$OUT" "gates: ok" "the base gates.sh output is printed"
  assert_line "$OUT" "gate tests-locked: ok" "gates.sh ran the lock gate"
  assert_true "ci-gates: ok is the last line" test "$(last_line "$OUT")" = "ci-gates: ok"
  assert_true "working tree left clean (temp scripts outside the repo)" \
    test -z "$(git -C "$d" status --porcelain)"
}

case_no_changed_locks() {
  # a branch that touches no lock.md: only the check runs
  local d; d="$(base_only)"
  printf 'app v2\n' > "$d/src/app.txt"
  commit_all "$d" "feature work"
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "no changed lock.md -> exit 0"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: ok" "only the check runs"
  assert_not_contains "$OUT" "gate tests-locked" "gates.sh not run"
}

case_same_commit_as_base() {
  local d; d="$(base_only)"
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "HEAD = base -> exit 0"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: ok" "HEAD = base: only the check runs"
}

# base with changes/old/lock.md whose sha is garbage (gating it would fail
# LOCK bad-sha); returns the repo on the feature branch
base_with_old_lock() {
  local d
  d="$(filled_install Zqxproj)" || return 1
  mkdir -p "$d/tests" "$d/src" "$d/changes/old"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  printf 'app\n' > "$d/src/app.txt"
  printf 'Tests-locked-at: 0000000000000000000000000000000000000000\n\n## Locked tests\n\n- tests/a.test.sh\n' \
    > "$d/changes/old/lock.md"
  printf '# tasks\n' > "$d/changes/old/tasks.md"
  commit_all "$d" "base with an old change folder"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q -b feature
  printf '%s\n' "$d"
}

case_unchanged_lock_not_gated() {
  local d; d="$(base_with_old_lock)"
  printf '# tasks\n- more\n' > "$d/changes/old/tasks.md"   # folder touched, lock.md not
  printf 'echo b\n' > "$d/tests/b.test.sh"
  lock_folder "$d" changes/x
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "only the changed lock is gated -> exit 0"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: changes/x ok
ci-gates: ok" "changes/x gated, changes/old not"
  assert_not_contains "$OUT" "changes/old" "the unchanged folder is not gated"
  assert_not_contains "$OUT" "LOCK bad-sha" "the old lock was not checked"
}

case_deleted_lock_not_gated() {
  local d; d="$(base_with_old_lock)"
  git -C "$d" rm -q changes/old/lock.md
  git -C "$d" commit -q -m "drop old lock"
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "a lock.md removed on the branch is not gated"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: ok" "no folder gated when its lock.md no longer exists"
}

case_base_moved_on() {
  # three-dot diff: a lock.md changed only on the base after the branch point
  # differs from the base but was not changed on this branch -> not gated
  local d; d="$(base_with_old_lock)"
  git -C "$d" checkout -q -B main "$BASE"
  printf 'Tests-locked-at: 1111111111111111111111111111111111111111\n\n## Locked tests\n\n- tests/a.test.sh\n' \
    > "$d/changes/old/lock.md"
  commit_all "$d" "base moves on"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q feature
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "a lock changed only on the base is not gated"
  assert_not_contains "$OUT" "changes/old" "changes/old not gated"
  assert_line "$OUT" "ci-gates: ok" "ends ok"
}

# ---- AC21 the checker comes from the base -----------------------------------------

case_tampered_tests_locked() {
  local d; d="$(ci_repo)"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/scripts/cortex/tests-locked.sh"
  printf 'echo weakened\n' > "$d/tests/b.test.sh"
  commit_all "$d" "weaken the test and the checker"
  # the branch's own gates.sh is fooled
  run bash -c 'cd "$1" && bash scripts/cortex/gates.sh changes/x' _ "$d"
  assert_exit 0 "$CODE" "fixture: the branch's own gates.sh passes"
  assert_line "$OUT" "gates: ok" "fixture: the branch's gates.sh says ok"
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "ci-gates fails with the base checker"
  assert_line "$OUT" "ci-gates: using scripts from $BASE" "reports using the base scripts"
  assert_contains "$OUT" "LOCK modified: tests/b.test.sh" "base tests-locked.sh names the weakened test"
  assert_line "$OUT" "gate tests-locked: FAIL (exit 1)" "base gates.sh output printed"
  assert_line "$OUT" "ci-gates: check ok" "check still passes"
  assert_line "$OUT" "ci-gates: FAIL changes/x" "the folder fails"
  assert_line "$OUT" "ci-gates: 1 failed" "one failure counted"
  assert_true "the count is the last line" test "$(last_line "$OUT")" = "ci-gates: 1 failed"
}

case_tampered_gates_and_check() {
  # every checker on the branch lies; the base copies still catch both
  # plants, and every step runs after the first failure (two counted)
  local d; d="$(ci_repo)"
  printf '#!/usr/bin/env bash\necho "gates: ok"\nexit 0\n' > "$d/scripts/cortex/gates.sh"
  printf '#!/usr/bin/env bash\necho "check: ok"\nexit 0\n' > "$d/scripts/cortex/check.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/scripts/cortex/tests-locked.sh"
  printf 'echo weakened\n' > "$d/tests/a.test.sh"
  append "$d/AGENTS.md" "TODO: planted"
  commit_all "$d" "tamper"
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "two failures -> exit 1"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: FAIL check
ci-gates: FAIL changes/x
ci-gates: 2 failed" "both failures reported, in order"
  assert_contains "$OUT" "LOCK modified: tests/a.test.sh" "pre-existing locked test caught by the base checker"
}

case_from_subdir() {
  local d; d="$(ci_repo)"
  printf 'echo weakened\n' > "$d/tests/b.test.sh"
  commit_all "$d" "weaken"
  run bash -c 'cd "$1/src" && bash ../scripts/cortex/ci-gates.sh "$2"' _ "$d" "$BASE"
  assert_exit 1 "$CODE" "from a subdirectory: still fails"
  assert_line "$OUT" "ci-gates: using scripts from $BASE" "uses base scripts from a subdirectory"
  assert_line "$OUT" "ci-gates: check ok" "check runs on the repo root"
  assert_line "$OUT" "ci-gates: FAIL changes/x" "folder named relative to the root"
  assert_contains "$OUT" "LOCK modified: tests/b.test.sh" "the weakened test is named"
  assert_line "$OUT" "ci-gates: 1 failed" "one failure counted"
}

case_from_subdir_clean() {
  local d; d="$(ci_repo)"
  run bash -c 'cd "$1/src" && bash ../scripts/cortex/ci-gates.sh "$2"' _ "$d" "$BASE"
  assert_exit 0 "$CODE" "clean from a subdirectory -> exit 0"
  assert_line "$OUT" "ci-gates: changes/x ok" "folder gated from a subdirectory"
  assert_line "$OUT" "ci-gates: ok" "ends ok"
}

# ---- AC22 no cortex at the base -----------------------------------------------------

# pre_cortex_repo -> base commit without cortex (origin/main), then on branch
# "feature" cortex installed, filled and committed
pre_cortex_repo() {
  local d
  d="$(new_git_repo)"
  printf '# app\n' > "$d/README.md"
  mkdir -p "$d/src"; printf 'app\n' > "$d/src/app.txt"
  commit_all "$d" "base without cortex"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q -b feature
  "$ROOT/scripts/install.sh" "$d" >/dev/null || return 1
  fill_install "$d" Zqxproj || return 1
  mkdir -p "$d/tests"; printf 'echo a\n' > "$d/tests/a.test.sh"
  commit_all "$d" "install cortex"
  printf '%s\n' "$d"
}

NOTE_LINE="ci-gates: note: $BASE has no cortex scripts; using this branch's copy"

case_no_cortex_at_base() {
  local d; d="$(pre_cortex_repo)"
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "installing change passes with the branch copy"
  expect_ci_lines "$NOTE_LINE
ci-gates: check ok
ci-gates: ok" "note, check, ok"
  assert_not_contains "$OUT" "using scripts from" "does not claim base scripts"
}

case_no_cortex_at_base_with_lock() {
  local d; d="$(pre_cortex_repo)"
  printf 'echo b\n' > "$d/tests/b.test.sh"
  lock_folder "$d" changes/x
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "branch copy gates the new lock"
  expect_ci_lines "$NOTE_LINE
ci-gates: check ok
ci-gates: changes/x ok
ci-gates: ok" "note, check, folder, ok"
}

case_no_cortex_at_base_uses_branch_copy() {
  # evidence the branch copy really runs: a branch check.sh that fails
  local d; d="$(pre_cortex_repo)"
  printf '#!/usr/bin/env bash\necho "branch-check-marker"\nexit 1\n' > "$d/scripts/cortex/check.sh"
  commit_all "$d" "branch check fails"
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "branch check.sh failing -> exit 1"
  assert_line "$OUT" "$NOTE_LINE" "prints the note"
  assert_line "$OUT" "ci-gates: FAIL check" "the branch copy's failure is reported"
  assert_line "$OUT" "ci-gates: 1 failed" "one failure counted"
}

# ---- AC24 hidden edits ----------------------------------------------------------------

case_skip_worktree() {
  local d; d="$(ci_repo)"
  git -C "$d" update-index --skip-worktree src/app.txt
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "skip-worktree -> exit 1"
  assert_line "$OUT" "ci-gates: FAIL hidden src/app.txt" "names the skip-worktree file"
  assert_line "$OUT" "ci-gates: check ok" "check still runs"
  assert_line "$OUT" "ci-gates: changes/x ok" "folder still gated"
  assert_line "$OUT" "ci-gates: 1 failed" "one failure per hidden file"
}

case_assume_unchanged() {
  local d; d="$(ci_repo)"
  git -C "$d" update-index --assume-unchanged tests/a.test.sh
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "assume-unchanged -> exit 1"
  assert_line "$OUT" "ci-gates: FAIL hidden tests/a.test.sh" "names the assume-unchanged file"
  assert_line "$OUT" "ci-gates: 1 failed" "one failure counted"
}

case_two_hidden() {
  local d; d="$(ci_repo)"
  git -C "$d" update-index --skip-worktree src/app.txt
  git -C "$d" update-index --assume-unchanged tests/a.test.sh
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "two hidden files -> exit 1"
  assert_line "$OUT" "ci-gates: FAIL hidden src/app.txt" "skip-worktree file named"
  assert_line "$OUT" "ci-gates: FAIL hidden tests/a.test.sh" "assume-unchanged file named"
  assert_line "$OUT" "ci-gates: check ok" "check still runs"
  assert_line "$OUT" "ci-gates: 2 failed" "one failure per file"
}

case_hidden_plus_lock_failure() {
  local d; d="$(ci_repo)"
  printf 'echo weakened\n' > "$d/tests/b.test.sh"
  commit_all "$d" "weaken"
  git -C "$d" update-index --skip-worktree tests/b.test.sh
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "hidden + broken lock -> exit 1"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: FAIL hidden tests/b.test.sh
ci-gates: check ok
ci-gates: FAIL changes/x
ci-gates: 2 failed" "all steps run and both failures count"
}

run_case "ci-gates.sh shipped and installed executable" case_installed
run_case "AC25 no argument -> exit 2" case_usage_no_argument
run_case "AC25 unresolvable ref -> exit 2" case_usage_bad_ref
run_case "AC23 clean branch with a new lock -> ok" case_clean_with_lock
run_case "AC23 no changed lock.md: only the check runs" case_no_changed_locks
run_case "AC23 HEAD equals the base" case_same_commit_as_base
run_case "AC23 unchanged lock.md is not gated" case_unchanged_lock_not_gated
run_case "AC23 lock.md deleted on the branch is not gated" case_deleted_lock_not_gated
run_case "AC23 lock changed only on the base is not gated" case_base_moved_on
run_case "AC21 edited tests-locked.sh: base copy catches the weakened test" case_tampered_tests_locked
run_case "AC21 edited gates/check: two failures, every step runs" case_tampered_gates_and_check
run_case "from a subdirectory: failure" case_from_subdir
run_case "from a subdirectory: clean" case_from_subdir_clean
run_case "AC22 no cortex at base: note + branch copy" case_no_cortex_at_base
run_case "AC22 no cortex at base: new lock gated" case_no_cortex_at_base_with_lock
run_case "AC22 no cortex at base: branch check.sh is what runs" case_no_cortex_at_base_uses_branch_copy
run_case "AC24 skip-worktree -> FAIL hidden" case_skip_worktree
run_case "AC24 assume-unchanged -> FAIL hidden" case_assume_unchanged
run_case "AC24 two hidden files counted separately" case_two_hidden
run_case "AC24 hidden + broken lock: both counted" case_hidden_plus_lock_failure
summary
