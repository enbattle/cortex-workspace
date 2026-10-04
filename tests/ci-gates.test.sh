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

# lock_folder DIR FOLDER : commit everything as T, then FOLDER/lock.md naming
# T (locking tests/b.test.sh) as its own commit L
lock_folder() { lock_tests "$1" "$2" tests/b.test.sh; }

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

# ---- AC29/AC70 (Amendments 4 and 11): archived folders; a dropped lock ----------
#
# Amendment 11, M4: a branch that adds a lock.md and no longer has it at HEAD
# (deleted, or its folder moved under changes/archive/) fails for that folder.
# Archiving a folder whose lock.md is already on the base stays ungated (D2).

# expect_dropped_lock msg : ci-gates fails for changes/x, and nothing else
expect_dropped_lock() {
  assert_exit 1 "$CODE" "$1: exit 1"
  if grep -qE '^ci-gates: FAIL changes/(archive/)?x( |:|$)' <<<"$OUT"; then pass
  else fail "$1: a ci-gates: FAIL line for the folder"; show_output; fi
  assert_line "$OUT" "ci-gates: check ok" "$1: check still passes"
  assert_true "$1: one failure counted, as the last line" test "$(last_line "$OUT")" = "ci-gates: 1 failed"
}

case_archived_on_branch() {
  # was AC29's "folder archived on the branch is not gated": the lock was
  # added on this branch, so moving it away drops it (AC70)
  local d; d="$(ci_repo)"
  git -C "$d" mv changes/x changes/archive/x
  git -C "$d" commit -q -m "archive changes/x"
  assert_file_exists "$d/changes/archive/x/lock.md" "fixture: lock.md now under changes/archive/"
  ci_gates "$d" "$BASE"
  expect_dropped_lock "lock added on the branch, then its folder archived"
}

case_added_lock_deleted() {
  local d; d="$(ci_repo)"
  git -C "$d" rm -q changes/x/lock.md
  git -C "$d" commit -q -m "drop the lock"
  assert_file_absent "$d/changes/x/lock.md" "fixture: lock.md deleted"
  assert_true "fixture: the base has no changes/x/lock.md" \
    bash -c '! git -C "$1" cat-file -e "$2:changes/x/lock.md" 2>/dev/null' _ "$d" "$BASE"
  ci_gates "$d" "$BASE"
  expect_dropped_lock "lock added on the branch, then deleted"
}

# ---- AC72 (Amendment 12, N1): a merge can't hide the lock commit ------------------
#
# The tip is a merge whose first parent is T (the tests commit, before the
# lock: no changes/x/lock.md) and whose second parent is the lock commit L,
# keeping T's tree for changes/x. A pathspec git log simplifies history and
# prunes the L side, so the dropped lock is only seen by reading every commit.

# pruned_lock_merge DIR [archive|archive-first] : make HEAD such a merge,
# built with plumbing so the shape is exact. The tree is the first parent's
# plus src/impl.txt. With "archive", the merge also places L's lock.md at
# changes/archive/x/lock.md. With "archive-first", the first parent is P, a
# child of T (a sibling of L) that already holds that archived copy, so the
# merge equals P for every lock.md path and any pathspec log prunes L.
pruned_lock_merge() {
  local d="$1" first l blob tree m
  l="$(git -C "$d" rev-parse HEAD)"
  first="$(git -C "$d" rev-parse HEAD^1)"
  blob="$(git -C "$d" rev-parse "$l:changes/x/lock.md")"
  git -C "$d" checkout -q "$first"
  if [ "${2-}" = archive-first ]; then
    git -C "$d" update-index --add --cacheinfo "100644,$blob,changes/archive/x/lock.md"
    tree="$(git -C "$d" write-tree)"
    first="$(printf 'archive copy of the lock, before the merge\n' | git -C "$d" commit-tree "$tree" -p "$first")"
    git -C "$d" checkout -q "$first"
  fi
  printf 'impl\n' > "$d/src/impl.txt"
  git -C "$d" add src/impl.txt
  if [ "${2-}" = archive ]; then
    git -C "$d" update-index --add --cacheinfo "100644,$blob,changes/archive/x/lock.md"
  fi
  tree="$(git -C "$d" write-tree)"
  m="$(printf 'merge the lock, keeping the pre-lock tree\n' | git -C "$d" commit-tree "$tree" -p "$first" -p "$l")"
  git -C "$d" checkout -q feature
  git -C "$d" reset -q --hard "$m"
}

