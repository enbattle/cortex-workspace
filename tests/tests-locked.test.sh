#!/usr/bin/env bash
# Tests for cortex/bin/tests-locked.sh (spec acceptance criteria 6, 9 and,
# under Amendment 2, 14-16).
#
# Lock layout (Amendment 2, B1): test-first commits the tests (commit T), then
# adds <change-folder>/lock.md naming T in its own commit L, whose first
# parent is T. Every fixture below builds exactly that: T, then L, then any
# further commits. The lock also covers cortex/config (B2), which counts in
# the success line when it existed at T, so a fresh install's counts are
# "locked tests + 1".
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

LOCK_REL="cortex/changes/x/lock.md"

# write_lock DIR SHA [LIST-LINE...] : cortex/changes/x/lock.md naming SHA ("-" omits
# the Tests-locked-at line). With no list lines, locks tests/a.test.sh and
# tests/b.test.sh (the second wrapped in backticks). A "## Notes" section
# follows the list, so the list must end at the next heading.
write_lock() {
  local d="$1" sha="$2"; shift 2
  mkdir -p "$d/cortex/changes/x"
  {
    printf '<!-- lock record, written once by test-first -->\n\n'
    if [ "$sha" != "-" ]; then printf 'Tests-locked-at: %s\n\n' "$sha"; fi
    printf '## Locked tests\n\n'
    if [ "$#" -eq 0 ]; then
      printf '%s\n' '- tests/a.test.sh' '- `tests/b.test.sh`'
    else
      printf '%s\n' "$@"
    fi
    printf '\n## Notes\n\n- written by test-first\n'
  } > "$d/$LOCK_REL"
}

# base_repo [GLOBS] -> installed repo, nothing committed yet, with TEST_GLOBS
# set to GLOBS (default *.test.sh; "" leaves it empty), tests/a.test.sh,
# tests/b.test.sh and src/app.txt
base_repo() {
  local d globs="${1-*.test.sh}"
  d="$(fresh_install)" || return 1
  set_config "$d/cortex/config" TEST_GLOBS "$globs"
  mkdir -p "$d/tests" "$d/src"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  printf 'echo b\n' > "$d/tests/b.test.sh"
  printf 'app\n' > "$d/src/app.txt"
  printf '%s\n' "$d"
}

# lock_it DIR [LIST-LINE...] : commit everything as T, then lock.md naming T as
# its own commit L
lock_it() {
  local d="$1" sha; shift
  commit_all "$d" "add tests"
  sha="$(git -C "$d" rev-parse HEAD)"
  write_lock "$d" "$sha" "$@"
  commit_all "$d" "lock tests"
}

# locked_repo [GLOBS] -> base_repo, locked: HEAD is L, HEAD~1 is T
locked_repo() {
  local d
  d="$(base_repo "$@")" || return 1
  lock_it "$d"
  printf '%s\n' "$d"
}

lock_sha() { git -C "$1" rev-parse HEAD~1; }

locked() { # dir [change-folder] -> run tests-locked.sh from the repo root
  run bash -c 'cd "$1" && ./cortex/bin/tests-locked.sh "$2"' _ "$1" "${2:-cortex/changes/x}"
}

expect_lock() { # kind detail msg
  assert_exit 1 "$CODE" "$3: exits 1"
  assert_contains "$OUT$ERR" "LOCK $1: $2" "$3: reports LOCK $1"
  assert_not_contains "$OUT" "tests-locked: " "$3: no success line"
}

expect_pass() { # count msg
  assert_exit 0 "$CODE" "$2: exits 0"
  assert_contains "$OUT" "tests-locked: $1 file(s) unchanged since" "$2: success line counts $1"
  assert_not_contains "$OUT$ERR" "LOCK " "$2: no LOCK lines"
}

case_fixture_layout() {
  local d sha; d="$(locked_repo)"; sha="$(lock_sha "$d")"
  assert_true "fixture: L's first parent is T" test "$(git -C "$d" rev-parse HEAD^1)" = "$sha"
  assert_true "fixture: exactly one commit touches lock.md" \
    test "$(git -C "$d" log --format=%H -- "$LOCK_REL" | grep -c .)" = 1
  assert_true "fixture: that commit is HEAD" \
    test "$(git -C "$d" log --format=%H -- "$LOCK_REL")" = "$(git -C "$d" rev-parse HEAD)"
  assert_file_contains "$d/$LOCK_REL" "Tests-locked-at: $sha" "fixture: lock.md names T"
  assert_file_absent "$d/cortex/changes/x/tasks.md" "fixture: no tasks.md is needed"
}

case_pass_untouched() {
  local d sha; d="$(locked_repo)"; sha="$(lock_sha "$d")"
  locked "$d"
  # a, b + cortex/config (B2)
  expect_pass 3 "untouched locked set"
  assert_contains "$OUT" "since $(printf '%s' "$sha" | cut -c1-7)" "success line names the short sha"
}

case_pass_non_test_changes() {
  local d; d="$(locked_repo)"
  printf 'app v2\n' > "$d/src/app.txt"
  printf 'new\n' > "$d/src/new.txt"
  commit_all "$d" "implementation"
  printf 'more\n' >> "$d/src/app.txt"
  printf '%s\n' '- [x] done' > "$d/cortex/changes/x/tasks.md"
  locked "$d"
  assert_exit 0 "$CODE" "implementation changes outside tests (and tasks.md) are fine"
}

case_pass_from_subdir() {
  local d; d="$(locked_repo)"
  run bash -c 'cd "$1/src" && ../cortex/bin/tests-locked.sh ../cortex/changes/x' _ "$d"
  assert_exit 0 "$CODE" "runs from a subdirectory of the repo"
  assert_contains "$OUT" "tests-locked: 3 file(s) unchanged since" "success from subdir"
}

case_usage_error() {
  local d; d="$(locked_repo)"
  run bash -c 'cd "$1" && ./cortex/bin/tests-locked.sh' _ "$d"
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
  local d; d="$(locked_repo "")"
  printf 'echo c\n' > "$d/tests/c.test.sh"
  locked "$d"
  assert_exit 0 "$CODE" "without TEST_GLOBS at the lock, new tests are not flagged"
}

# bad-sha: with the B1 layout a sha that isn't an ancestor (or isn't a commit)
# can only appear in an edited lock.md, so LOCK moved may be reported too; the
# bad-sha line must still be there.
case_sha_not_ancestor() {
  local d side
  d="$(locked_repo)"
  git -C "$d" checkout -q -b side
  printf 'side\n' > "$d/side.txt"
  commit_all "$d" "side commit"
  side="$(git -C "$d" rev-parse HEAD)"
  git -C "$d" checkout -q -
  assert_true "back on the main branch" test "$(git -C "$d" rev-parse HEAD)" != "$side"
  write_lock "$d" "$side"
  locked "$d"
  expect_lock bad-sha "" "sha not an ancestor of HEAD"
}

case_sha_unresolvable() {
  local d; d="$(locked_repo)"
  write_lock "$d" 0123456789abcdef0123456789abcdef01234567
  locked "$d"
  expect_lock bad-sha "" "sha that is not a commit"
}

case_missing_locked_at() {
  local d; d="$(base_repo)"
  commit_all "$d" "add tests"
  write_lock "$d" -
  commit_all "$d" "lock tests"
  assert_file_not_contains "$d/$LOCK_REL" "Tests-locked-at:" "plant has no Tests-locked-at line"
  locked "$d"
  expect_lock missing "" "missing Tests-locked-at line"
}

case_missing_lock_file() {
  local d; d="$(locked_repo)"
  mkdir -p "$d/cortex/changes/empty"
  printf 'Tests-locked-at: %s\n\n## Locked tests\n\n- tests/a.test.sh\n' "$(lock_sha "$d")" \
    > "$d/cortex/changes/empty/tasks.md"
  commit_all "$d" "a tasks.md is not a lock record"
  locked "$d" cortex/changes/empty
  expect_lock missing "" "missing lock.md (tasks.md is no longer read)"
}

case_no_locked_tests() {
  local d; d="$(base_repo)"
  lock_it "$d" ""
  assert_file_not_contains "$d/$LOCK_REL" "test.sh" "plant has an empty list"
  locked "$d"
  expect_lock missing "" "empty locked-tests list"
  assert_not_contains "$OUT$ERR" "LOCK moved" "a correctly committed lock.md is not moved"
}

case_not_locked() {
  local d; d="$(base_repo)"
  lock_it "$d" '- tests/a.test.sh' '- tests/z.test.sh'
  locked "$d"
  expect_lock not-locked tests/z.test.sh "listed path absent at the sha"
  assert_not_contains "$OUT$ERR" "LOCK moved" "a correctly committed lock.md is not moved"
}

# ---- AC9 (A1): pre-existing tests matching TEST_GLOBS are locked too ------------

# locked_repo_with_old [GLOBS] -> like locked_repo, but T also contains
# tests/old.test.sh (matches TEST_GLOBS, NOT in ## Locked tests) and a
# non-matching helper tests/helper.sh
locked_repo_with_old() {
  local d
  d="$(base_repo "$@")" || return 1
  printf 'echo old regression\n' > "$d/tests/old.test.sh"
  printf 'echo helper\n' > "$d/tests/helper.sh"
  lock_it "$d"
  if grep -qF "old.test.sh" "$d/$LOCK_REL"; then
    fail "fixture: old.test.sh must not be listed"; return 1
  fi
  printf '%s\n' "$d"
}

case_A1_pass_counts_listed_plus_matched() {
  local d; d="$(locked_repo_with_old)"
  locked "$d"
  # a, b listed (and matched), old matched only, + cortex/config: 4, each
  # counted once; helper.sh does not match TEST_GLOBS
  expect_pass 4 "untouched listed + matched tests"
}

case_A1_listed_and_matched_not_double_counted() {
  local d; d="$(locked_repo)"
  locked "$d"
  expect_pass 3 "listed files that also match TEST_GLOBS count once"
}

