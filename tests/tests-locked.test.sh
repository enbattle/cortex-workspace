#!/usr/bin/env bash
# Tests for scripts/cortex/tests-locked.sh (spec acceptance criterion 6).
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

# write_tasks DIR SHA : changes/x/tasks.md locking tests/a.test.sh and
# tests/b.test.sh (the second wrapped in backticks)
write_tasks() {
  mkdir -p "$1/changes/x"
  cat > "$1/changes/x/tasks.md" <<EOF
# Tasks

Tests-locked-at: $2

## Locked tests

- tests/a.test.sh
- \`tests/b.test.sh\`

## Tasks

- [ ] implement the feature
EOF
}

commit_all() { # dir msg
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}

# locked_repo -> installed repo whose HEAD~1 is the lock commit (tests a, b
# committed, TEST_GLOBS=*.test.sh) and HEAD adds changes/x/tasks.md
locked_repo() {
  local d sha
  d="$(fresh_install)" || return 1
  set_config "$d/.cortex/config" TEST_GLOBS '*.test.sh'
  mkdir -p "$d/tests" "$d/src"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  printf 'echo b\n' > "$d/tests/b.test.sh"
  printf 'app\n' > "$d/src/app.txt"
  commit_all "$d" "lock tests"
  sha="$(git -C "$d" rev-parse HEAD)"
  write_tasks "$d" "$sha"
  commit_all "$d" "tasks"
  printf '%s\n' "$d"
}

lock_sha() { git -C "$1" rev-parse HEAD~1; }

locked() { # dir [change-folder] -> run tests-locked.sh from the repo root
  run bash -c 'cd "$1" && ./scripts/cortex/tests-locked.sh "$2"' _ "$1" "${2:-changes/x}"
}

expect_lock() { # kind detail msg
  assert_exit 1 "$CODE" "$3: exits 1"
  assert_contains "$OUT$ERR" "LOCK $1: $2" "$3: reports LOCK $1"
  assert_not_contains "$OUT" "tests-locked: " "$3: no success line"
}

case_pass_untouched() {
  local d sha; d="$(locked_repo)"; sha="$(lock_sha "$d")"
  locked "$d"
  assert_exit 0 "$CODE" "untouched locked set passes"
  assert_contains "$OUT" "tests-locked: 2 file(s) unchanged since" "success line counts 2 files"
  assert_contains "$OUT" "since $(printf '%s' "$sha" | cut -c1-7)" "success line names the short sha"
  assert_not_contains "$OUT$ERR" "LOCK " "no LOCK lines on success"
}

case_pass_non_test_changes() {
  local d; d="$(locked_repo)"
  printf 'app v2\n' > "$d/src/app.txt"
  printf 'new\n' > "$d/src/new.txt"
  commit_all "$d" "implementation"
  printf 'more\n' >> "$d/src/app.txt"
  locked "$d"
  assert_exit 0 "$CODE" "implementation changes outside tests are fine"
}

case_pass_from_subdir() {
  local d; d="$(locked_repo)"
  run bash -c 'cd "$1/src" && ../scripts/cortex/tests-locked.sh ../changes/x' _ "$d"
  assert_exit 0 "$CODE" "runs from a subdirectory of the repo"
  assert_contains "$OUT" "tests-locked: 2 file(s) unchanged since" "success from subdir"
}

case_usage_error() {
  local d; d="$(locked_repo)"
  run bash -c 'cd "$1" && ./scripts/cortex/tests-locked.sh' _ "$d"
  assert_exit 2 "$CODE" "no argument is a usage error (exit 2)"
}

case_modified_committed() {
  local d; d="$(locked_repo)"
  printf 'echo a changed\n' > "$d/tests/a.test.sh"
  commit_all "$d" "weaken test"
  locked "$d"
  expect_lock modified tests/a.test.sh "committed modification"
}

case_modified_unstaged() {
  local d; d="$(locked_repo)"
  printf 'echo a changed\n' > "$d/tests/a.test.sh"
  locked "$d"
  expect_lock modified tests/a.test.sh "unstaged modification"
}

case_modified_staged() {
  local d; d="$(locked_repo)"
  printf 'echo b changed\n' > "$d/tests/b.test.sh"
  git -C "$d" add tests/b.test.sh
  locked "$d"
  expect_lock modified tests/b.test.sh "staged modification (backticked path)"
}

case_deleted() {
  local d; d="$(locked_repo)"
  rm "$d/tests/a.test.sh"
  locked "$d"
  expect_lock deleted tests/a.test.sh "deleted test"
}

case_deleted_committed() {
  local d; d="$(locked_repo)"
  git -C "$d" rm -q tests/b.test.sh
  git -C "$d" commit -q -m "drop test"
  locked "$d"
  expect_lock deleted tests/b.test.sh "committed deletion"
}

case_added_untracked() {
  local d; d="$(locked_repo)"
  printf 'echo c\n' > "$d/tests/c.test.sh"
  locked "$d"
  expect_lock added tests/c.test.sh "new untracked test"
}

case_added_staged() {
  local d; d="$(locked_repo)"
  printf 'echo c\n' > "$d/tests/c.test.sh"
  git -C "$d" add tests/c.test.sh
  locked "$d"
  expect_lock added tests/c.test.sh "new staged test"
}

case_added_committed() {
  local d; d="$(locked_repo)"
  printf 'echo c\n' > "$d/tests/c.test.sh"
  commit_all "$d" "add test"
  locked "$d"
  expect_lock added tests/c.test.sh "new committed test"
}

case_added_ignored_without_globs() {
  local d; d="$(locked_repo)"
  set_config "$d/.cortex/config" TEST_GLOBS ""
  commit_all "$d" "no globs"
  printf 'echo c\n' > "$d/tests/c.test.sh"
  locked "$d"
  assert_exit 0 "$CODE" "without TEST_GLOBS, new tests are not flagged"
}

case_sha_not_ancestor() {
  local d side
  d="$(locked_repo)"
  git -C "$d" checkout -q -b side
  printf 'side\n' > "$d/side.txt"
  commit_all "$d" "side commit"
  side="$(git -C "$d" rev-parse HEAD)"
  git -C "$d" checkout -q -
  assert_true "back on the main branch" test "$(git -C "$d" rev-parse HEAD)" != "$side"
  write_tasks "$d" "$side"
  locked "$d"
  expect_lock bad-sha "" "sha not an ancestor of HEAD"
}

case_sha_unresolvable() {
  local d; d="$(locked_repo)"
  write_tasks "$d" 0123456789abcdef0123456789abcdef01234567
  locked "$d"
  expect_lock bad-sha "" "sha that is not a commit"
}

case_missing_locked_at() {
  local d; d="$(locked_repo)"
  filter_file "$d/changes/x/tasks.md" awk '!/^Tests-locked-at:/'
  assert_file_not_contains "$d/changes/x/tasks.md" "Tests-locked-at:" "plant removed the line"
  locked "$d"
  expect_lock missing "" "missing Tests-locked-at line"
}

case_missing_tasks_file() {
  local d; d="$(locked_repo)"
  mkdir -p "$d/changes/empty"
  locked "$d" changes/empty
  expect_lock missing "" "missing tasks.md"
}

case_no_locked_tests() {
  local d; d="$(locked_repo)"
  filter_file "$d/changes/x/tasks.md" awk '!/test\.sh/'
  assert_file_not_contains "$d/changes/x/tasks.md" "test.sh" "plant removed the list"
  locked "$d"
  expect_lock missing "" "empty locked-tests list"
}

case_not_locked() {
  local d; d="$(locked_repo)"
  filter_file "$d/changes/x/tasks.md" awk '{print} /^- tests\/a\.test\.sh$/ {print "- tests/z.test.sh"}'
  assert_file_contains "$d/changes/x/tasks.md" "- tests/z.test.sh" "plant added a path"
  locked "$d"
  expect_lock not-locked tests/z.test.sh "listed path absent at the sha"
}

run_case "pass: untouched locked set" case_pass_untouched
run_case "pass: non-test changes" case_pass_non_test_changes
run_case "pass: run from a subdirectory" case_pass_from_subdir
run_case "usage error -> exit 2" case_usage_error
run_case "modified: committed" case_modified_committed
run_case "modified: unstaged" case_modified_unstaged
run_case "modified: staged" case_modified_staged
run_case "deleted: working tree" case_deleted
run_case "deleted: committed" case_deleted_committed
run_case "added: untracked" case_added_untracked
run_case "added: staged" case_added_staged
run_case "added: committed" case_added_committed
run_case "added: ignored without TEST_GLOBS" case_added_ignored_without_globs
run_case "bad-sha: not an ancestor" case_sha_not_ancestor
run_case "bad-sha: unresolvable" case_sha_unresolvable
run_case "missing: no Tests-locked-at" case_missing_locked_at
run_case "missing: no tasks.md" case_missing_tasks_file
run_case "missing: no locked tests" case_no_locked_tests
run_case "not-locked: path absent at sha" case_not_locked
summary
