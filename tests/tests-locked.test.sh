#!/usr/bin/env bash
# Tests for scripts/cortex/tests-locked.sh (spec acceptance criteria 6, 9 and,
# under Amendment 2, 14-16).
#
# Lock layout (Amendment 2, B1): test-first commits the tests (commit T), then
# adds <change-folder>/lock.md naming T in its own commit L, whose first
# parent is T. Every fixture below builds exactly that: T, then L, then any
# further commits. The lock also covers .cortex/config (B2), which counts in
# the success line when it existed at T, so a fresh install's counts are
# "locked tests + 1".
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

LOCK_REL="changes/x/lock.md"

commit_all() { # dir msg
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}

# write_lock DIR SHA [LIST-LINE...] : changes/x/lock.md naming SHA ("-" omits
# the Tests-locked-at line). With no list lines, locks tests/a.test.sh and
# tests/b.test.sh (the second wrapped in backticks). A "## Notes" section
# follows the list, so the list must end at the next heading.
write_lock() {
  local d="$1" sha="$2"; shift 2
  mkdir -p "$d/changes/x"
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
  set_config "$d/.cortex/config" TEST_GLOBS "$globs"
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
  run bash -c 'cd "$1" && ./scripts/cortex/tests-locked.sh "$2"' _ "$1" "${2:-changes/x}"
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
  assert_file_absent "$d/changes/x/tasks.md" "fixture: no tasks.md is needed"
}

case_pass_untouched() {
  local d sha; d="$(locked_repo)"; sha="$(lock_sha "$d")"
  locked "$d"
  # a, b + .cortex/config (B2)
  expect_pass 3 "untouched locked set"
  assert_contains "$OUT" "since $(printf '%s' "$sha" | cut -c1-7)" "success line names the short sha"
}

case_pass_non_test_changes() {
  local d; d="$(locked_repo)"
  printf 'app v2\n' > "$d/src/app.txt"
  printf 'new\n' > "$d/src/new.txt"
  commit_all "$d" "implementation"
  printf 'more\n' >> "$d/src/app.txt"
  printf '%s\n' '- [x] done' > "$d/changes/x/tasks.md"
  locked "$d"
  assert_exit 0 "$CODE" "implementation changes outside tests (and tasks.md) are fine"
}

case_pass_from_subdir() {
  local d; d="$(locked_repo)"
  run bash -c 'cd "$1/src" && ../scripts/cortex/tests-locked.sh ../changes/x' _ "$d"
  assert_exit 0 "$CODE" "runs from a subdirectory of the repo"
  assert_contains "$OUT" "tests-locked: 3 file(s) unchanged since" "success from subdir"
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
  mkdir -p "$d/changes/empty"
  printf 'Tests-locked-at: %s\n\n## Locked tests\n\n- tests/a.test.sh\n' "$(lock_sha "$d")" \
    > "$d/changes/empty/tasks.md"
  commit_all "$d" "a tasks.md is not a lock record"
  locked "$d" changes/empty
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
  # a, b listed (and matched), old matched only, + .cortex/config: 4, each
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

# ---- AC14 (B1, B2): lock.md can't be moved; .cortex/config is locked -------------

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
  expect_lock modified .cortex/config "$1"
}

case_B2_config_narrowed_unstaged() {
  local d; d="$(locked_repo)"
  set_config "$d/.cortex/config" TEST_GLOBS 'tests/a.test.sh'
  locked "$d"
  config_mod "TEST_GLOBS narrowed, unstaged"
}

case_B2_config_narrowed_staged() {
  local d; d="$(locked_repo)"
  set_config "$d/.cortex/config" TEST_GLOBS 'tests/a.test.sh'
  git -C "$d" add .cortex/config
  locked "$d"
  config_mod "TEST_GLOBS narrowed, staged"
}

case_B2_config_narrowed_committed() {
  local d; d="$(locked_repo)"
  set_config "$d/.cortex/config" TEST_GLOBS 'tests/a.test.sh'
  commit_all "$d" "narrow globs"
  locked "$d"
  config_mod "TEST_GLOBS narrowed, committed"
}

case_B2_config_command_changed() {
  local d; d="$(locked_repo)"
  set_config "$d/.cortex/config" TEST_CMD 'true'
  locked "$d"
  config_mod "a gate command changed"
}