case_A1_non_matching_helper_free() {
  local d; d="$(locked_repo_with_old)"
  printf 'echo helper v2\n' > "$d/tests/helper.sh"
  locked "$d"
  assert_exit 0 "$CODE" "a file not matching TEST_GLOBS and not listed is not locked"
}

case_A1_modified_unstaged() {
  local d; d="$(locked_repo_with_old)"
  printf 'echo weakened\n' > "$d/tests/old.test.sh"
  locked "$d"
  expect_lock modified tests/old.test.sh "unlisted pre-existing test modified, unstaged"
}

case_A1_modified_staged() {
  local d; d="$(locked_repo_with_old)"
  printf 'echo weakened\n' > "$d/tests/old.test.sh"
  git -C "$d" add tests/old.test.sh
  locked "$d"
  expect_lock modified tests/old.test.sh "unlisted pre-existing test modified, staged"
}

case_A1_modified_committed() {
  local d; d="$(locked_repo_with_old)"
  printf 'echo weakened\n' > "$d/tests/old.test.sh"
  commit_all "$d" "weaken old test"
  locked "$d"
  expect_lock modified tests/old.test.sh "unlisted pre-existing test modified, committed"
}

case_A1_deleted() {
  local d; d="$(locked_repo_with_old)"
  rm "$d/tests/old.test.sh"
  locked "$d"
  expect_lock deleted tests/old.test.sh "unlisted pre-existing test deleted"
}

case_A1_deleted_committed() {
  local d; d="$(locked_repo_with_old)"
  git -C "$d" rm -q tests/old.test.sh
  git -C "$d" commit -q -m "drop old test"
  locked "$d"
  expect_lock deleted tests/old.test.sh "unlisted pre-existing test deleted, committed"
}

case_A1_without_globs_passes() {
  local d; d="$(locked_repo_with_old "")"
  printf 'echo weakened\n' > "$d/tests/old.test.sh"
  locked "$d"
  # only the listed files (+ config) are counted
  expect_pass 3 "without TEST_GLOBS at the lock an unlisted test is not locked"
}

case_A1_placeholder_globs_passes() {
  local d; d="$(locked_repo_with_old "<test file globs>")"
  rm "$d/tests/old.test.sh"
  locked "$d"
  assert_exit 0 "$CODE" "a placeholder TEST_GLOBS counts as unset"
}

# ---- AC14 (B1, B2): lock.md can't be moved; cortex/config is locked -------------

case_B1_lock_edited_unstaged() {
  local d; d="$(locked_repo)"
  append "$d/$LOCK_REL" "- an extra note"
  locked "$d"
  expect_lock moved "" "lock.md edited, unstaged"
}

case_B1_lock_edited_staged() {
  local d; d="$(locked_repo)"
  append "$d/$LOCK_REL" "- an extra note"
  git -C "$d" add "$LOCK_REL"
  locked "$d"
  expect_lock moved "" "lock.md edited, staged"
}

case_B1_lock_edited_committed() {
  local d; d="$(locked_repo)"
  append "$d/$LOCK_REL" "- an extra note"
  commit_all "$d" "edit lock"
  locked "$d"
  expect_lock moved "" "lock.md edited, committed"
}

case_B1_second_commit_same_content() {
  local d; d="$(locked_repo)"
  cp "$d/$LOCK_REL" "$TEST_TMP/lock.orig"
  append "$d/$LOCK_REL" "- an extra note"
  commit_all "$d" "edit lock"
  cp "$TEST_TMP/lock.orig" "$d/$LOCK_REL"
  commit_all "$d" "restore lock"
  assert_true "fixture: lock.md content equals L's again" \
    test -z "$(git -C "$d" diff HEAD~2 -- "$LOCK_REL")"
  locked "$d"
  expect_lock moved "" "a second commit touching lock.md (even restoring it)"
}

case_B1_repoint_after_weakening() {
  # the reviewer's attack: weaken a test, then point the lock at the new HEAD
  local d w; d="$(locked_repo)"
  printf 'echo a weakened\n' > "$d/tests/a.test.sh"
  commit_all "$d" "weaken test"
  w="$(git -C "$d" rev-parse HEAD)"
  write_lock "$d" "$w"
  commit_all "$d" "re-lock"
  locked "$d"
  expect_lock moved "" "lock.md re-pointed at a later commit"
}

case_B1_parent_not_named_sha() {
  local d t; d="$(base_repo)"
  commit_all "$d" "add tests"
  t="$(git -C "$d" rev-parse HEAD)"
  printf 'app v2\n' > "$d/src/app.txt"
  commit_all "$d" "something between T and L"
  write_lock "$d" "$t"
  commit_all "$d" "lock tests"
  assert_true "fixture: L's parent is not T" test "$(git -C "$d" rev-parse HEAD^1)" != "$t"
  locked "$d"
  expect_lock moved "" "lock.md's commit parent is not the named sha"
}

case_B1_lock_uncommitted() {
  local d; d="$(base_repo)"
  commit_all "$d" "add tests"
  write_lock "$d" "$(git -C "$d" rev-parse HEAD)"
  locked "$d"
  expect_lock moved "" "lock.md never committed (no commit L)"
}

case_B1_trailing_note() {
  local d; d="$(base_repo "")"
  lock_it "$d" '- `tests/a.test.sh` (new)' '- tests/b.test.sh (existing, strengthened)'
  locked "$d"
  expect_pass 3 "list lines with a trailing note"
  printf 'echo a changed\n' > "$d/tests/a.test.sh"
  locked "$d"
  expect_lock modified tests/a.test.sh "backticked path with a trailing note is locked"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  printf 'echo b changed\n' > "$d/tests/b.test.sh"
  locked "$d"
  expect_lock modified tests/b.test.sh "first word of an unquoted line with a note is the path"
}

config_mod() { # msg
  expect_lock modified cortex/config "$1"
}

case_B2_config_narrowed_unstaged() {
  local d; d="$(locked_repo)"
  set_config "$d/cortex/config" TEST_GLOBS 'tests/a.test.sh'
  locked "$d"
  config_mod "TEST_GLOBS narrowed, unstaged"
}

case_B2_config_narrowed_staged() {
  local d; d="$(locked_repo)"
  set_config "$d/cortex/config" TEST_GLOBS 'tests/a.test.sh'
  git -C "$d" add cortex/config
  locked "$d"
  config_mod "TEST_GLOBS narrowed, staged"
}

case_B2_config_narrowed_committed() {
  local d; d="$(locked_repo)"
  set_config "$d/cortex/config" TEST_GLOBS 'tests/a.test.sh'
  commit_all "$d" "narrow globs"
  locked "$d"
  config_mod "TEST_GLOBS narrowed, committed"
}

case_B2_config_command_changed() {
  local d; d="$(locked_repo)"
  set_config "$d/cortex/config" TEST_CMD 'true'
  locked "$d"
  config_mod "a gate command changed"
}

case_B2_narrowing_does_not_unlock() {
  local d; d="$(locked_repo_with_old)"
  set_config "$d/cortex/config" TEST_GLOBS 'tests/a.test.sh'
  printf 'echo weakened\n' > "$d/tests/old.test.sh"
  locked "$d"
  config_mod "narrowed TEST_GLOBS"
  assert_contains "$OUT$ERR" "LOCK modified: tests/old.test.sh" "matched test still locked under the lock's TEST_GLOBS"
}

case_B2_narrowing_still_flags_added() {
  local d; d="$(locked_repo)"
  set_config "$d/cortex/config" TEST_GLOBS 'tests/a.test.sh'
  printf 'echo c\n' > "$d/tests/c.test.sh"
  locked "$d"
  config_mod "narrowed TEST_GLOBS"
  assert_contains "$OUT$ERR" "LOCK added: tests/c.test.sh" "new test flagged under the lock's TEST_GLOBS"
}

case_B2_widening_at_lock_is_used() {
  # TEST_GLOBS empty in the working tree, set at the lock: the lock's wins
  local d; d="$(locked_repo_with_old)"
  set_config "$d/cortex/config" TEST_GLOBS ''
  rm "$d/tests/old.test.sh"
  locked "$d"
  config_mod "TEST_GLOBS emptied"
  assert_contains "$OUT$ERR" "LOCK deleted: tests/old.test.sh" "deletion flagged under the lock's TEST_GLOBS"
}

case_B2_config_absent_at_lock_not_counted() {
  local d; d="$(base_repo "")"
  rm "$d/cortex/config"
  lock_it "$d"
  locked "$d"
  expect_pass 2 "config absent at the lock is not counted"
}

# ---- AC15 (B4): spaces and non-ASCII paths ---------------------------------------

SP="tests/with space.test.sh"
NA="tests/café.test.sh"
NA_OLD="tests/naïve.test.sh"   # matched by TEST_GLOBS, not listed

odd_paths_repo() {
  local d
  d="$(fresh_install)" || return 1
  set_config "$d/cortex/config" TEST_GLOBS '*.test.sh'
  mkdir -p "$d/tests" "$d/tests/sub dir"
  printf 'echo sp\n' > "$d/$SP"
  printf 'echo na\n' > "$d/$NA"
  printf 'echo old\n' > "$d/$NA_OLD"
  printf 'echo deep\n' > "$d/tests/sub dir/deep.test.sh"
  lock_it "$d" "- \`$SP\`" "- $NA"
  printf '%s\n' "$d"
}

case_B4_untouched() {
  local d; d="$(odd_paths_repo)"
  locked "$d"
  # 4 tests + cortex/config
  expect_pass 5 "spaced and non-ASCII paths, untouched"
}

case_B4_spaced_modified() {
  local d; d="$(odd_paths_repo)"
  printf 'echo changed\n' > "$d/$SP"
  locked "$d"
  expect_lock modified "$SP" "listed path with a space, edited"
}

case_B4_non_ascii_modified() {
  local d; d="$(odd_paths_repo)"
  printf 'echo changed\n' > "$d/$NA"
  git -C "$d" add -A
  locked "$d"
  expect_lock modified "$NA" "listed non-ASCII path, edited and staged"
}