# expect_pruned_shape DIR : fixture checks that HEAD is the pruned-side merge
expect_pruned_shape() {
  local d="$1"
  assert_true "fixture: HEAD^1 has no changes/x/lock.md" \
    bash -c '! git -C "$1" cat-file -e HEAD^1:changes/x/lock.md 2>/dev/null' _ "$d"
  assert_true "fixture: HEAD^2 is the lock commit (adds changes/x/lock.md)" \
    test -n "$(git -C "$d" diff --name-only --diff-filter=A HEAD^2^ HEAD^2 -- changes/x/lock.md)"
  assert_file_absent "$d/changes/x/lock.md" "fixture: no changes/x/lock.md at HEAD"
  assert_true "fixture: the base has no changes/x/lock.md" \
    bash -c '! git -C "$1" cat-file -e "$2:changes/x/lock.md" 2>/dev/null' _ "$d" "$BASE"
  assert_true "fixture: a plain pathspec git log prunes the lock commit" \
    test -z "$(git -C "$d" log --format=%H "$BASE..HEAD" -- changes/x/lock.md)"
}

case_AC72_merge_prunes_lock() {
  local d; d="$(ci_repo)"
  pruned_lock_merge "$d"
  expect_pruned_shape "$d"
  assert_file_exists "$d/src/impl.txt" "fixture: the merge added an implementation file"
  ci_gates "$d" "$BASE"
  expect_dropped_lock "merge whose first parent predates the lock"
  assert_line "$OUT" "ci-gates: FAIL changes/x (lock.md added on this branch is gone)" \
    "the dropped-lock line names changes/x"
}

case_AC72_merge_prunes_lock_archived() {
  local d; d="$(ci_repo)"
  pruned_lock_merge "$d" archive
  expect_pruned_shape "$d"
  assert_file_exists "$d/changes/archive/x/lock.md" "fixture: lock.md now under changes/archive/x"
  ci_gates "$d" "$BASE"
  expect_dropped_lock "merge whose first parent predates the lock, folder archived"
  assert_true "the dropped-lock line names the folder" \
    grep -qxE 'ci-gates: FAIL changes/(archive/)?x \(lock\.md added on this branch is gone\)' <<<"$OUT"
}

case_AC72_merge_prunes_lock_archived_first_parent() {
  local d l; d="$(ci_repo)"
  l="$(git -C "$d" rev-parse HEAD)"
  pruned_lock_merge "$d" archive-first
  expect_pruned_shape "$d"
  assert_file_exists "$d/changes/archive/x/lock.md" "fixture: lock.md under changes/archive/x"
  assert_true "fixture: the merge equals its first parent for every lock.md path" \
    git -C "$d" diff --quiet HEAD^1 HEAD -- 'changes/*lock.md'
  assert_true "fixture: a pathspec log over every lock.md prunes the lock commit" \
    bash -c '! git -C "$1" log --format=%H "$2..HEAD" -- "changes/*lock.md" | grep -qxF "$3"' _ "$d" "$BASE" "$l"
  ci_gates "$d" "$BASE"
  expect_dropped_lock "merge pruning the lock, archived copy on the first parent"
  assert_true "the dropped-lock line names the folder" \
    grep -qxE 'ci-gates: FAIL changes/(archive/)?x \(lock\.md added on this branch is gone\)' <<<"$OUT"
}

case_archived_after_merge() {
  # the usual order: changes/x merged into the base, then a later branch
  # archives it
  local d; d="$(ci_repo)"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q -b archive-x
  git -C "$d" mv changes/x changes/archive/x
  git -C "$d" commit -q -m "archive changes/x"
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "archiving a merged change -> exit 0"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: ok" "archived folder is not gated after the merge"
  assert_not_contains "$OUT" "LOCK " "the archived lock.md was not checked"
}

# ---- AC65/AC66 (Amendment 11, M1/M2): a base merge is a re-lock -----------------

# move_base DIR [no-config] : the base moves on (edits tests/a.test.sh, matched
# by TEST_GLOBS, and, unless "no-config", .cortex/config; adds tests/c.test.sh);
# feature checked out again, not merged
move_base() {
  git -C "$1" checkout -q -B main "$BASE"
  printf 'echo a from base\n' > "$1/tests/a.test.sh"
  [ "${2-}" = no-config ] || append "$1/.cortex/config" "# base: a later config line"
  printf 'echo c from base\n' > "$1/tests/c.test.sh"
  commit_all "$1" "base moves on"
  git -C "$1" update-ref "refs/remotes/$BASE" HEAD
  git -C "$1" checkout -q feature
}

# relock_folder DIR FOLDER : FOLDER/lock.md naming HEAD (the merge), signed,
# listing tests/b.test.sh, committed as the very next commit
relock_folder() {
  local sha; sha="$(git -C "$1" rev-parse HEAD)"
  printf 'Tests-locked-at: %s\nRe-lock signed off by: Pat Maintainer\n\n## Locked tests\n\n- tests/b.test.sh\n' \
    "$sha" > "$1/$2/lock.md"
  commit_all "$1" "re-lock $2 after merging the base"
}