case_B2_narrowing_does_not_unlock() {
  local d; d="$(locked_repo_with_old)"
  set_config "$d/.cortex/config" TEST_GLOBS 'tests/a.test.sh'
  printf 'echo weakened\n' > "$d/tests/old.test.sh"
  locked "$d"
  config_mod "narrowed TEST_GLOBS"
  assert_contains "$OUT$ERR" "LOCK modified: tests/old.test.sh" "matched test still locked under the lock's TEST_GLOBS"
}

case_B2_narrowing_still_flags_added() {
  local d; d="$(locked_repo)"
  set_config "$d/.cortex/config" TEST_GLOBS 'tests/a.test.sh'
  printf 'echo c\n' > "$d/tests/c.test.sh"
  locked "$d"
  config_mod "narrowed TEST_GLOBS"
  assert_contains "$OUT$ERR" "LOCK added: tests/c.test.sh" "new test flagged under the lock's TEST_GLOBS"
}

case_B2_widening_at_lock_is_used() {
  # TEST_GLOBS empty in the working tree, set at the lock: the lock's wins
  local d; d="$(locked_repo_with_old)"
  set_config "$d/.cortex/config" TEST_GLOBS ''
  rm "$d/tests/old.test.sh"
  locked "$d"
  config_mod "TEST_GLOBS emptied"
  assert_contains "$OUT$ERR" "LOCK deleted: tests/old.test.sh" "deletion flagged under the lock's TEST_GLOBS"
}

case_B2_config_absent_at_lock_not_counted() {
  local d; d="$(base_repo "")"
  rm "$d/.cortex/config"
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
  set_config "$d/.cortex/config" TEST_GLOBS '*.test.sh'
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
  # 4 tests + .cortex/config
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

# ---- AC16: CRLF lock.md and .cortex/config ----------------------------------------

no_cr() { # text msg  (a bash pattern, since grep may strip CRs)
  case "$1" in *$'\r'*) fail "$2"; show_output ;; *) pass ;; esac
}

to_crlf() { filter_file "$1" awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }'; }

crlf_repo() {
  local d sha
  d="$(base_repo)" || return 1
  to_crlf "$d/.cortex/config"
  commit_all "$d" "add tests"
  sha="$(git -C "$d" rev-parse HEAD)"
  write_lock "$d" "$sha"
  to_crlf "$d/$LOCK_REL"
  commit_all "$d" "lock tests"
  # (tr + cmp, not grep: Git Bash's grep strips CRs before matching)
  if tr -d '\r' < "$d/$LOCK_REL" | cmp -s - "$d/$LOCK_REL" \
    || tr -d '\r' < "$d/.cortex/config" | cmp -s - "$d/.cortex/config"; then
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
  to_crlf "$d/.cortex/config"
  lock_it "$d"
  printf 'echo weakened\n' > "$d/tests/old.test.sh"
  locked "$d"
  expect_lock modified tests/old.test.sh "CRLF config: matched unlisted test locked"
}

# ---- AC26-28 (Amendment 4, D1): merging the base is allowed; rebasing is not ---

# merge_repo -> a locked branch whose base has moved on, not yet merged:
#   B0 (branch "base"): installed, TEST_GLOBS=*.test.sh, tests/a.test.sh,
#     tests/b.test.sh, tests/old.test.sh (matched, unlisted), src/app.txt
#   feature (checked out): T adds src/feature.txt, L locks a and b
#   B1 on "base": edits tests/a.test.sh (listed), tests/old.test.sh (matched,
#     unlisted) and .cortex/config, and adds tests/new.test.sh (matched)
merge_repo() {
  local d
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
  append "$d/.cortex/config" "# base: a later config line"
  printf 'echo new from base\n' > "$d/tests/new.test.sh"
  commit_all "$d" "base B1"
  git -C "$d" checkout -q feature
  printf '%s\n' "$d"
}

# merged_repo -> merge_repo with "base" merged into feature (no conflicts:
# the merge takes the base's version of every locked or matched file)
merged_repo() {
  local d
  d="$(merge_repo)" || return 1
  git -C "$d" merge -q --no-edit base
  if [ "$(git -C "$d" rev-parse HEAD^2)" != "$(git -C "$d" rev-parse base)" ]; then
    fail "fixture: HEAD is not a merge of base"; return 1
  fi
  if [ -n "$(git -C "$d" status --porcelain)" ]; then
    fail "fixture: merged repo is not clean"; return 1
  fi
  printf '%s\n' "$d"
}