case_B4_unlisted_non_ascii_modified() {
  local d; d="$(odd_paths_repo)"
  printf 'echo changed\n' > "$d/$NA_OLD"
  commit_all "$d" "weaken"
  locked "$d"
  expect_lock modified "$NA_OLD" "matched non-ASCII path, edited and committed"
}

case_B4_spaced_dir_deleted() {
  local d; d="$(odd_paths_repo)"
  rm "$d/tests/sub dir/deep.test.sh"
  locked "$d"
  expect_lock deleted "tests/sub dir/deep.test.sh" "matched path in a spaced directory, deleted"
}

case_B4_non_ascii_added() {
  local d; d="$(odd_paths_repo)"
  printf 'echo new\n' > "$d/tests/über.test.sh"
  locked "$d"
  expect_lock added "tests/über.test.sh" "new non-ASCII test"
}

# ---- AC16: CRLF lock.md and cortex/config ----------------------------------------

no_cr() { # text msg  (a bash pattern, since grep may strip CRs)
  case "$1" in *$'\r'*) fail "$2"; show_output ;; *) pass ;; esac
}

to_crlf() { filter_file "$1" awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }'; }

crlf_repo() {
  local d sha
  d="$(base_repo)" || return 1
  to_crlf "$d/cortex/config"
  commit_all "$d" "add tests"
  sha="$(git -C "$d" rev-parse HEAD)"
  write_lock "$d" "$sha"
  to_crlf "$d/$LOCK_REL"
  commit_all "$d" "lock tests"
  # (tr + cmp, not grep: Git Bash's grep strips CRs before matching)
  if tr -d '\r' < "$d/$LOCK_REL" | cmp -s - "$d/$LOCK_REL" \
    || tr -d '\r' < "$d/cortex/config" | cmp -s - "$d/cortex/config"; then
    fail "fixture: CRLF not planted"; return 1
  fi
  if [ -n "$(git -C "$d" status --porcelain)" ]; then
    fail "fixture: CRLF repo is not clean"; return 1
  fi
  printf '%s\n' "$d"
}

case_crlf_untouched() {
  local d; d="$(crlf_repo)"
  locked "$d"
  expect_pass 3 "CRLF lock.md and config parse like LF"
  no_cr "$OUT$ERR" "no carriage returns leak into output"
}

case_crlf_modified() {
  local d; d="$(crlf_repo)"
  printf 'echo b changed\n' > "$d/tests/b.test.sh"
  locked "$d"
  expect_lock modified tests/b.test.sh "CRLF lock.md: backticked path locked"
  no_cr "$OUT$ERR" "no carriage return in the reported path"
}

case_crlf_globs_added() {
  local d; d="$(crlf_repo)"
  printf 'echo c\n' > "$d/tests/c.test.sh"
  locked "$d"
  expect_lock added tests/c.test.sh "CRLF config: TEST_GLOBS still matches"
}

case_crlf_globs_unlisted() {
  local d; d="$(base_repo)"
  printf 'echo old\n' > "$d/tests/old.test.sh"
  to_crlf "$d/cortex/config"
  lock_it "$d"
  printf 'echo weakened\n' > "$d/tests/old.test.sh"
  locked "$d"
  expect_lock modified tests/old.test.sh "CRLF config: matched unlisted test locked"
}

# ---- AC65-69 (Amendment 11, M1-M3; was Amendment 4, D1): a merge is a re-lock ---
#
# Amendment 11 withdrew D1 (criteria 26-27): a merge that changes a locked file
# fails like any other edit, unless a signed re-lock names the merge commit as
# its tests commit, with lock.md committed as the very next commit (M2). A
# re-lock may not change cortex/config (M3). Rebasing still fails (AC28).

# merge_repo [no-config] -> a locked branch whose base has moved on, not yet
# merged:
#   B0 (branch "base"): installed, TEST_GLOBS=*.test.sh, tests/a.test.sh,
#     tests/b.test.sh, tests/old.test.sh (matched, unlisted), src/app.txt
#   feature (checked out): T adds src/feature.txt, L locks a and b
#   B1 on "base": edits tests/a.test.sh (listed), tests/old.test.sh (matched,
#     unlisted) and, unless "no-config" is given, cortex/config; adds
#     tests/new.test.sh (matched)
merge_repo() {
  local d cfg="${1-}"
  d="$(base_repo)" || return 1
  printf 'echo old regression\n' > "$d/tests/old.test.sh"
  commit_all "$d" "base B0"
  git -C "$d" branch base
  git -C "$d" checkout -q -b feature
  printf 'feature\n' > "$d/src/feature.txt"
  lock_it "$d"
  git -C "$d" checkout -q base
  printf 'echo a from base\n' > "$d/tests/a.test.sh"
  printf 'echo old from base\n' > "$d/tests/old.test.sh"
  [ "$cfg" = no-config ] || append "$d/cortex/config" "# base: a later config line"
  printf 'echo new from base\n' > "$d/tests/new.test.sh"
  commit_all "$d" "base B1"
  git -C "$d" checkout -q feature
  printf '%s\n' "$d"
}

# merged_repo [no-config] -> merge_repo with "base" merged into feature (no
# conflicts: the merge takes the base's version of every locked or matched
# file); no re-lock
merged_repo() {
  local d
  d="$(merge_repo "$@")" || return 1
  git -C "$d" merge -q --no-edit base
  if [ "$(git -C "$d" rev-parse HEAD^2)" != "$(git -C "$d" rev-parse base)" ]; then
    fail "fixture: HEAD is not a merge of base"; return 1
  fi
  if [ -n "$(git -C "$d" status --porcelain)" ]; then
    fail "fixture: merged repo is not clean"; return 1
  fi
  printf '%s\n' "$d"
}

# relock_merge DIR [SIGN] : M2's re-lock of a merge: lock.md naming HEAD (the
# merge, as the re-lock's tests commit), with SIGN (default SIGNED, as
# write_relock) and write_lock's default list (a and b), committed as the very
# next commit
relock_merge() {
  local d="$1" sign="${2-$SIGNED}" m
  m="$(git -C "$d" rev-parse HEAD)"
  write_relock "$d" "$m" "$sign" || return 1
  commit_all "$d" "re-lock after merging the base"
}

# relocked_merge_repo -> merged_repo no-config, re-locked as M2 says: HEAD is
# L2, HEAD~1 the merge. Locked at the merge: a, b (listed), old and new
# (matched) and cortex/config: 5 files.
relocked_merge_repo() {
  local d
  d="$(merged_repo no-config)" || return 1
  relock_merge "$d" || return 1
  printf '%s\n' "$d"
}

# expect_merge_failures msg : the failures merged_repo (with the config) plants
expect_merge_failures() {
  expect_lock modified tests/a.test.sh "$1"
  assert_contains "$OUT$ERR" "LOCK modified: tests/old.test.sh" "$1: matched test the merge changed"
  assert_contains "$OUT$ERR" "LOCK modified: cortex/config" "$1: config the merge changed"
  assert_contains "$OUT$ERR" "LOCK added: tests/new.test.sh" "$1: matched test the merge added"
}

case_M1_merge_base_fails() {
  # replaces AC26's "merge of the base passes" (withdrawn): with no re-lock,
  # the base's versions are edits like any other (AC65)
  local d sha; d="$(merged_repo)"; sha="$(git -C "$d" rev-parse 'HEAD^1~1')"
  assert_true "fixture: the lock names T" \
    grep -qF "Tests-locked-at: $sha" "$d/$LOCK_REL"
  assert_file_contains "$d/tests/a.test.sh" "echo a from base" "fixture: merge took base's listed test"
  assert_file_contains "$d/tests/old.test.sh" "echo old from base" "fixture: merge took base's matched test"
  assert_file_contains "$d/cortex/config" "# base: a later config line" "fixture: merge took base's config"
  assert_file_exists "$d/tests/new.test.sh" "fixture: merge brought base's new test"
  locked "$d"
  expect_merge_failures "merge of the base, no re-lock"
}

case_M2_merge_relock_passes() {
  # AC66: the merge is the re-lock's tests commit; a signed lock.md naming it
  # is the very next commit
  local d m; d="$(relocked_merge_repo)"; m="$(git -C "$d" rev-parse HEAD~1)"
  assert_true "fixture: the re-lock's tests commit is a merge of base" \
    test "$(git -C "$d" rev-parse HEAD~1^2)" = "$(git -C "$d" rev-parse base)"
  assert_true "fixture: L2's first parent is the merge" test "$(git -C "$d" rev-parse HEAD^1)" = "$m"
  assert_file_contains "$d/$LOCK_REL" "Tests-locked-at: $m" "fixture: lock.md names the merge"
  assert_true "fixture: the merge changed a listed test" \
    test -n "$(git -C "$d" diff HEAD~2 HEAD~1 -- tests/a.test.sh)"
  assert_true "fixture: the merge left the config as locked" \
    test -z "$(git -C "$d" diff HEAD~2 HEAD~1 -- cortex/config)"
  locked "$d"
  # a, b listed; old, new matched at the merge; cortex/config
  expect_pass 5 "merge of the base, then a signed re-lock naming it"
  assert_contains "$OUT" "since $(short "$m")" "merge + re-lock: success line names the merge commit"
}

case_M2_merge_relock_then_implementation() {
  local d; d="$(relocked_merge_repo)"
  printf 'app v2\n' > "$d/src/app.txt"
  commit_all "$d" "implementation after the merge and re-lock"
  locked "$d"
  assert_exit 0 "$CODE" "implementation commits after a re-locked base merge still pass"
  assert_not_contains "$OUT$ERR" "LOCK " "no LOCK lines"
}

case_M2_unsigned_merge_relock() {
  local d; d="$(merged_repo no-config)"
  relock_merge "$d" -
  locked "$d"
  expect_lock moved "" "merge of the base, then an unsigned re-lock"
}