case_base_merged_into_locked_branch() {
  # was "base merged into a locked branch -> ok" (Amendment 4, withdrawn):
  # the merge changed locked files and nothing re-locked them
  local d; d="$(ci_repo)"
  move_base "$d"
  git -C "$d" merge -q --no-edit "$BASE"
  assert_true "fixture: merge took base's test" grep -qF "echo a from base" "$d/tests/a.test.sh"
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "locked branch with the base merged in, no re-lock -> exit 1"
  assert_contains "$OUT" "LOCK modified: tests/a.test.sh" "the base tests-locked.sh names the merged test"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: FAIL changes/x
ci-gates: 1 failed" "the folder fails after an un-relocked base merge"
}

case_base_merged_and_relocked() {
  local d m; d="$(ci_repo)"
  move_base "$d" no-config
  git -C "$d" merge -q --no-edit "$BASE"
  m="$(git -C "$d" rev-parse HEAD)"
  relock_folder "$d" changes/x
  assert_true "fixture: the re-lock follows the merge" test "$(git -C "$d" rev-parse HEAD^1)" = "$m"
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "base merged, then a signed re-lock naming the merge -> exit 0"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: changes/x ok
ci-gates: ok" "the folder is gated and passes after a re-locked base merge"
  assert_not_contains "$OUT" "LOCK " "no LOCK lines after a re-locked base merge"
}

# ---- AC35 (Amendment 6, F1): the base's parser, never the branch's ----------------

case_AC35_branch_stub_parser() {
  # the branch replaces _config.sh with one that reads nothing; the base copies
  # of check.sh and gates.sh still read the base's filled config correctly
  local d; d="$(ci_repo)"
  printf '%s\n' '# stub: config_value reads its input and prints nothing' \
    'config_value() { cat > /dev/null; }' > "$d/scripts/cortex/_config.sh"
  commit_all "$d" "replace the config parser"
  assert_true "fixture: the branch's _config.sh differs from the base's" \
    test -n "$(git -C "$d" diff --name-only "$BASE" HEAD -- scripts/cortex/_config.sh)"
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "ci-gates passes with the base's parser"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: changes/x ok
ci-gates: ok" "base parser: check and folder pass"
  assert_not_contains "$OUT" "[C11]" "the base check.sh reads the config"
  assert_line "$OUT" "gate build: ok" "the base gates.sh reads BUILD_CMD"
  assert_true "ci-gates: ok is the last line" test "$(last_line "$OUT")" = "ci-gates: ok"
}

# ---- AC62 (Amendment 10, L3): the base allowance needs the base ---------------------

case_AC62_side_branch_weakens_locked_test() {
  # a side branch (not reachable from the base) weakens the locked test and
  # is merged into the locked branch, lock.md untouched: the side's version
  # is an edit (Amendment 11, M1: no merge allowance at all; the local check
  # that used to accept it without CORTEX_BASE_REF, criterion 61, is withdrawn)
  local d; d="$(ci_repo)"
  git -C "$d" checkout -q -b side
  printf 'echo weakened on side\n' > "$d/tests/b.test.sh"
  commit_all "$d" "side: weaken the locked test"
  git -C "$d" checkout -q feature
  git -C "$d" merge -q --no-ff --no-edit side
  assert_true "fixture: HEAD is a merge of side" \
    test "$(git -C "$d" rev-parse HEAD^2)" = "$(git -C "$d" rev-parse side)"
  assert_true "fixture: side is not reachable from the base" \
    bash -c '! git -C "$1" merge-base --is-ancestor side "$2"' _ "$d" "$BASE"
  assert_true "fixture: lock.md untouched by the merge" \
    git -C "$d" diff --quiet HEAD^1 HEAD -- changes/x/lock.md
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "side-branch weakening merged in -> exit 1"
  assert_contains "$OUT" "LOCK modified: tests/b.test.sh" "the base tests-locked.sh names the weakened test"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: FAIL changes/x
ci-gates: 1 failed" "the folder fails, nothing else"
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
run_case "AC70 lock added on the branch, then archived -> FAIL" case_archived_on_branch
run_case "AC70 lock added on the branch, then deleted -> FAIL" case_added_lock_deleted
run_case "AC72 merge keeping the pre-lock tree drops the lock -> FAIL" case_AC72_merge_prunes_lock
run_case "AC72 the same merge, folder moved under changes/archive/ -> FAIL" case_AC72_merge_prunes_lock_archived
run_case "AC72 the same merge, archived copy already on the first parent -> FAIL" case_AC72_merge_prunes_lock_archived_first_parent
run_case "AC29 folder archived after its change merged" case_archived_after_merge
run_case "AC65 base merged into a locked branch, no re-lock -> FAIL" case_base_merged_into_locked_branch
run_case "AC66 base merged, then a signed re-lock -> ok" case_base_merged_and_relocked
run_case "AC35 a branch's stub _config.sh: the base's parser is used" case_AC35_branch_stub_parser
run_case "AC62 a merged side branch weakening a locked test fails" case_AC62_side_branch_weakens_locked_test
summary