case_D1_merge_base_passes() {
  local d sha; d="$(merged_repo)"; sha="$(git -C "$d" rev-parse 'HEAD^1~1')"
  assert_true "fixture: the lock names T" \
    grep -qF "Tests-locked-at: $sha" "$d/$LOCK_REL"
  assert_file_contains "$d/tests/a.test.sh" "echo a from base" "fixture: merge took base's listed test"
  assert_file_contains "$d/tests/old.test.sh" "echo old from base" "fixture: merge took base's matched test"
  assert_file_contains "$d/.cortex/config" "# base: a later config line" "fixture: merge took base's config"
  assert_file_exists "$d/tests/new.test.sh" "fixture: merge brought base's new test"
  locked "$d"
  assert_exit 0 "$CODE" "merge of the base taking its versions: exits 0"
  assert_contains "$OUT" "file(s) unchanged since $(printf '%s' "$sha" | cut -c1-7)" \
    "merge of the base: success line unchanged in form"
  assert_not_contains "$OUT$ERR" "LOCK " "merge of the base: no LOCK lines"
}

case_D1_merge_then_implementation() {
  local d; d="$(merged_repo)"
  printf 'app v2\n' > "$d/src/app.txt"
  commit_all "$d" "implementation after the merge"
  locked "$d"
  assert_exit 0 "$CODE" "implementation commits after a base merge still pass"
  assert_not_contains "$OUT$ERR" "LOCK " "no LOCK lines"
}

case_D1_edit_after_merge_committed() {
  local d; d="$(merged_repo)"
  printf 'echo a weakened\n' > "$d/tests/a.test.sh"
  commit_all "$d" "weaken after merge"
  locked "$d"
  expect_lock modified tests/a.test.sh "listed test edited on top of a base merge"
}

case_D1_edit_after_merge_unstaged() {
  local d; d="$(merged_repo)"
  printf 'echo old weakened\n' > "$d/tests/old.test.sh"
  locked "$d"
  expect_lock modified tests/old.test.sh "matched test edited (unstaged) on top of a base merge"
}

case_D1_edit_after_merge_staged() {
  local d; d="$(merged_repo)"
  printf 'echo a weakened\n' > "$d/tests/a.test.sh"
  git -C "$d" add tests/a.test.sh
  locked "$d"
  expect_lock modified tests/a.test.sh "listed test edited (staged) on top of a base merge"
}

case_D1_config_edit_after_merge() {
  local d; d="$(merged_repo)"
  set_config "$d/.cortex/config" TEST_GLOBS 'tests/a.test.sh'
  commit_all "$d" "narrow globs after merge"
  locked "$d"
  expect_lock modified .cortex/config "config edited on top of a base merge"
}

case_D1_new_test_edit_after_merge() {
  local d; d="$(merged_repo)"
  printf 'echo new weakened\n' > "$d/tests/new.test.sh"
  commit_all "$d" "edit the base's new test"
  locked "$d"
  expect_lock added tests/new.test.sh "base's new test edited on the branch after the merge"
}

case_D1_added_after_merge() {
  local d; d="$(merged_repo)"
  printf 'echo c\n' > "$d/tests/c.test.sh"
  locked "$d"
  expect_lock added tests/c.test.sh "a test not on the base, added after a base merge"
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
  set_config "$d/.cortex/config" TEST_GLOBS 'tests/a.test.sh'
  git -C "$d" add .cortex/config
  git -C "$d" commit -q --no-edit
  locked "$d"
  expect_lock modified .cortex/config "merge resolving the config to neither side"
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
run_case "AC26 merge of the base taking its versions passes" case_D1_merge_base_passes
run_case "AC26 implementation after a base merge passes" case_D1_merge_then_implementation
run_case "AC27 listed test edited after a merge, committed" case_D1_edit_after_merge_committed
run_case "AC27 matched test edited after a merge, unstaged" case_D1_edit_after_merge_unstaged
run_case "AC27 listed test edited after a merge, staged" case_D1_edit_after_merge_staged
run_case "AC27 config edited after a merge" case_D1_config_edit_after_merge
run_case "AC27 base's new test edited after a merge" case_D1_new_test_edit_after_merge
run_case "AC27 new test added after a merge" case_D1_added_after_merge
run_case "AC27 merge resolving a listed test to neither side" case_D1_merge_resolved_to_neither
run_case "AC27 merge resolving a matched test to neither side" case_D1_merge_resolved_to_neither_matched
run_case "AC27 merge resolving the config to neither side" case_D1_merge_resolved_config_to_neither
run_case "AC28 rebase onto a moved base fails" case_D1_rebase_onto_moved_base
summary