case_D1_edit_after_merge_committed() {
  local d; d="$(relocked_merge_repo)"
  printf 'echo a weakened\n' > "$d/tests/a.test.sh"
  commit_all "$d" "weaken after merge"
  locked "$d"
  expect_lock modified tests/a.test.sh "listed test edited on top of a re-locked base merge"
}

case_D1_edit_after_merge_unstaged() {
  local d; d="$(relocked_merge_repo)"
  printf 'echo old weakened\n' > "$d/tests/old.test.sh"
  locked "$d"
  expect_lock modified tests/old.test.sh "matched test edited (unstaged) on top of a re-locked base merge"
}

case_D1_edit_after_merge_staged() {
  local d; d="$(relocked_merge_repo)"
  printf 'echo a weakened\n' > "$d/tests/a.test.sh"
  git -C "$d" add tests/a.test.sh
  locked "$d"
  expect_lock modified tests/a.test.sh "listed test edited (staged) on top of a re-locked base merge"
}

case_D1_config_edit_after_merge() {
  local d; d="$(relocked_merge_repo)"
  set_config "$d/cortex/config" TEST_GLOBS 'tests/a.test.sh'
  commit_all "$d" "narrow globs after merge"
  locked "$d"
  expect_lock modified cortex/config "config edited on top of a re-locked base merge"
}

case_D1_new_test_edit_after_merge() {
  # the base's new test exists at the merge, the re-lock's sha, so it is
  # locked there (matched by TEST_GLOBS): an edit is LOCK modified
  local d; d="$(relocked_merge_repo)"
  printf 'echo new weakened\n' > "$d/tests/new.test.sh"
  commit_all "$d" "edit the base's new test"
  locked "$d"
  expect_lock modified tests/new.test.sh "base's new test edited on the branch after a re-locked merge"
}

case_D1_added_after_merge() {
  local d; d="$(relocked_merge_repo)"
  printf 'echo c\n' > "$d/tests/c.test.sh"
  locked "$d"
  expect_lock added tests/c.test.sh "a test not on the base, added after a re-locked base merge"
}

# merge_resolving DIR PATH CONTENT : merge base into feature, but commit the
# merge with PATH resolved to CONTENT (neither the sha's nor the base's)
merge_resolving() {
  git -C "$1" merge -q --no-commit --no-ff base >/dev/null 2>&1
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add -- "$2"
  git -C "$1" commit -q --no-edit
}

case_D1_merge_resolved_to_neither() {
  local d; d="$(merge_repo)"
  merge_resolving "$d" tests/a.test.sh 'echo a from neither'
  assert_true "fixture: HEAD is a merge of base" \
    test "$(git -C "$d" rev-parse HEAD^2)" = "$(git -C "$d" rev-parse base)"
  locked "$d"
  expect_lock modified tests/a.test.sh "merge resolving a listed test to neither side"
}

case_D1_merge_resolved_to_neither_matched() {
  local d; d="$(merge_repo)"
  merge_resolving "$d" tests/old.test.sh 'echo old from neither'
  locked "$d"
  expect_lock modified tests/old.test.sh "merge resolving a matched test to neither side"
}

case_D1_merge_resolved_config_to_neither() {
  local d; d="$(merge_repo)"
  git -C "$d" merge -q --no-commit --no-ff base >/dev/null 2>&1
  set_config "$d/cortex/config" TEST_GLOBS 'tests/a.test.sh'
  git -C "$d" add cortex/config
  git -C "$d" commit -q --no-edit
  locked "$d"
  expect_lock modified cortex/config "merge resolving the config to neither side"
}

case_D1_rebase_onto_moved_base() {
  local d; d="$(merge_repo)"
  git -C "$d" rebase -q base
  assert_true "fixture: base is now an ancestor of HEAD" git -C "$d" merge-base --is-ancestor base HEAD
  locked "$d"
  assert_exit 1 "$CODE" "rebase onto a moved base: exits 1"
  if grep -qE 'LOCK (bad-sha|moved):' <<<"$OUT$ERR"; then pass
  else fail "rebase onto a moved base: reports LOCK bad-sha or LOCK moved"; show_output; fi
  assert_not_contains "$OUT" "tests-locked: " "rebase onto a moved base: no success line"
}

case_M1_merge_takes_base_older_copy() {
  # AC67: T strengthens tests/a.test.sh; the base never touches it but moves
  # on elsewhere; the merge is resolved by taking the base's (older) copy
  local d; d="$(base_repo)"
  commit_all "$d" "base B0"
  git -C "$d" branch base
  git -C "$d" checkout -q -b feature
  printf 'echo a strengthened\n' > "$d/tests/a.test.sh"
  lock_it "$d"
  git -C "$d" checkout -q base
  printf 'app from base\n' > "$d/src/app.txt"
  commit_all "$d" "base B1: no test touched"
  git -C "$d" checkout -q feature
  git -C "$d" merge -q --no-commit --no-ff base >/dev/null 2>&1 || true
  git -C "$d" checkout -q base -- tests/a.test.sh
  git -C "$d" commit -q --no-edit
  assert_true "fixture: HEAD is a merge of base" \
    test "$(git -C "$d" rev-parse HEAD^2)" = "$(git -C "$d" rev-parse base)"
  assert_true "fixture: the base never changed tests/a.test.sh" \
    git -C "$d" diff --quiet base~1 base -- tests/a.test.sh
  assert_true "fixture: the merge took the base's copy" \
    git -C "$d" diff --quiet base HEAD -- tests/a.test.sh
  assert_true "fixture: working tree clean" test -z "$(git -C "$d" status --porcelain)"
  locked "$d"
  expect_lock modified tests/a.test.sh "merge resolved to the base's older copy of a locked test"
}

# fabricated_merge_repo -> B0 on "base"; feature: T strengthens
# tests/a.test.sh, L locks a and b; then a merge commit made by hand whose
# second parent is the fork point (B0) and whose tree restores
# tests/a.test.sh to its pre-lock (B0) content
fabricated_merge_repo() {
  local d tree c
  d="$(base_repo)" || return 1
  commit_all "$d" "base B0"
  git -C "$d" branch base
  git -C "$d" checkout -q -b feature
  printf 'echo a strengthened\n' > "$d/tests/a.test.sh"
  lock_it "$d"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  git -C "$d" add tests/a.test.sh
  tree="$(git -C "$d" write-tree)"
  c="$(git -C "$d" commit-tree "$tree" -p HEAD -p base -m "merge base")"
  git -C "$d" reset -q "$c"
  printf '%s\n' "$d"
}

fabricated_merge_fixture() {
  assert_true "fixture: HEAD's second parent is base" \
    test "$(git -C "$1" rev-parse HEAD^2)" = "$(git -C "$1" rev-parse base)"
  assert_true "fixture: base is the fork point" \
    test "$(git -C "$1" merge-base HEAD^1 base)" = "$(git -C "$1" rev-parse base)"
  assert_true "fixture: tests/a.test.sh restored to its pre-lock content" \
    git -C "$1" diff --quiet base HEAD -- tests/a.test.sh
  assert_true "fixture: working tree clean" test -z "$(git -C "$1" status --porcelain)"
}

case_M1_fabricated_merge() {
  local d; d="$(fabricated_merge_repo)"
  fabricated_merge_fixture "$d"
  locked "$d"
  expect_lock modified tests/a.test.sh "fabricated merge of the fork point restoring a locked test"
}

case_M1_fabricated_merge_with_base_ref() {
  local d; d="$(fabricated_merge_repo)"
  fabricated_merge_fixture "$d"
  locked_with_base "$d" base
  expect_lock modified tests/a.test.sh "fabricated merge of the fork point, CORTEX_BASE_REF=base"
}

case_M3_relock_narrows_globs() {
  # AC69: T2 narrows TEST_GLOBS (and fixes a listed test); a signed L2 names T2
  local d; d="$(locked_repo)"
  set_config "$d/cortex/config" TEST_GLOBS 'tests/a.test.sh'
  printf 'echo a fixed\n' > "$d/tests/a.test.sh"
  relock_it "$d" "$SIGNED"
  assert_true "fixture: T2 changes the config" \
    test -n "$(git -C "$d" diff HEAD~2 HEAD~1 -- cortex/config)"
  locked "$d"
  expect_lock modified cortex/config "signed re-lock whose tests commit narrows TEST_GLOBS"
  assert_not_contains "$OUT$ERR" "LOCK moved" "narrowing re-lock: the re-lock itself is well formed"
}

case_M3_relock_widens_globs() {
  # the Amendment 9 fixture that widened TEST_GLOBS in T2: now refused (M3)
  local d; d="$(relocked_repo "$SIGNED" widen)"
  assert_true "fixture: T2 changes the config" \
    test -n "$(git -C "$d" diff HEAD~2 HEAD~1 -- cortex/config)"
  locked "$d"
  expect_lock modified cortex/config "signed re-lock whose tests commit widens TEST_GLOBS"
}

case_M3_merge_relock_with_config() {
  # AC66 applied to AC65's merge that also changed the config: the re-lock's
  # tests commit (the merge) changes cortex/config, which M3 refuses; the
  # test files the merge changed are blessed by the sign-off
  local d; d="$(merged_repo)"
  relock_merge "$d"
  assert_true "fixture: the merge changed the config" \
    test -n "$(git -C "$d" diff HEAD~2 HEAD~1 -- cortex/config)"
  locked "$d"
  expect_lock modified cortex/config "re-locked merge of a base that changed the config"
  assert_not_contains "$OUT$ERR" "LOCK modified: tests/a.test.sh" "re-locked merge with config: listed test blessed"
  assert_not_contains "$OUT$ERR" "LOCK added: tests/new.test.sh" "re-locked merge with config: new test blessed"
}

# ---- AC32/AC34 (Amendment 6, F1/F2): one config parser --------------------------

# ac32_locked KIND : TEST_GLOBS at the lock written per KIND (real *.test.sh,
# other *.spec.sh); a new *.test.sh is added, a new *.spec.sh is not
ac32_locked() {
  local kind="$1" d; d="$(base_repo)"
  config_variant "$d/cortex/config" "$kind" TEST_GLOBS '*.test.sh' '*.spec.sh'
  lock_it "$d"
  printf 'echo c\n' > "$d/tests/c.test.sh"
  printf 'echo d\n' > "$d/tests/d.spec.sh"
  locked "$d"
  expect_lock added tests/c.test.sh "$kind: the real TEST_GLOBS"
  assert_not_contains "$OUT$ERR" "LOCK added: tests/d.spec.sh" "$kind: the other value is not read as TEST_GLOBS"
}

case_AC32_spaced() { ac32_locked spaced; }
case_AC32_comment() { ac32_locked comment; }
case_AC32_no_equals() { ac32_locked no-equals; }
case_AC32_twice() { ac32_locked twice; }

case_AC34_stub_parser() {
  local d; d="$(locked_repo)"
  write_stub_parser "$d"
  printf 'echo c\n' > "$d/tests/c.test.sh"
  locked "$d"
  assert_not_contains "$OUT$ERR" "LOCK added: tests/c.test.sh" "tests-locked.sh reads TEST_GLOBS through _config.sh"
  assert_exit 0 "$CODE" "nothing else is broken -> exit 0"
}

# ---- AC37 (Amendment 7): staged edit, working tree restored -----------------------

# ac37_check PATH LIST-LINE... : lock (with LIST-LINEs), stage an edit to PATH,
# then restore PATH's working-tree copy to its locked content
ac37_check() {
  local d p="$1"; shift
  d="$(base_repo)" || return 1
  lock_it "$d" "$@"
  cp "$d/$p" "$TEST_TMP/ac37.orig"
  printf 'echo weakened\n' > "$d/$p"
  git -C "$d" add "$p"
  cp "$TEST_TMP/ac37.orig" "$d/$p"
  assert_true "fixture: working tree matches the lock" \
    test "$(git -C "$d" show "HEAD~1:$p")" = "$(cat "$d/$p")"
  assert_true "fixture: index holds the edited copy" \
    test "$(git -C "$d" show ":$p")" = "echo weakened"
  locked "$d"
  expect_lock modified "$p" "staged edit, working tree restored"
}

case_AC37_listed() { ac37_check tests/a.test.sh; }
case_AC37_glob_only() { ac37_check tests/b.test.sh '- tests/a.test.sh'; }

# ---- AC50-55 (Amendment 9, K1/K2): a signed re-lock -------------------------------
#
# A re-lock: after T1 and L1 (as above) and further commits, the test writer
# commits test edits (T2), then rewrites lock.md naming T2 in its own commit L2,
# with a "Re-lock signed off by: <text>" line.

SIGNED="Re-lock signed off by: Pat Maintainer"
SIGN_RE='^Re-lock signed off by:'
RELOCK_LIST=('- tests/a.test.sh' '- `tests/b.test.sh`' '- tests/c.test.sh (new at the re-lock)')

short() { printf '%s' "$1" | cut -c1-7; }

# lock_commit_count DIR -> number of commits touching lock.md
lock_commit_count() { git -C "$1" log --format=%H -- "$LOCK_REL" | grep -c . || true; }

# first_lock_sha DIR -> T1, the sha the oldest lock commit names (its parent)
first_lock_sha() {
  git -C "$1" rev-parse "$(git -C "$1" log --reverse --format=%H -- "$LOCK_REL" | sed -n 1p)^1"
}

# write_relock DIR SHA SIGN [LIST-LINE...] : write_lock, plus the line SIGN
# right after Tests-locked-at ("-" writes no sign-off line)
write_relock() {
  local d="$1" sha="$2" sign="$3"; shift 3
  write_lock "$d" "$sha" "$@"
  if [ "$sign" != "-" ]; then
    filter_file "$d/$LOCK_REL" awk -v s="$sign" '{ print } /^Tests-locked-at:/ { print s }'
    grep -qxF -- "$sign" "$d/$LOCK_REL" || { fail "fixture: sign-off not planted: $sign"; return 1; }
  elif grep -q "$SIGN_RE" "$d/$LOCK_REL"; then
    fail "fixture: unexpected sign-off line"; return 1
  fi
}

# relock_it DIR SIGN [LIST-LINE...] : commit everything as T2, then lock.md
# naming T2 (with SIGN, as write_relock) as its own commit L2
relock_it() {
  local d="$1" sign="$2" sha; shift 2
  commit_all "$d" "re-lock: test edits"
  sha="$(git -C "$d" rev-parse HEAD)"
  write_relock "$d" "$sha" "$sign" "$@"
  commit_all "$d" "re-lock tests"
}

# prelock_repo [widen] -> T1 and L1, a further commit, and T2's edits left
# uncommitted:
#   T1: TEST_GLOBS=*.test.sh, tests/a.test.sh, tests/b.test.sh,
#       tests/old.test.sh (matched, unlisted), src/app.txt; L1 lists a and b
#   after L1: an implementation commit (no locked file touched)
#   uncommitted (T2's edits): tests/old.test.sh reworked, tests/a.test.sh
#       fixed, tests/c.test.sh added; with "widen", also TEST_GLOBS widened
#       to "*.test.sh *.spec.sh" and tests/y.spec.sh added
# Every locked file changes in T2 itself, the only changes a re-lock blesses
# (Amendment 10, L1); changes between L1 and T2 are AC57's failing cases. A
# re-lock may not change the config (Amendment 11, M3), so "widen" builds
# AC69's failing case.
prelock_repo() {
  local d
  d="$(base_repo)" || return 1
  printf 'echo old regression\n' > "$d/tests/old.test.sh"
  lock_it "$d"
  printf 'app v2\n' > "$d/src/app.txt"
  commit_all "$d" "implementation"
  if [ "${1-}" = widen ]; then
    set_config "$d/cortex/config" TEST_GLOBS '*.test.sh *.spec.sh'
    printf 'echo y\n' > "$d/tests/y.spec.sh"
  fi
  printf 'echo old reworked\n' > "$d/tests/old.test.sh"
  printf 'echo a fixed\n' > "$d/tests/a.test.sh"
  printf 'echo c\n' > "$d/tests/c.test.sh"
  printf '%s\n' "$d"
}

# relocked_repo [SIGN [widen]] -> prelock_repo [widen], re-locked with
# RELOCK_LIST and SIGN (default SIGNED): HEAD is L2, HEAD~1 is T2. Without
# "widen", locked at T2: a, b, c (listed), old (matched) and cortex/config:
# 5 files.
relocked_repo() {
  local d sign="${1-$SIGNED}"
  d="$(prelock_repo "${2-}")" || return 1
  relock_it "$d" "$sign" "${RELOCK_LIST[@]}"
  if [ "$(lock_commit_count "$d")" != 2 ]; then
    fail "fixture: expected two lock commits"; return 1
  fi
  printf '%s\n' "$d"
}

case_K1_signed_relock_minimal() {
  local d t2; d="$(locked_repo)"
  printf 'app v2\n' > "$d/src/app.txt"
  commit_all "$d" "implementation"
  printf 'echo a fixed\n' > "$d/tests/a.test.sh"
  relock_it "$d" "$SIGNED"
  t2="$(git -C "$d" rev-parse HEAD~1)"
  assert_true "fixture: two commits touch lock.md" test "$(lock_commit_count "$d")" = 2
  assert_true "fixture: L2's first parent is T2" test "$(git -C "$d" rev-parse HEAD^1)" = "$t2"
  assert_file_contains "$d/$LOCK_REL" "Tests-locked-at: $t2" "fixture: lock.md names T2"
  locked "$d"
  expect_pass 3 "signed re-lock"
  assert_contains "$OUT" "since $(short "$t2")" "signed re-lock: success line names T2's short sha"
}

case_K1_signed_relock_passes() {
  local d t2; d="$(relocked_repo)"; t2="$(git -C "$d" rev-parse HEAD~1)"
  assert_true "fixture: L2's first parent is T2" test "$(git -C "$d" rev-parse HEAD^1)" = "$t2"
  assert_file_contains "$d/$LOCK_REL" "Tests-locked-at: $t2" "fixture: lock.md names T2"
  locked "$d"
  # a, b, c listed; old matched at T2; cortex/config
  expect_pass 5 "signed re-lock with new and matched tests"
  assert_contains "$OUT" "since $(short "$t2")" "success line names T2's short sha"
}

# unsigned SIGN msg : the re-lock of case_K1_signed_relock_passes, but with SIGN
unsigned() {
  local d; d="$(relocked_repo "$1")"
  locked "$d"
  expect_lock moved "" "$2"
}

case_K1_unsigned_no_line() { unsigned - "re-lock without a sign-off line"; }
case_K1_unsigned_empty() { unsigned "Re-lock signed off by:" "re-lock with an empty sign-off"; }
case_K1_unsigned_blank() { unsigned "Re-lock signed off by:   " "re-lock with a blank sign-off"; }
case_K1_unsigned_placeholder() { unsigned "Re-lock signed off by: <name>" "re-lock with a <name> placeholder"; }

case_K1_relock_parent_not_named_sha() {
  local d t2; d="$(prelock_repo)"
  commit_all "$d" "re-lock: test edits"
  t2="$(git -C "$d" rev-parse HEAD)"
  printf 'app v3\n' > "$d/src/app.txt"
  commit_all "$d" "something between T2 and L2"
  write_relock "$d" "$t2" "$SIGNED" "${RELOCK_LIST[@]}"
  commit_all "$d" "re-lock tests"
  assert_true "fixture: L2's parent is not T2" test "$(git -C "$d" rev-parse HEAD^1)" != "$t2"
  locked "$d"
  expect_lock moved "" "signed re-lock whose parent is not the named sha"
}

case_K1_signoff_removed_later() {
  local d; d="$(relocked_repo)"
  filter_file "$d/$LOCK_REL" awk -v re="$SIGN_RE" '$0 !~ re'
  assert_file_not_contains "$d/$LOCK_REL" "Re-lock signed off by" "fixture: sign-off removed"
  commit_all "$d" "drop the sign-off"
  locked "$d"
  expect_lock moved "" "sign-off removed in a later commit"
}

case_K1_lock_edited_after_relock_committed() {
  local d; d="$(relocked_repo)"
  append "$d/$LOCK_REL" "- an extra note"
  commit_all "$d" "edit lock"
  locked "$d"
  expect_lock moved "" "lock.md edited in a later commit, sign-off kept"
}

case_K1_lock_edited_after_relock_unstaged() {
  local d; d="$(relocked_repo)"
  append "$d/$LOCK_REL" "- an extra note"
  locked "$d"
  expect_lock moved "" "lock.md edited after a re-lock, unstaged"
}

case_K1_third_lock_unsigned() {
  # well placed (its parent is the T3 it names) but unsigned
  local d; d="$(relocked_repo)"
  printf 'echo b fixed\n' > "$d/tests/b.test.sh"
  relock_it "$d" - "${RELOCK_LIST[@]}"
  assert_true "fixture: three commits touch lock.md" test "$(lock_commit_count "$d")" = 3
  locked "$d"
  expect_lock moved "" "a third lock commit without a sign-off"
}

case_K2_changed_in_t2_passes() {
  # AC57's last sentence (Amendment 10 replaced AC54's third clause): a file
  # changed in T2 itself is accepted. The changes before T2 that this case
  # used to bless are now AC57's failing cases (case_L1_*_before_t2).
  local d t1; d="$(relocked_repo)"; t1="$(first_lock_sha "$d")"
  assert_true "fixture: no locked file changed between T1 and T2's parent" \
    test -z "$(git -C "$d" diff "$t1" HEAD~2 -- tests cortex/config)"
  assert_true "fixture: T2 changes a listed test" \
    test -n "$(git -C "$d" diff HEAD~2 HEAD~1 -- tests/a.test.sh)"
  assert_true "fixture: T2 changes a matched test" \
    test -n "$(git -C "$d" diff HEAD~2 HEAD~1 -- tests/old.test.sh)"
  # Amendment 11, M3: a re-lock may not change the config (AC69's case)
  assert_true "fixture: T2 leaves the config as locked" \
    test -z "$(git -C "$d" diff HEAD~2 HEAD~1 -- cortex/config)"
  locked "$d"
  expect_pass 5 "files changed in T2 itself, locked again at T2"
}

case_K2_new_listed_modified() {
  local d; d="$(relocked_repo)"
  printf 'echo c weakened\n' > "$d/tests/c.test.sh"
  commit_all "$d" "weaken c"
  locked "$d"
  expect_lock modified tests/c.test.sh "test first listed in L2, edited and committed"
}

case_K2_listed_modified_unstaged() {
  local d; d="$(relocked_repo)"
  printf 'echo a weakened\n' > "$d/tests/a.test.sh"
  locked "$d"
  expect_lock modified tests/a.test.sh "test listed in L2, edited (unstaged)"
}

case_K2_matched_modified_staged() {
  local d; d="$(relocked_repo)"
  printf 'echo old weakened\n' > "$d/tests/old.test.sh"
  git -C "$d" add tests/old.test.sh
  locked "$d"
  expect_lock modified tests/old.test.sh "unlisted test matching TEST_GLOBS at T2, edited (staged)"
}

case_K2_added_after_t2() {
  local d; d="$(relocked_repo)"
  printf 'echo e\n' > "$d/tests/e.test.sh"
  commit_all "$d" "add e"
  locked "$d"
  expect_lock added tests/e.test.sh "new test added after T2"
}

case_K2_config_modified() {
  local d; d="$(relocked_repo)"
  set_config "$d/cortex/config" TEST_GLOBS 'tests/a.test.sh'
  commit_all "$d" "narrow globs after the re-lock"
  locked "$d"
  expect_lock modified cortex/config "config edited after the re-lock"
}

# relock_merge_repo -> like merge_repo (base "base", branch "feature"), with a
# signed re-lock on feature before the base moves: T1/L1 lock a and b; T2 fixes
# tests/a.test.sh; then B1 on base edits tests/b.test.sh (listed) and
# tests/old.test.sh (matched), and adds tests/new.test.sh (the config is left
# alone, so a re-lock of the merge can pass: Amendment 11, M3)
relock_merge_repo() {
  local d
  d="$(base_repo)" || return 1
  printf 'echo old regression\n' > "$d/tests/old.test.sh"
  commit_all "$d" "base B0"
  git -C "$d" branch base
  git -C "$d" checkout -q -b feature
  printf 'feature\n' > "$d/src/feature.txt"
  lock_it "$d"
  printf 'app v2\n' > "$d/src/app.txt"
  commit_all "$d" "implementation"
  printf 'echo a fixed\n' > "$d/tests/a.test.sh"
  relock_it "$d" "$SIGNED"
  git -C "$d" checkout -q base
  printf 'echo b from base\n' > "$d/tests/b.test.sh"
  printf 'echo old from base\n' > "$d/tests/old.test.sh"
  printf 'echo new from base\n' > "$d/tests/new.test.sh"
  commit_all "$d" "base B1"
  git -C "$d" checkout -q feature
  printf '%s\n' "$d"
}

case_K2_merge_after_relock_fails() {
  # was AC55's "merge after a re-lock passes" (Amendment 4's allowance,
  # withdrawn by Amendment 11): without its own re-lock, the merge fails
  local d; d="$(relock_merge_repo)"
  git -C "$d" merge -q --no-edit base
  assert_true "fixture: HEAD is a merge of base" \
    test "$(git -C "$d" rev-parse HEAD^2)" = "$(git -C "$d" rev-parse base)"
  assert_true "fixture: merged repo is clean" test -z "$(git -C "$d" status --porcelain)"
  assert_file_contains "$d/tests/b.test.sh" "echo b from base" "fixture: merge took base's listed test"
  assert_file_contains "$d/tests/a.test.sh" "echo a fixed" "fixture: T2's fix kept"
  locked "$d"
  expect_lock modified tests/b.test.sh "merge of the base after a re-lock, not re-locked"
  assert_contains "$OUT$ERR" "LOCK modified: tests/old.test.sh" "merge after a re-lock: matched test"
  assert_contains "$OUT$ERR" "LOCK added: tests/new.test.sh" "merge after a re-lock: added test"
}

case_K2_merge_after_relock_relocked_passes() {
  # a second re-lock, naming the merge (Amendment 11, M2)
  local d m; d="$(relock_merge_repo)"
  git -C "$d" merge -q --no-edit base
  m="$(git -C "$d" rev-parse HEAD)"
  relock_merge "$d"
  assert_true "fixture: three lock commits" test "$(lock_commit_count "$d")" = 3
  locked "$d"
  # a, b listed; old, new matched at the merge; cortex/config
  expect_pass 5 "merge of the base after a re-lock, re-locked again"
  assert_contains "$OUT" "since $(short "$m")" "second re-lock: success line names the merge commit"
}

case_K2_edit_after_relock_merge() {
  local d; d="$(relock_merge_repo)"
  git -C "$d" merge -q --no-edit base
  relock_merge "$d"
  printf 'echo b weakened\n' > "$d/tests/b.test.sh"
  commit_all "$d" "weaken after merge"
  locked "$d"
  expect_lock modified tests/b.test.sh "listed test edited on top of a merge after the re-lock"
}

case_K2_merge_before_t2_not_accepted() {
  # a merge before T2 is not one "after that sha": restoring the base's
  # version it brought in, over T2's, is an edit
  local d; d="$(base_repo)"
  commit_all "$d" "base B0"
  git -C "$d" branch base
  git -C "$d" checkout -q -b feature
  printf 'feature\n' > "$d/src/feature.txt"
  lock_it "$d"
  git -C "$d" checkout -q base
  printf 'echo b from base\n' > "$d/tests/b.test.sh"
  commit_all "$d" "base B1"
  git -C "$d" checkout -q feature
  git -C "$d" merge -q --no-edit base
  printf 'echo b fixed\n' > "$d/tests/b.test.sh"
  relock_it "$d" "$SIGNED"
  printf 'echo b from base\n' > "$d/tests/b.test.sh"
  commit_all "$d" "back to the base's b"
  locked "$d"
  expect_lock modified tests/b.test.sh "base version from a merge before T2"
}

case_K1_single_lock_with_signoff() {
  # AC56: a single lock commit passes with a sign-off line too
  local d sha; d="$(base_repo)"
  commit_all "$d" "add tests"
  sha="$(git -C "$d" rev-parse HEAD)"
  write_relock "$d" "$sha" "$SIGNED"
  commit_all "$d" "lock tests"
  locked "$d"
  expect_pass 3 "single lock commit with a sign-off line"
}

# ---- AC57-64 (Amendment 10, L1-L4): the lock's merge and re-lock holes ---------
#
# Amendment 10 wins over Amendment 9 where they conflict. CORTEX_BASE_REF (L3)
# is set only where a case says so; a value inherited from the caller's
# environment must not leak into the other cases.
unset CORTEX_BASE_REF

# locked_with_base DIR REF : tests-locked.sh on cortex/changes/x with CORTEX_BASE_REF=REF
locked_with_base() {
  run bash -c 'cd "$1" && CORTEX_BASE_REF="$2" ./cortex/bin/tests-locked.sh cortex/changes/x' _ "$1" "$2"
}

# before_t2_repo EDIT-FN -> T1 (base_repo plus tests/old.test.sh, matched and
# unlisted) and L1 locking a and b; an implementation commit; a commit of what
# EDIT-FN DIR changes (after L1, before T2); then T2, which fixes only
# tests/b.test.sh, and a signed L2 naming T2 and listing a and b
before_t2_repo() {
  local d edit="$1"
  d="$(base_repo)" || return 1
  printf 'echo old regression\n' > "$d/tests/old.test.sh"
  lock_it "$d"
  printf 'app v2\n' > "$d/src/app.txt"
  commit_all "$d" "implementation"
  "$edit" "$d"
  commit_all "$d" "edit after L1, before T2"
  printf 'echo b fixed\n' > "$d/tests/b.test.sh"
  relock_it "$d" "$SIGNED"
  if [ "$(lock_commit_count "$d")" != 2 ]; then
    fail "fixture: expected two lock commits"; return 1
  fi
  printf '%s\n' "$d"
}

edit_listed() { printf 'echo a weakened\n' > "$1/tests/a.test.sh"; }
edit_matched() { printf 'echo old weakened\n' > "$1/tests/old.test.sh"; }
edit_config() { append "$1/cortex/config" "# edited after L1, before T2"; }
add_matched() { printf 'echo e\n' > "$1/tests/e.test.sh"; }

# before_t2_case EDIT-FN KIND PATH msg : after the signed re-lock, PATH (left
# untouched by T2) is reported as LOCK KIND; T2's own change is accepted
before_t2_case() {
  local d; d="$(before_t2_repo "$1")"
  assert_true "fixture: T2 does not touch $3" \
    test -z "$(git -C "$d" diff HEAD~2 HEAD~1 -- "$3")"
  assert_true "fixture: $3 changed after T1" \
    test -n "$(git -C "$d" diff "$(first_lock_sha "$d")" HEAD -- "$3")"
  locked "$d"
  expect_lock "$2" "$3" "$4"
  assert_not_contains "$OUT$ERR" "LOCK modified: tests/b.test.sh" "$4: T2's own change is accepted"
  assert_not_contains "$OUT$ERR" "LOCK moved" "$4: the signed re-lock itself is well formed"
}

case_L1_listed_before_t2() {
  before_t2_case edit_listed modified tests/a.test.sh "listed test edited after L1, before T2"
}
case_L1_matched_before_t2() {
  before_t2_case edit_matched modified tests/old.test.sh "matched test edited after L1, before T2"
}
case_L1_config_before_t2() {
  before_t2_case edit_config modified cortex/config "config edited after L1, before T2"
}
case_L1_added_before_t2() {
  before_t2_case add_matched added tests/e.test.sh "matched test added after L1, before T2"
}

# side_lock_repo SIGN -> T1 (base_repo committed) on branch "feature" with L1
# locking a and b; branch "side" from T1 weakens tests/a.test.sh (Ts) and
# commits a lock.md naming Ts (Ls, with SIGN as write_relock); "side" is then
# merged into feature, the add/add conflict on lock.md resolved to side's
side_lock_repo() {
  local d sign="$1" t1 ts
  d="$(base_repo)" || return 1
  git -C "$d" checkout -q -b feature
  commit_all "$d" "add tests"
  t1="$(git -C "$d" rev-parse HEAD)"
  git -C "$d" branch side
  write_lock "$d" "$t1"
  commit_all "$d" "lock tests"
  git -C "$d" checkout -q side
  printf 'echo a weakened on side\n' > "$d/tests/a.test.sh"
  commit_all "$d" "side: weaken a"
  ts="$(git -C "$d" rev-parse HEAD)"
  write_relock "$d" "$ts" "$sign"
  commit_all "$d" "side: lock"
  git -C "$d" checkout -q feature
  git -C "$d" merge -q --no-ff --no-edit side >/dev/null 2>&1 || true
  if git -C "$d" rev-parse -q --verify MERGE_HEAD >/dev/null; then
    git -C "$d" checkout -q --theirs -- "$LOCK_REL"
    git -C "$d" add -- "$LOCK_REL"
    git -C "$d" commit -q --no-edit
  fi
  printf '%s\n' "$d"
}

side_lock_case() { # SIGN msg
  local d; d="$(side_lock_repo "$1")"
  assert_true "fixture: HEAD is a merge of side" \
    test "$(git -C "$d" rev-parse HEAD^2)" = "$(git -C "$d" rev-parse side)"
  assert_true "fixture: the merge took side's lock.md" \
    git -C "$d" diff --quiet side HEAD -- "$LOCK_REL"
  assert_true "fixture: the merge's lock.md differs from its first parent's" \
    test -n "$(git -C "$d" diff HEAD^1 HEAD -- "$LOCK_REL")"
  assert_file_contains "$d/tests/a.test.sh" "echo a weakened on side" "fixture: the merge took side's test"
  assert_true "fixture: working tree clean" test -z "$(git -C "$d" status --porcelain)"
  locked "$d"
  expect_lock moved "" "$2"
}

case_L2_side_lock_merged_unsigned() { side_lock_case - "a side branch's lock.md merged in (unsigned)"; }
case_L2_side_lock_merged_signed() { side_lock_case "$SIGNED" "a side branch's lock.md merged in (signed)"; }

# side_merge_repo PATH -> merge_repo (base "base" moved on, not merged), plus a
# branch "side" from L that edits PATH, merged into feature (--no-ff);
# lock.md untouched
side_merge_repo() {
  local d path="$1"
  d="$(merge_repo)" || return 1
  git -C "$d" checkout -q -b side
  printf 'echo weakened on side\n' > "$d/$path"
  commit_all "$d" "side: weaken $path"
  git -C "$d" checkout -q feature
  git -C "$d" merge -q --no-ff --no-edit side
  if [ "$(git -C "$d" rev-parse HEAD^2)" != "$(git -C "$d" rev-parse side)" ]; then
    fail "fixture: HEAD is not a merge of side"; return 1
  fi
  if [ -n "$(git -C "$d" status --porcelain)" ]; then
    fail "fixture: merged repo is not clean"; return 1
  fi
  printf '%s\n' "$d"
}

side_merge_case() { # PATH msg
  local d; d="$(side_merge_repo "$1")"
  assert_true "fixture: one commit touches lock.md" test "$(lock_commit_count "$d")" = 1
  assert_true "fixture: side is not reachable from base" \
    bash -c '! git -C "$1" merge-base --is-ancestor side base' _ "$d"
  assert_file_contains "$d/$1" "echo weakened on side" "fixture: the merge took side's version"
  locked_with_base "$d" base
  expect_lock modified "$1" "$2"
  assert_not_contains "$OUT$ERR" "LOCK moved" "$2: lock.md untouched, not LOCK moved"
}

case_L3_side_merge_listed() {
  side_merge_case tests/a.test.sh "CORTEX_BASE_REF set: listed test weakened on a merged side branch"
}
case_L3_side_merge_matched() {
  side_merge_case tests/old.test.sh "CORTEX_BASE_REF set: matched test weakened on a merged side branch"
}

# Amendment 11 withdrew L3 (criteria 60-61): CORTEX_BASE_REF is no longer
# read, so a merge changing a locked file fails with or without it (AC65),
# and a re-locked merge passes with or without it (AC66).

case_L3_base_merge_with_base_ref() {
  # was AC60's "a merge of the base still passes"
  local d; d="$(merged_repo)"
  locked_with_base "$d" base
  expect_merge_failures "CORTEX_BASE_REF=base: a merge of the base, no re-lock"
}

case_L3_base_merge_with_base_sha() {
  # was AC60's "a merge of the base still passes" (base ref as a sha)
  local d; d="$(relocked_merge_repo)"
  locked_with_base "$d" "$(git -C "$d" rev-parse base)"
  expect_pass 5 "CORTEX_BASE_REF=<sha of base>: a re-locked merge of the base passes"
}

case_L3_unset_side_merge() {
  # was AC61: with CORTEX_BASE_REF unset a merged side branch's version was
  # accepted; under Amendment 11 it is an edit like any other
  local d; d="$(side_merge_repo tests/a.test.sh)"
  run bash -c 'unset CORTEX_BASE_REF; cd "$1" && ./cortex/bin/tests-locked.sh cortex/changes/x' _ "$d"
  expect_lock modified tests/a.test.sh "CORTEX_BASE_REF unset: a merged side branch's version"
}

# relock_drop_case GLOBS msg : locked_repo GLOBS (a and b listed); T2 fixes
# tests/a.test.sh; a signed L2 lists only tests/a.test.sh
relock_drop_case() {
  local d; d="$(locked_repo "$1")"
  printf 'echo a fixed\n' > "$d/tests/a.test.sh"
  relock_it "$d" "$SIGNED" '- tests/a.test.sh'
  assert_file_not_contains "$d/$LOCK_REL" "tests/b.test.sh" "fixture: L2 drops tests/b.test.sh"
  assert_true "fixture: two lock commits" test "$(lock_commit_count "$d")" = 2
  locked "$d"
  expect_lock moved "" "$2"
}

case_L4_relock_drops_path() { relock_drop_case '*.test.sh' "signed re-lock dropping a listed path"; }
case_L4_relock_drops_path_no_globs() { relock_drop_case "" "signed re-lock dropping a listed path, no TEST_GLOBS"; }

# expect_moved_no_git_error msg
expect_moved_no_git_error() {
  assert_exit 1 "$CODE" "$1: exits 1"
  assert_contains "$OUT$ERR" "LOCK moved" "$1: reports LOCK moved"
  assert_not_contains "$OUT$ERR" "fatal:" "$1: no git error"
  assert_not_contains "$OUT" "tests-locked: " "$1: no success line"
}

case_L4_lock_deleted_then_relocked() {
  local d; d="$(locked_repo)"
  git -C "$d" rm -q "$LOCK_REL"
  git -C "$d" commit -q -m "drop the lock"
  printf 'echo a fixed\n' > "$d/tests/a.test.sh"
  relock_it "$d" "$SIGNED"
  assert_true "fixture: three commits touch lock.md" test "$(lock_commit_count "$d")" = 3
  assert_true "fixture: lock.md is absent from the deleting commit" \
    bash -c '! git -C "$1" cat-file -e "HEAD~2:$2" 2>/dev/null' _ "$d" "$LOCK_REL"
  locked "$d"
  expect_moved_no_git_error "lock.md deleted, then re-added by a signed re-lock"
}

case_L4_lock_deleted_then_restored() {
  local d saved; d="$(locked_repo)"
  saved="$(cat "$d/$LOCK_REL")"
  git -C "$d" rm -q "$LOCK_REL"
  git -C "$d" commit -q -m "drop the lock"
  mkdir -p "$d/cortex/changes/x"
  printf '%s\n' "$saved" > "$d/$LOCK_REL"
  commit_all "$d" "restore the lock"
  assert_true "fixture: three commits touch lock.md" test "$(lock_commit_count "$d")" = 3
  locked "$d"
  expect_moved_no_git_error "lock.md deleted, then restored unchanged"
}

run_case "fixture: T, then lock.md in its own commit L" case_fixture_layout
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
run_case "missing: no lock.md" case_missing_lock_file
run_case "missing: no locked tests" case_no_locked_tests
run_case "not-locked: path absent at sha" case_not_locked
run_case "AC9 pass: count = listed + matched" case_A1_pass_counts_listed_plus_matched
run_case "AC9 pass: listed+matched counted once" case_A1_listed_and_matched_not_double_counted
run_case "AC9 pass: non-matching unlisted file free" case_A1_non_matching_helper_free
run_case "AC9 modified: unlisted test, unstaged" case_A1_modified_unstaged
run_case "AC9 modified: unlisted test, staged" case_A1_modified_staged
run_case "AC9 modified: unlisted test, committed" case_A1_modified_committed
run_case "AC9 deleted: unlisted test" case_A1_deleted
run_case "AC9 deleted: unlisted test, committed" case_A1_deleted_committed
run_case "AC9 pass: without TEST_GLOBS" case_A1_without_globs_passes
run_case "AC9 pass: placeholder TEST_GLOBS" case_A1_placeholder_globs_passes
run_case "AC14 moved: lock.md edited, unstaged" case_B1_lock_edited_unstaged
run_case "AC14 moved: lock.md edited, staged" case_B1_lock_edited_staged
run_case "AC14 moved: lock.md edited, committed" case_B1_lock_edited_committed
run_case "AC14 moved: second commit touching lock.md" case_B1_second_commit_same_content
run_case "AC14 moved: re-pointed after weakening a test" case_B1_repoint_after_weakening
run_case "AC14 moved: L's parent is not the named sha" case_B1_parent_not_named_sha
run_case "AC14 moved: lock.md never committed" case_B1_lock_uncommitted
run_case "B1 list lines with a trailing note" case_B1_trailing_note
run_case "AC14 config: TEST_GLOBS narrowed, unstaged" case_B2_config_narrowed_unstaged
run_case "AC14 config: TEST_GLOBS narrowed, staged" case_B2_config_narrowed_staged
run_case "AC14 config: TEST_GLOBS narrowed, committed" case_B2_config_narrowed_committed
run_case "AC14 config: gate command changed" case_B2_config_command_changed
run_case "AC14 narrowing TEST_GLOBS doesn't unlock a test" case_B2_narrowing_does_not_unlock
run_case "AC14 narrowing TEST_GLOBS doesn't hide an added test" case_B2_narrowing_still_flags_added
run_case "B2 TEST_GLOBS read from the lock commit" case_B2_widening_at_lock_is_used
run_case "B2 config absent at the lock is not counted" case_B2_config_absent_at_lock_not_counted
run_case "AC15 pass: spaced and non-ASCII paths" case_B4_untouched
run_case "AC15 modified: path with a space" case_B4_spaced_modified
run_case "AC15 modified: non-ASCII path" case_B4_non_ascii_modified
run_case "AC15 modified: unlisted non-ASCII path" case_B4_unlisted_non_ascii_modified
run_case "AC15 deleted: path in a spaced directory" case_B4_spaced_dir_deleted
run_case "AC15 added: non-ASCII path" case_B4_non_ascii_added
run_case "AC16 pass: CRLF lock.md and config" case_crlf_untouched
run_case "AC16 modified under CRLF lock.md" case_crlf_modified
run_case "AC16 added under CRLF config" case_crlf_globs_added
run_case "AC16 unlisted matched test under CRLF config" case_crlf_globs_unlisted
run_case "AC65 merge of the base without a re-lock fails" case_M1_merge_base_fails
run_case "AC66 merge of the base, then a signed re-lock naming it, passes" case_M2_merge_relock_passes
run_case "AC66 implementation after a re-locked base merge passes" case_M2_merge_relock_then_implementation
run_case "AC51/AC66 merge of the base, then an unsigned re-lock" case_M2_unsigned_merge_relock
run_case "AC66 listed test edited after a re-locked merge, committed" case_D1_edit_after_merge_committed
run_case "AC66 matched test edited after a re-locked merge, unstaged" case_D1_edit_after_merge_unstaged
run_case "AC66 listed test edited after a re-locked merge, staged" case_D1_edit_after_merge_staged
run_case "AC66 config edited after a re-locked merge" case_D1_config_edit_after_merge
run_case "AC66 base's new test edited after a re-locked merge" case_D1_new_test_edit_after_merge
run_case "AC66 new test added after a re-locked merge" case_D1_added_after_merge
run_case "AC65 merge resolving a listed test to neither side" case_D1_merge_resolved_to_neither
run_case "AC65 merge resolving a matched test to neither side" case_D1_merge_resolved_to_neither_matched
run_case "AC65 merge resolving the config to neither side" case_D1_merge_resolved_config_to_neither
run_case "AC28 rebase onto a moved base fails" case_D1_rebase_onto_moved_base
run_case "AC67 merge taking the base's older copy of a locked test" case_M1_merge_takes_base_older_copy
run_case "AC68 fabricated merge of the fork point restoring a locked test" case_M1_fabricated_merge
run_case "AC68 fabricated merge, CORTEX_BASE_REF set" case_M1_fabricated_merge_with_base_ref
run_case "AC69 signed re-lock narrowing TEST_GLOBS" case_M3_relock_narrows_globs
run_case "AC69 signed re-lock widening TEST_GLOBS" case_M3_relock_widens_globs
run_case "AC69 re-locked merge of a base that changed the config" case_M3_merge_relock_with_config
run_case "AC32 TEST_GLOBS with spaces around =" case_AC32_spaced
run_case "AC32 TEST_GLOBS after a commented-out line" case_AC32_comment
run_case "AC32 TEST_GLOBS after a line without =" case_AC32_no_equals
run_case "AC32 TEST_GLOBS twice: the first wins" case_AC32_twice
run_case "AC34 a stub _config.sh changes what tests-locked.sh reads" case_AC34_stub_parser
run_case "AC37 listed test: staged edit, working tree restored" case_AC37_listed
run_case "AC37 TEST_GLOBS test: staged edit, working tree restored" case_AC37_glob_only
run_case "AC50 signed re-lock passes" case_K1_signed_relock_minimal
run_case "AC50 signed re-lock with new and matched tests passes" case_K1_signed_relock_passes
run_case "AC51 re-lock without a sign-off line" case_K1_unsigned_no_line
run_case "AC51 re-lock with an empty sign-off" case_K1_unsigned_empty
run_case "AC51 re-lock with a blank sign-off" case_K1_unsigned_blank
run_case "AC51 re-lock with a <name> placeholder" case_K1_unsigned_placeholder
run_case "AC52 signed re-lock whose parent is not the named sha" case_K1_relock_parent_not_named_sha
run_case "AC53 sign-off removed after a re-lock" case_K1_signoff_removed_later
run_case "AC53 lock.md edited after a re-lock, committed" case_K1_lock_edited_after_relock_committed
run_case "AC53 lock.md edited after a re-lock, unstaged" case_K1_lock_edited_after_relock_unstaged
run_case "AC53 third lock commit without a sign-off" case_K1_third_lock_unsigned
run_case "AC57 files changed in T2 itself pass" case_K2_changed_in_t2_passes
run_case "AC54 new listed test edited after the re-lock" case_K2_new_listed_modified
run_case "AC54 listed test edited after the re-lock" case_K2_listed_modified_unstaged
run_case "AC54 matched test edited after the re-lock" case_K2_matched_modified_staged
run_case "AC54 new test added after T2" case_K2_added_after_t2
run_case "AC54 config edited after the re-lock" case_K2_config_modified
run_case "AC65 merge of the base after a re-lock, not re-locked, fails" case_K2_merge_after_relock_fails
run_case "AC66 merge of the base after a re-lock, re-locked again, passes" case_K2_merge_after_relock_relocked_passes
run_case "AC66 listed test edited after that merge and re-lock" case_K2_edit_after_relock_merge
run_case "AC55 a merge before T2 is not accepted after the re-lock" case_K2_merge_before_t2_not_accepted
run_case "AC56 single lock commit with a sign-off line" case_K1_single_lock_with_signoff
run_case "AC57 listed test edited after L1, before T2" case_L1_listed_before_t2
run_case "AC57 matched test edited after L1, before T2" case_L1_matched_before_t2
run_case "AC57 config edited after L1, before T2" case_L1_config_before_t2
run_case "AC58 matched test added after L1, before T2" case_L1_added_before_t2
run_case "AC59 side branch's lock.md merged in, unsigned" case_L2_side_lock_merged_unsigned
run_case "AC59 side branch's lock.md merged in, signed" case_L2_side_lock_merged_signed
run_case "AC65 CORTEX_BASE_REF set: listed test weakened on a merged side branch" case_L3_side_merge_listed
run_case "AC65 CORTEX_BASE_REF set: matched test weakened on a merged side branch" case_L3_side_merge_matched
run_case "AC65 CORTEX_BASE_REF set: a merge of the base, no re-lock, fails" case_L3_base_merge_with_base_ref
run_case "AC66 CORTEX_BASE_REF as a sha: a re-locked merge of the base passes" case_L3_base_merge_with_base_sha
run_case "AC65 CORTEX_BASE_REF unset: listed test weakened on a merged side branch" case_L3_unset_side_merge
run_case "AC63 signed re-lock dropping a listed path" case_L4_relock_drops_path
run_case "AC63 signed re-lock dropping a listed path, no TEST_GLOBS" case_L4_relock_drops_path_no_globs
run_case "AC64 lock.md deleted, then re-added by a re-lock" case_L4_lock_deleted_then_relocked
run_case "AC64 lock.md deleted, then restored" case_L4_lock_deleted_then_restored
summary
