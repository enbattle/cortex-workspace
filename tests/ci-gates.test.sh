#!/usr/bin/env bash
# Tests for cortex/bin/ci-gates.sh (spec Amendment 3, C1; acceptance
# criteria 21-25). ci-gates.sh <base-ref> runs, with the checker scripts taken
# from <base-ref>: a hidden-edit scan (skip-worktree / assume-unchanged), the
# base copy of check.sh, and the base copy of gates.sh for every change folder
# whose lock.md was added or changed on this branch (base...HEAD).
#
# Fixture: a filled install (plus tests/a.test.sh, src/app.txt) committed as
# the base, pointed to by refs/remotes/origin/main, the way CI sees it. A
# feature branch then locks cortex/changes/x in the Amendment 2 layout: the tests are
# committed (T, adds tests/b.test.sh), then cortex/changes/x/lock.md naming T in its
# own commit (L). Each case plants its violation on the feature branch.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

BASE="origin/main"

# lock_folder DIR FOLDER : commit everything as T, then FOLDER/lock.md naming
# T (locking tests/b.test.sh) as its own commit L. FOLDER gets a tasks.md
# with every task ticked first, unless it has one: spec 3.1.0 G3's tasks gate
# fails a change folder without it (was: no tasks.md written)
lock_folder() {
  if [ ! -f "$1/$2/tasks.md" ]; then
    mkdir -p "$1/$2"
    printf '# Tasks: %s\n\n- [x] the change -- done when: its test passes\n' "${2##*/}" > "$1/$2/tasks.md"
  fi
  lock_tests "$1" "$2" tests/b.test.sh
}

# base_only -> filled install committed as the base (origin/main), checked out
# on branch "feature" at the same commit; nothing locked yet
base_only() {
  local d
  d="$(filled_install)" || return 1
  mkdir -p "$d/tests" "$d/src"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  printf 'app\n' > "$d/src/app.txt"
  commit_all "$d" "base: cortex installed"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q -b feature
  printf '%s\n' "$d"
}

# ci_repo -> base_only plus, on the feature branch, cortex/changes/x locked
ci_repo() {
  local d
  d="$(base_only)" || return 1
  printf 'echo b\n' > "$d/tests/b.test.sh"
  lock_folder "$d" cortex/changes/x
  printf '%s\n' "$d"
}

ci_gates() { # dir [args...] -> run the working tree's ci-gates.sh from the repo root
  local d="$1"; shift
  run bash -c 'd="$1"; shift; cd "$d" && bash cortex/bin/ci-gates.sh "$@"' _ "$d" "$@"
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
  assert_file_exists "$ROOT/template/cortex/bin/ci-gates.sh" "template ships ci-gates.sh"
  assert_true "installed ci-gates.sh is executable" test -x "$d/cortex/bin/ci-gates.sh"
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
ci-gates: cortex/changes/x ok
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

# base with cortex/changes/old/lock.md whose sha is garbage (gating it would fail
# LOCK bad-sha); returns the repo on the feature branch
base_with_old_lock() {
  local d
  d="$(filled_install)" || return 1
  mkdir -p "$d/tests" "$d/src" "$d/cortex/changes/old"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  printf 'app\n' > "$d/src/app.txt"
  printf 'Tests-locked-at: 0000000000000000000000000000000000000000\n\n## Locked tests\n\n- tests/a.test.sh\n' \
    > "$d/cortex/changes/old/lock.md"
  printf '# tasks\n' > "$d/cortex/changes/old/tasks.md"
  commit_all "$d" "base with an old change folder"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q -b feature
  printf '%s\n' "$d"
}

case_unchanged_lock_not_gated() {
  local d; d="$(base_with_old_lock)"
  printf '# tasks\n- more\n' > "$d/cortex/changes/old/tasks.md"   # folder touched, lock.md not
  printf 'echo b\n' > "$d/tests/b.test.sh"
  lock_folder "$d" cortex/changes/x
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "only the changed lock is gated -> exit 0"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: cortex/changes/x ok
ci-gates: ok" "cortex/changes/x gated, cortex/changes/old not"
  assert_not_contains "$OUT" "cortex/changes/old" "the unchanged folder is not gated"
  assert_not_contains "$OUT" "LOCK bad-sha" "the old lock was not checked"
}

case_deleted_lock_not_gated() {
  local d; d="$(base_with_old_lock)"
  git -C "$d" rm -q cortex/changes/old/lock.md
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
    > "$d/cortex/changes/old/lock.md"
  commit_all "$d" "base moves on"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q feature
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "a lock changed only on the base is not gated"
  assert_not_contains "$OUT" "cortex/changes/old" "cortex/changes/old not gated"
  assert_line "$OUT" "ci-gates: ok" "ends ok"
}

# ---- AC21 the checker comes from the base -----------------------------------------

case_tampered_tests_locked() {
  local d; d="$(ci_repo)"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/cortex/bin/tests-locked.sh"
  printf 'echo weakened\n' > "$d/tests/b.test.sh"
  commit_all "$d" "weaken the test and the checker"
  # the branch's own gates.sh is fooled
  run bash -c 'cd "$1" && bash cortex/bin/gates.sh cortex/changes/x' _ "$d"
  assert_exit 0 "$CODE" "fixture: the branch's own gates.sh passes"
  assert_line "$OUT" "gates: ok" "fixture: the branch's gates.sh says ok"
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "ci-gates fails with the base checker"
  assert_line "$OUT" "ci-gates: using scripts from $BASE" "reports using the base scripts"
  assert_contains "$OUT" "LOCK modified: tests/b.test.sh" "base tests-locked.sh names the weakened test"
  assert_line "$OUT" "gate tests-locked: FAIL (exit 1)" "base gates.sh output printed"
  assert_line "$OUT" "ci-gates: check ok" "check still passes"
  assert_line "$OUT" "ci-gates: FAIL cortex/changes/x" "the folder fails"
  assert_line "$OUT" "ci-gates: 1 failed" "one failure counted"
  assert_true "the count is the last line" test "$(last_line "$OUT")" = "ci-gates: 1 failed"
}

case_tampered_gates_and_check() {
  # every checker on the branch lies; the base copies still catch both
  # plants, and every step runs after the first failure (two counted)
  local d; d="$(ci_repo)"
  printf '#!/usr/bin/env bash\necho "gates: ok"\nexit 0\n' > "$d/cortex/bin/gates.sh"
  printf '#!/usr/bin/env bash\necho "check: ok"\nexit 0\n' > "$d/cortex/bin/check.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/cortex/bin/tests-locked.sh"
  printf 'echo weakened\n' > "$d/tests/a.test.sh"
  # C12 reads cortex/AGENTS.md (the router) in 3.0.0 (check table); path only
  append "$d/cortex/AGENTS.md" "TODO: planted"
  commit_all "$d" "tamper"
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "two failures -> exit 1"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: FAIL check
ci-gates: FAIL cortex/changes/x
ci-gates: 2 failed" "both failures reported, in order"
  assert_contains "$OUT" "LOCK modified: tests/a.test.sh" "pre-existing locked test caught by the base checker"
}

case_from_subdir() {
  local d; d="$(ci_repo)"
  printf 'echo weakened\n' > "$d/tests/b.test.sh"
  commit_all "$d" "weaken"
  run bash -c 'cd "$1/src" && bash ../cortex/bin/ci-gates.sh "$2"' _ "$d" "$BASE"
  assert_exit 1 "$CODE" "from a subdirectory: still fails"
  assert_line "$OUT" "ci-gates: using scripts from $BASE" "uses base scripts from a subdirectory"
  assert_line "$OUT" "ci-gates: check ok" "check runs on the repo root"
  assert_line "$OUT" "ci-gates: FAIL cortex/changes/x" "folder named relative to the root"
  assert_contains "$OUT" "LOCK modified: tests/b.test.sh" "the weakened test is named"
  assert_line "$OUT" "ci-gates: 1 failed" "one failure counted"
}

case_from_subdir_clean() {
  local d; d="$(ci_repo)"
  run bash -c 'cd "$1/src" && bash ../cortex/bin/ci-gates.sh "$2"' _ "$d" "$BASE"
  assert_exit 0 "$CODE" "clean from a subdirectory -> exit 0"
  assert_line "$OUT" "ci-gates: cortex/changes/x ok" "folder gated from a subdirectory"
  assert_line "$OUT" "ci-gates: ok" "ends ok"
}

# ---- AC22 no cortex at the base -----------------------------------------------------

# pre_cortex_repo -> base commit without cortex (origin/main), then on branch
# "feature" cortex installed, filled and committed
#
# 3.0.0 (spec criterion 45): the fallback is keyed on the base having no
# cortex/bin/ (2.x keyed it on scripts/cortex/). This base has neither, so
# these cases exercise the 3.0.0 fallback unchanged; the install comes from
# bin/install.sh (spec "Layouts").
pre_cortex_repo() {
  local d
  d="$(new_git_repo)"
  printf '# app\n' > "$d/README.md"
  mkdir -p "$d/src"; printf 'app\n' > "$d/src/app.txt"
  commit_all "$d" "base without cortex"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q -b feature
  "$ROOT/bin/install.sh" "$d" >/dev/null || return 1
  fill_install "$d" || return 1
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
  lock_folder "$d" cortex/changes/x
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "branch copy gates the new lock"
  expect_ci_lines "$NOTE_LINE
ci-gates: check ok
ci-gates: cortex/changes/x ok
ci-gates: ok" "note, check, folder, ok"
}

case_no_cortex_at_base_uses_branch_copy() {
  # evidence the branch copy really runs: a branch check.sh that fails
  local d; d="$(pre_cortex_repo)"
  printf '#!/usr/bin/env bash\necho "branch-check-marker"\nexit 1\n' > "$d/cortex/bin/check.sh"
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
  assert_line "$OUT" "ci-gates: cortex/changes/x ok" "folder still gated"
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
ci-gates: FAIL cortex/changes/x
ci-gates: 2 failed" "all steps run and both failures count"
}

# ---- AC29/AC70 (Amendments 4 and 11): archived folders; a dropped lock ----------
#
# Amendment 11, M4: a branch that adds a lock.md and no longer has it at HEAD
# (deleted, or its folder moved under cortex/changes/archive/) fails for that folder.
# Archiving a folder whose lock.md is already on the base stays ungated (D2).

# expect_dropped_lock msg : ci-gates fails for cortex/changes/x, and nothing else
expect_dropped_lock() {
  assert_exit 1 "$CODE" "$1: exit 1"
  if grep -qE '^ci-gates: FAIL cortex/changes/(archive/)?x( |:|$)' <<<"$OUT"; then pass
  else fail "$1: a ci-gates: FAIL line for the folder"; show_output; fi
  assert_line "$OUT" "ci-gates: check ok" "$1: check still passes"
  assert_true "$1: one failure counted, as the last line" test "$(last_line "$OUT")" = "ci-gates: 1 failed"
}

case_archived_on_branch() {
  # was AC29's "folder archived on the branch is not gated": the lock was
  # added on this branch, so moving it away drops it (AC70)
  local d; d="$(ci_repo)"
  git -C "$d" mv cortex/changes/x cortex/changes/archive/x
  git -C "$d" commit -q -m "archive cortex/changes/x"
  assert_file_exists "$d/cortex/changes/archive/x/lock.md" "fixture: lock.md now under cortex/changes/archive/"
  ci_gates "$d" "$BASE"
  expect_dropped_lock "lock added on the branch, then its folder archived"
}

case_added_lock_deleted() {
  local d; d="$(ci_repo)"
  git -C "$d" rm -q cortex/changes/x/lock.md
  git -C "$d" commit -q -m "drop the lock"
  assert_file_absent "$d/cortex/changes/x/lock.md" "fixture: lock.md deleted"
  assert_true "fixture: the base has no cortex/changes/x/lock.md" \
    bash -c '! git -C "$1" cat-file -e "$2:cortex/changes/x/lock.md" 2>/dev/null' _ "$d" "$BASE"
  ci_gates "$d" "$BASE"
  expect_dropped_lock "lock added on the branch, then deleted"
}

# ---- AC72 (Amendment 12, N1): a merge can't hide the lock commit ------------------
#
# The tip is a merge whose first parent is T (the tests commit, before the
# lock: no cortex/changes/x/lock.md) and whose second parent is the lock commit L,
# keeping T's tree for cortex/changes/x. A pathspec git log simplifies history and
# prunes the L side, so the dropped lock is only seen by reading every commit.

# pruned_lock_merge DIR [archive|archive-first] : make HEAD such a merge,
# built with plumbing so the shape is exact. The tree is the first parent's
# plus src/impl.txt. With "archive", the merge also places L's lock.md at
# cortex/changes/archive/x/lock.md. With "archive-first", the first parent is P, a
# child of T (a sibling of L) that already holds that archived copy, so the
# merge equals P for every lock.md path and any pathspec log prunes L.
pruned_lock_merge() {
  local d="$1" first l blob tree m
  [ -n "$d" ] && [ -d "$d" ] || return 1
  l="$(git -C "$d" rev-parse HEAD)"
  first="$(git -C "$d" rev-parse HEAD^1)"
  blob="$(git -C "$d" rev-parse "$l:cortex/changes/x/lock.md")"
  git -C "$d" checkout -q "$first"
  if [ "${2-}" = archive-first ]; then
    git -C "$d" update-index --add --cacheinfo "100644,$blob,cortex/changes/archive/x/lock.md"
    tree="$(git -C "$d" write-tree)"
    first="$(printf 'archive copy of the lock, before the merge\n' | git -C "$d" commit-tree "$tree" -p "$first")"
    git -C "$d" checkout -q "$first"
  fi
  printf 'impl\n' > "$d/src/impl.txt"
  git -C "$d" add src/impl.txt
  if [ "${2-}" = archive ]; then
    git -C "$d" update-index --add --cacheinfo "100644,$blob,cortex/changes/archive/x/lock.md"
  fi
  tree="$(git -C "$d" write-tree)"
  m="$(printf 'merge the lock, keeping the pre-lock tree\n' | git -C "$d" commit-tree "$tree" -p "$first" -p "$l")"
  git -C "$d" checkout -q feature
  git -C "$d" reset -q --hard "$m"
}

# expect_pruned_shape DIR : fixture checks that HEAD is the pruned-side merge
expect_pruned_shape() {
  local d="$1"
  [ -n "$d" ] && [ -d "$d" ] || return 1
  assert_true "fixture: HEAD^1 has no cortex/changes/x/lock.md" \
    bash -c '! git -C "$1" cat-file -e HEAD^1:cortex/changes/x/lock.md 2>/dev/null' _ "$d"
  assert_true "fixture: HEAD^2 is the lock commit (adds cortex/changes/x/lock.md)" \
    test -n "$(git -C "$d" diff --name-only --diff-filter=A HEAD^2^ HEAD^2 -- cortex/changes/x/lock.md)"
  assert_file_absent "$d/cortex/changes/x/lock.md" "fixture: no cortex/changes/x/lock.md at HEAD"
  assert_true "fixture: the base has no cortex/changes/x/lock.md" \
    bash -c '! git -C "$1" cat-file -e "$2:cortex/changes/x/lock.md" 2>/dev/null' _ "$d" "$BASE"
  assert_true "fixture: a plain pathspec git log prunes the lock commit" \
    test -z "$(git -C "$d" log --format=%H "$BASE..HEAD" -- cortex/changes/x/lock.md)"
}

case_AC72_merge_prunes_lock() {
  local d; d="$(ci_repo)"
  pruned_lock_merge "$d"
  expect_pruned_shape "$d"
  assert_file_exists "$d/src/impl.txt" "fixture: the merge added an implementation file"
  ci_gates "$d" "$BASE"
  expect_dropped_lock "merge whose first parent predates the lock"
  assert_line "$OUT" "ci-gates: FAIL cortex/changes/x (lock.md added on this branch is gone)" \
    "the dropped-lock line names cortex/changes/x"
}

case_AC72_merge_prunes_lock_archived() {
  local d; d="$(ci_repo)"
  pruned_lock_merge "$d" archive
  expect_pruned_shape "$d"
  assert_file_exists "$d/cortex/changes/archive/x/lock.md" "fixture: lock.md now under cortex/changes/archive/x"
  ci_gates "$d" "$BASE"
  expect_dropped_lock "merge whose first parent predates the lock, folder archived"
  assert_true "the dropped-lock line names the folder" \
    grep -qxE 'ci-gates: FAIL cortex/changes/(archive/)?x \(lock\.md added on this branch is gone\)' <<<"$OUT"
}

case_AC72_merge_prunes_lock_archived_first_parent() {
  local d l; d="$(ci_repo)"
  l="$(git -C "$d" rev-parse HEAD)"
  pruned_lock_merge "$d" archive-first
  expect_pruned_shape "$d"
  assert_file_exists "$d/cortex/changes/archive/x/lock.md" "fixture: lock.md under cortex/changes/archive/x"
  assert_true "fixture: the merge equals its first parent for every lock.md path" \
    git -C "$d" diff --quiet HEAD^1 HEAD -- 'cortex/changes/*lock.md'
  assert_true "fixture: a pathspec log over every lock.md prunes the lock commit" \
    bash -c '! git -C "$1" log --format=%H "$2..HEAD" -- "cortex/changes/*lock.md" | grep -qxF "$3"' _ "$d" "$BASE" "$l"
  ci_gates "$d" "$BASE"
  expect_dropped_lock "merge pruning the lock, archived copy on the first parent"
  assert_true "the dropped-lock line names the folder" \
    grep -qxE 'ci-gates: FAIL cortex/changes/(archive/)?x \(lock\.md added on this branch is gone\)' <<<"$OUT"
}

# ---- AC74 (Amendment 12, N1): a lock.md that only merges touch --------------------

# side_commit DIR NAME -> sha of a commit off the base adding src/NAME.txt
side_commit() {
  local d="$1" tree
  [ -n "$d" ] && [ -d "$d" ] || return 1
  git -C "$d" read-tree "$BASE"
  printf '%s\n' "$2" > "$d/src/$2.txt"
  git -C "$d" add "src/$2.txt"
  tree="$(git -C "$d" write-tree)"
  printf 'side: %s\n' "$2" | git -C "$d" commit-tree "$tree" -p "$BASE"
}

case_AC74_lock_only_in_merges() {
  # T adds the tests; merge M1 (T + side1) adds cortex/changes/x/lock.md naming T,
  # which neither parent has; merge M2 (M1 + side2) removes it. No ordinary
  # commit touches the path. Built with plumbing so the shape is exact.
  local d t s1 s2 blob tree m1 m2
  d="$(base_only)"
  printf 'echo b\n' > "$d/tests/b.test.sh"
  commit_all "$d" "add tests for cortex/changes/x"
  t="$(git -C "$d" rev-parse HEAD)"
  s1="$(side_commit "$d" side1)"
  s2="$(side_commit "$d" side2)"
  blob="$(printf 'Tests-locked-at: %s\n\n## Locked tests\n\n- tests/b.test.sh\n' "$t" \
    | git -C "$d" hash-object -w --stdin)"
  git -C "$d" read-tree "$t"
  git -C "$d" update-index --add --cacheinfo "100644,$(git -C "$d" rev-parse "$s1:src/side1.txt"),src/side1.txt"
  git -C "$d" update-index --add --cacheinfo "100644,$blob,cortex/changes/x/lock.md"
  tree="$(git -C "$d" write-tree)"
  m1="$(printf 'merge side1 (adds the lock)\n' | git -C "$d" commit-tree "$tree" -p "$t" -p "$s1")"
  git -C "$d" update-index --force-remove cortex/changes/x/lock.md
  git -C "$d" update-index --add --cacheinfo "100644,$(git -C "$d" rev-parse "$s2:src/side2.txt"),src/side2.txt"
  tree="$(git -C "$d" write-tree)"
  m2="$(printf 'merge side2 (drops the lock)\n' | git -C "$d" commit-tree "$tree" -p "$m1" -p "$s2")"
  git -C "$d" reset -q --hard "$m2"

  assert_true "fixture: HEAD is a merge" git -C "$d" cat-file -e HEAD^2
  assert_true "fixture: HEAD^1 is a merge whose first parent is T" \
    test "$(git -C "$d" rev-parse HEAD^1^1)" = "$t" -a -n "$(git -C "$d" rev-parse -q --verify HEAD^1^2)"
  assert_true "fixture: the first merge's first parent has no cortex/changes/x/lock.md" \
    bash -c '! git -C "$1" cat-file -e HEAD^1^1:cortex/changes/x/lock.md 2>/dev/null' _ "$d"
  assert_true "fixture: the first merge's second parent has no cortex/changes/x/lock.md" \
    bash -c '! git -C "$1" cat-file -e HEAD^1^2:cortex/changes/x/lock.md 2>/dev/null' _ "$d"
  assert_true "fixture: the first merge's tree has cortex/changes/x/lock.md" \
    git -C "$d" cat-file -e HEAD^1:cortex/changes/x/lock.md
  assert_file_absent "$d/cortex/changes/x/lock.md" "fixture: no cortex/changes/x/lock.md at HEAD"
  assert_true "fixture: the base has no cortex/changes/x/lock.md" \
    bash -c '! git -C "$1" cat-file -e "$2:cortex/changes/x/lock.md" 2>/dev/null' _ "$d" "$BASE"
  assert_true "fixture: no ordinary commit on the branch touches cortex/changes/x/lock.md" \
    test -z "$(git -C "$d" log --no-merges --full-history --format=%H "$BASE..HEAD" -- cortex/changes/x/lock.md)"
  assert_true "fixture: the side commits don't touch cortex/changes/" \
    test -z "$(git -C "$d" diff --name-only "$BASE" "$s1" -- cortex/changes)$(git -C "$d" diff --name-only "$BASE" "$s2" -- cortex/changes)"
  ci_gates "$d" "$BASE"
  expect_dropped_lock "lock.md added and removed only by merges"
  assert_line "$OUT" "ci-gates: FAIL cortex/changes/x (lock.md added on this branch is gone)" \
    "the dropped-lock line names cortex/changes/x"
}

# ---- AC75 (Amendment 12, N1): a lock path the base ever had is the base's --------
#
# Guards existing behavior: merging a base that deleted or archived a finished
# change's lock.md lists that path in the merge, but the branch never added it.

# base_with_y_lock -> filled install with a finished change cortex/changes/y (lock.md
# and tasks.md) committed as the base; feature branched off it with one
# ordinary commit
base_with_y_lock() {
  local d
  d="$(filled_install)" || return 1
  mkdir -p "$d/tests" "$d/src" "$d/cortex/changes/y"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  printf 'app\n' > "$d/src/app.txt"
  printf 'Tests-locked-at: 0000000000000000000000000000000000000000\n\n## Locked tests\n\n- tests/a.test.sh\n' \
    > "$d/cortex/changes/y/lock.md"
  printf '# tasks\n' > "$d/cortex/changes/y/tasks.md"
  commit_all "$d" "base with a finished change folder"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q -b feature
  printf 'app v2\n' > "$d/src/app.txt"
  commit_all "$d" "feature work"
  printf '%s\n' "$d"
}

# base_then_merge DIR : with the base's new commit made on main (checked out),
# point origin/main at it and merge it into feature with a real merge commit
base_then_merge() {
  [ -n "$1" ] && [ -d "$1" ] || return 1
  git -C "$1" update-ref "refs/remotes/$BASE" HEAD
  git -C "$1" checkout -q feature
  git -C "$1" merge -q --no-ff --no-edit "$BASE"
}

# expect_y_merge_shape DIR : fixture checks shared by the AC75 cases
expect_y_merge_shape() {
  [ -n "$1" ] && [ -d "$1" ] || return 1
  assert_true "fixture: the base tip has no cortex/changes/y/lock.md" \
    bash -c '! git -C "$1" cat-file -e "$2:cortex/changes/y/lock.md" 2>/dev/null' _ "$1" "$BASE"
  assert_file_absent "$1/cortex/changes/y/lock.md" "fixture: no cortex/changes/y/lock.md at HEAD"
  assert_true "fixture: HEAD is a merge" git -C "$1" cat-file -e HEAD^2
}

case_AC75_base_deleted_lock_merged() {
  local d; d="$(base_with_y_lock)"
  git -C "$d" checkout -q -B main "$BASE"
  git -C "$d" rm -q cortex/changes/y/lock.md
  git -C "$d" commit -q -m "base: drop the finished change's lock"
  base_then_merge "$d"
  expect_y_merge_shape "$d"
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "merging a base that deleted cortex/changes/y/lock.md -> exit 0"
  assert_not_contains "$OUT" "FAIL cortex/changes/y" "no failure for cortex/changes/y"
  assert_true "ci-gates: ok is the last line" test "$(last_line "$OUT")" = "ci-gates: ok"
}

case_AC75_base_archived_lock_merged() {
  local d; d="$(base_with_y_lock)"
  git -C "$d" checkout -q -B main "$BASE"
  git -C "$d" mv cortex/changes/y cortex/changes/archive/y
  printf '%s\n' 'Tests-locked-at: 2222222222222222222222222222222222222222' \
    'Re-lock signed off by: Pat Maintainer' '' '## Locked tests' '' \
    '- tests/archived-one.test.sh' '- tests/archived-two.test.sh' '- tests/archived-three.test.sh' \
    '' '## Notes' '' 'Archived after release; the locked set was rewritten here' \
    'so that git sees no rename between the two paths.' \
    > "$d/cortex/changes/archive/y/lock.md"
  commit_all "$d" "base: archive cortex/changes/y, rewriting its lock"
  base_then_merge "$d"
  expect_y_merge_shape "$d"
  assert_file_exists "$d/cortex/changes/archive/y/lock.md" "fixture: the archived lock.md is at HEAD"
  assert_true "fixture: git log -m lists cortex/changes/y/lock.md for the merge (no rename seen)" \
    bash -c 'git -C "$1" log -m -1 --name-only --format= HEAD | grep -qxF cortex/changes/y/lock.md' _ "$d"
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "merging a base that archived and rewrote cortex/changes/y/lock.md -> exit 0"
  assert_not_contains "$OUT" "FAIL cortex/changes/y" "no failure for cortex/changes/y"
  assert_not_contains "$OUT" "FAIL cortex/changes/archive/y" "no failure for cortex/changes/archive/y"
}

# ---- AC76/AC77 (Amendment 12, N1 revised): added means against every parent ------
#
# A path is added on this branch when a branch commit has it and none of its
# parents does; paths compare literally; only the base's tip is exempt.

case_AC76_pattern_folder_name() {
  # the base has cortex/changes/old/lock.md; the branch locks cortex/changes/[o]ld (a
  # pattern that would match cortex/changes/old) and then deletes that lock.md
  local d f='cortex/changes/[o]ld'; d="$(base_with_old_lock)"
  printf 'echo b\n' > "$d/tests/b.test.sh"
  lock_tests "$d" "$f" tests/b.test.sh
  rm "$d/$f/lock.md"
  commit_all "$d" "drop the [o]ld lock"
  assert_true "fixture: the folder name is literal on disk" test -d "$d/$f"
  assert_true "fixture: HEAD^ has the literal path cortex/changes/[o]ld/lock.md" \
    bash -c 'git -C "$1" ls-tree -r --name-only HEAD^ | grep -qxF "cortex/changes/[o]ld/lock.md"' _ "$d"
  assert_true "fixture: HEAD has no cortex/changes/[o]ld/lock.md" \
    bash -c '! git -C "$1" cat-file -e "HEAD:cortex/changes/[o]ld/lock.md" 2>/dev/null' _ "$d"
  assert_file_absent "$d/$f/lock.md" "fixture: no cortex/changes/[o]ld/lock.md on disk"
  assert_true "fixture: the base has cortex/changes/old/lock.md" \
    git -C "$d" cat-file -e "$BASE:cortex/changes/old/lock.md"
  assert_true "fixture: HEAD still has cortex/changes/old/lock.md" \
    git -C "$d" cat-file -e "HEAD:cortex/changes/old/lock.md"
  assert_true "fixture: the base has no cortex/changes/[o]ld/lock.md" \
    bash -c '! git -C "$1" cat-file -e "$2:cortex/changes/[o]ld/lock.md" 2>/dev/null' _ "$d" "$BASE"
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "lock added at cortex/changes/[o]ld, then deleted -> exit 1"
  assert_line "$OUT" "ci-gates: FAIL cortex/changes/[o]ld (lock.md added on this branch is gone)" \
    "the dropped-lock line names cortex/changes/[o]ld literally"
  assert_line "$OUT" "ci-gates: check ok" "check still passes"
  assert_true "one failure counted, as the last line" test "$(last_line "$OUT")" = "ci-gates: 1 failed"
}

case_AC77_reused_folder_name() {
  # the base finished cortex/changes/x and archived it; the branch reuses the name,
  # locks it, and drops the new lock
  local d; d="$(base_only)"
  git -C "$d" checkout -q -B main "$BASE"
  mkdir -p "$d/cortex/changes/x"
  printf 'Tests-locked-at: 0000000000000000000000000000000000000000\n\n## Locked tests\n\n- tests/a.test.sh\n' \
    > "$d/cortex/changes/x/lock.md"
  printf '# tasks\n' > "$d/cortex/changes/x/tasks.md"
  commit_all "$d" "base: finished change x"
  git -C "$d" mv cortex/changes/x cortex/changes/archive/x
  git -C "$d" commit -q -m "base: archive cortex/changes/x"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q feature
  git -C "$d" reset -q --hard "$BASE"
  printf 'echo b\n' > "$d/tests/b.test.sh"
  lock_folder "$d" cortex/changes/x
  git -C "$d" rm -q cortex/changes/x/lock.md
  git -C "$d" commit -q -m "drop the new lock"
  assert_true "fixture: the base tip has no cortex/changes/x/lock.md" \
    bash -c '! git -C "$1" cat-file -e "$2:cortex/changes/x/lock.md" 2>/dev/null' _ "$d" "$BASE"
  assert_true "fixture: the base's history has cortex/changes/x/lock.md" \
    test -n "$(git -C "$d" log --format=%H "$BASE" -- cortex/changes/x/lock.md)"
  assert_true "fixture: the branch added cortex/changes/x/lock.md (HEAD^ has it)" \
    git -C "$d" cat-file -e HEAD^:cortex/changes/x/lock.md
  assert_file_absent "$d/cortex/changes/x/lock.md" "fixture: no cortex/changes/x/lock.md at HEAD"
  ci_gates "$d" "$BASE"
  expect_dropped_lock "lock added at a folder name the base used before, then deleted"
  assert_line "$OUT" "ci-gates: FAIL cortex/changes/x (lock.md added on this branch is gone)" \
    "the dropped-lock line names cortex/changes/x"
}

# ---- AC78-AC81 (Amendment 12, N1 tree-based): every lock a branch commit holds ----

DROPPED_X="ci-gates: FAIL cortex/changes/x (lock.md added on this branch is gone)"

case_AC78_lock_replaced_by_directory() {
  local d; d="$(ci_repo)"
  git -C "$d" rm -q cortex/changes/x/lock.md
  mkdir -p "$d/cortex/changes/x/lock.md"
  printf 'not a lock\n' > "$d/cortex/changes/x/lock.md/note.txt"
  commit_all "$d" "replace the lock with a directory"
  assert_true "fixture: HEAD's cortex/changes/x/lock.md is a tree" \
    bash -c 'git -C "$1" ls-tree HEAD cortex/changes/x/lock.md | grep -q "^040000 tree "' _ "$d"
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "lock.md replaced by a directory -> exit 1"
  assert_line "$OUT" "$DROPPED_X" "the dropped-lock line names cortex/changes/x"
  assert_line "$OUT" "ci-gates: check ok" "check still passes"
}

case_AC78_lock_replaced_by_symlink() {
  # built with plumbing (core.symlinks may be false); the working tree is
  # made to match a checkout: a symlink where symlinks work, else a plain
  # file holding the target
  local d target='../../tests/b.test.sh' blob; d="$(ci_repo)"
  blob="$(printf '%s' "$target" | git -C "$d" hash-object -w --stdin)"
  git -C "$d" rm -q --cached cortex/changes/x/lock.md
  git -C "$d" update-index --add --cacheinfo "120000,$blob,cortex/changes/x/lock.md"
  git -C "$d" commit -q -m "replace the lock with a symlink"
  rm -f "$d/cortex/changes/x/lock.md"
  git -C "$d" checkout -q -- cortex/changes/x/lock.md
  assert_true "fixture: HEAD's cortex/changes/x/lock.md has mode 120000" \
    bash -c 'git -C "$1" ls-tree HEAD cortex/changes/x/lock.md | grep -q "^120000 blob "' _ "$d"
  assert_true "fixture: the working tree matches HEAD" test -z "$(git -C "$d" status --porcelain)"
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "lock.md replaced by a symlink -> exit 1"
  assert_line "$OUT" "$DROPPED_X" "the dropped-lock line names cortex/changes/x"
  assert_line "$OUT" "ci-gates: check ok" "check still passes"
}

case_AC79_merge_with_old_base_commit() {
  # the base had cortex/changes/x/lock.md at B1, then archived it; the branch
  # merges B1 with a NEW cortex/changes/x/lock.md, then drops it with a test edit
  local d b1 p blob tree m; d="$(base_only)"
  git -C "$d" checkout -q -B main "$BASE"
  mkdir -p "$d/cortex/changes/x"
  printf 'Tests-locked-at: 0000000000000000000000000000000000000000\n\n## Locked tests\n\n- tests/a.test.sh\n' \
    > "$d/cortex/changes/x/lock.md"
  printf '# tasks\n' > "$d/cortex/changes/x/tasks.md"
  commit_all "$d" "base: change x (B1)"
  b1="$(git -C "$d" rev-parse HEAD)"
  git -C "$d" mv cortex/changes/x cortex/changes/archive/x
  git -C "$d" commit -q -m "base: archive cortex/changes/x"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q feature
  git -C "$d" reset -q --hard "$BASE"
  printf 'echo b\n' > "$d/tests/b.test.sh"
  commit_all "$d" "add tests for cortex/changes/x (P)"
  p="$(git -C "$d" rev-parse HEAD)"
  blob="$(printf 'Tests-locked-at: %s\n\n## Locked tests\n\n- tests/b.test.sh\n' "$p" \
    | git -C "$d" hash-object -w --stdin)"
  git -C "$d" update-index --add --cacheinfo "100644,$blob,cortex/changes/x/lock.md"
  tree="$(git -C "$d" write-tree)"
  m="$(printf 'merge B1, with a new lock\n' | git -C "$d" commit-tree "$tree" -p "$p" -p "$b1")"
  git -C "$d" reset -q --hard "$m"
  printf 'echo weakened\n' > "$d/tests/b.test.sh"
  git -C "$d" rm -q cortex/changes/x/lock.md
  commit_all "$d" "weaken the test, drop the lock"
  assert_true "fixture: HEAD~1 is a merge with B1 as its second parent" \
    test "$(git -C "$d" rev-parse HEAD~1^2)" = "$b1"
  assert_true "fixture: the merge's lock.md differs from B1's" \
    test "$(git -C "$d" rev-parse HEAD~1:cortex/changes/x/lock.md)" != "$(git -C "$d" rev-parse "$b1:cortex/changes/x/lock.md")"
  assert_true "fixture: the base tip has no cortex/changes/x/lock.md" \
    bash -c '! git -C "$1" cat-file -e "$2:cortex/changes/x/lock.md" 2>/dev/null' _ "$d" "$BASE"
  assert_file_absent "$d/cortex/changes/x/lock.md" "fixture: no cortex/changes/x/lock.md at HEAD"
  ci_gates "$d" "$BASE"
  expect_dropped_lock "new lock in a merge with an old base commit, then dropped"
  assert_line "$OUT" "$DROPPED_X" "the dropped-lock line names cortex/changes/x"
}

# a folder name holding a tab; git prints the lock.md path quoted
TAB_FOLDER="cortex/changes/a$(printf '\t')b"
QUOTED_LINE='ci-gates: FAIL "cortex/changes/a\tb/lock.md" (a lock.md path git has to quote, so CI can'"'"'t check it)'

# tab_lock DIR : commit everything as T, then TAB_FOLDER/lock.md naming T,
# with plumbing (a Windows filesystem can't hold a tab; there the working
# tree lacks the file, elsewhere a checkout writes it)
tab_lock() {
  local d="$1" t blob
  [ -n "$d" ] && [ -d "$d" ] || return 1
  commit_all "$d" "add tests for the tab folder"
  t="$(git -C "$d" rev-parse HEAD)"
  blob="$(printf 'Tests-locked-at: %s\n\n## Locked tests\n\n- tests/b.test.sh\n' "$t" \
    | git -C "$d" hash-object -w --stdin)"
  git -C "$d" -c core.protectNTFS=false update-index --add --cacheinfo "100644,$blob,$TAB_FOLDER/lock.md"
  git -C "$d" commit -q -m "lock the tab folder"
  git -C "$d" -c core.protectNTFS=false checkout -q -- . 2>/dev/null || true
}

case_AC80_tab_folder_kept() {
  local d; d="$(base_only)"
  printf 'echo b\n' > "$d/tests/b.test.sh"
  tab_lock "$d"
  assert_true "fixture: git prints HEAD's lock path quoted" \
    bash -c 'git -C "$1" ls-tree -r --name-only HEAD | grep -qxF "\"cortex/changes/a\\tb/lock.md\""' _ "$d"
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "lock at a folder name with a tab, kept -> exit 1"
  assert_line "$OUT" "$QUOTED_LINE" "the quoted-path line"
}

case_AC80_tab_folder_deleted() {
  local d; d="$(base_only)"
  printf 'echo b\n' > "$d/tests/b.test.sh"
  tab_lock "$d"
  git -C "$d" -c core.protectNTFS=false update-index --force-remove "$TAB_FOLDER/lock.md"
  git -C "$d" commit -q -m "drop the tab folder's lock"
  rm -rf "${d:?}/$TAB_FOLDER"
  assert_true "fixture: git prints HEAD^'s lock path quoted" \
    bash -c 'git -C "$1" ls-tree -r --name-only HEAD^ | grep -qxF "\"cortex/changes/a\\tb/lock.md\""' _ "$d"
  assert_true "fixture: HEAD has no lock under the tab folder" \
    test -z "$(git -C "$d" ls-tree -r --name-only HEAD -- changes | grep -F 'cortex/changes/a\tb' || true)"
  assert_true "fixture: the working tree matches HEAD" test -z "$(git -C "$d" status --porcelain)"
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "lock at a folder name with a tab, deleted -> exit 1"
  assert_line "$OUT" "$QUOTED_LINE" "the quoted-path line"
}

case_AC81_stacked_after_squash() {
  # branch A locks cortex/changes/a; B builds on A; A is squash-merged into the
  # base, which then archives cortex/changes/a; B merges the base and removes its
  # leftover cortex/changes/a
  local d la sq; d="$(base_only)"
  printf 'echo b\n' > "$d/tests/b.test.sh"
  lock_folder "$d" cortex/changes/a
  la="$(git -C "$d" rev-parse HEAD)"
  git -C "$d" checkout -q -b stacked
  printf 'more\n' > "$d/src/more.txt"
  commit_all "$d" "B: unrelated work"
  git -C "$d" checkout -q -B main "$BASE"
  git -C "$d" merge -q --squash "$la" >/dev/null
  git -C "$d" commit -q -m "squash-merge A"
  sq="$(git -C "$d" rev-parse HEAD)"
  git -C "$d" mv cortex/changes/a cortex/changes/archive/a
  git -C "$d" commit -q -m "base: archive cortex/changes/a"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q stacked
  git -C "$d" merge -q --no-ff --no-edit "$BASE"
  git -C "$d" rm -q -r cortex/changes/a
  git -C "$d" commit -q -m "B: remove the leftover cortex/changes/a"
  assert_true "fixture: the squash commit is an ordinary commit" \
    bash -c '! git -C "$1" cat-file -e "$2^2" 2>/dev/null' _ "$d" "$sq"
  assert_true "fixture: the squash commit holds A's lock.md blob" \
    test "$(git -C "$d" rev-parse "$sq:cortex/changes/a/lock.md")" = "$(git -C "$d" rev-parse "$la:cortex/changes/a/lock.md")"
  assert_true "fixture: HEAD^ is a merge of the base" \
    test "$(git -C "$d" rev-parse HEAD^^2)" = "$(git -C "$d" rev-parse "$BASE")"
  assert_true "fixture: HEAD has no cortex/changes/a/lock.md" \
    bash -c '! git -C "$1" cat-file -e HEAD:cortex/changes/a/lock.md 2>/dev/null' _ "$d"
  ci_gates "$d" "$BASE"
  assert_not_contains "$OUT" "ci-gates: FAIL cortex/changes/a (lock.md added on this branch is gone)" \
    "no dropped-lock failure for cortex/changes/a"
  assert_not_contains "$OUT" "ci-gates: FAIL cortex/changes/a" "no failure for cortex/changes/a at all"
}

# ---- AC82/AC83 (Amendment 12, N1): fixtures and inherited quoted paths -------------

case_AC82_nested_fixture_lock_deleted() {
  # the base has cortex/changes/y/lock.md; the branch adds a fixture
  # cortex/changes/y/fixtures/lock.md (two folders deep: not a lock), locks
  # cortex/changes/x as usual, then deletes the fixture
  local d
  d="$(filled_install)" || return 1
  [ -n "$d" ] && [ -d "$d" ] || return 1
  mkdir -p "$d/tests" "$d/src" "$d/cortex/changes/y"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  printf 'app\n' > "$d/src/app.txt"
  printf 'Tests-locked-at: 0000000000000000000000000000000000000000\n\n## Locked tests\n\n- tests/a.test.sh\n' \
    > "$d/cortex/changes/y/lock.md"
  printf '# tasks\n' > "$d/cortex/changes/y/tasks.md"
  commit_all "$d" "base with change folder y"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q -b feature
  mkdir -p "$d/cortex/changes/y/fixtures"
  printf 'Tests-locked-at: 1111111111111111111111111111111111111111\n\n## Locked tests\n\n- tests/fixture.test.sh\n' \
    > "$d/cortex/changes/y/fixtures/lock.md"
  commit_all "$d" "add a lock.md fixture under cortex/changes/y"
  printf 'echo b\n' > "$d/tests/b.test.sh"
  lock_folder "$d" cortex/changes/x
  git -C "$d" rm -q cortex/changes/y/fixtures/lock.md
  git -C "$d" commit -q -m "drop the fixture"
  assert_true "fixture: a branch commit held cortex/changes/y/fixtures/lock.md" \
    test -n "$(git -C "$d" log --format=%H "$BASE..HEAD" -- cortex/changes/y/fixtures/lock.md)"
  assert_true "fixture: HEAD has no cortex/changes/y/fixtures/lock.md" \
    bash -c '! git -C "$1" cat-file -e HEAD:cortex/changes/y/fixtures/lock.md 2>/dev/null' _ "$d"
  assert_true "fixture: cortex/changes/y/lock.md kept at HEAD" git -C "$d" cat-file -e HEAD:cortex/changes/y/lock.md
  ci_gates "$d" "$BASE"
  assert_not_contains "$OUT" "ci-gates: FAIL cortex/changes/y" "no failure for cortex/changes/y or cortex/changes/y/fixtures"
  assert_exit 0 "$CODE" "a deleted nested fixture -> exit 0"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: cortex/changes/x ok
ci-gates: ok" "cortex/changes/x gated, nothing else"
}

case_AC83_inherited_tab_lock() {
  # the base's tip holds a lock at a folder whose name has a tab (plumbing,
  # as in tab_lock); the branch makes an unrelated commit outside cortex/changes/
  local d
  d="$(filled_install)" || return 1
  [ -n "$d" ] && [ -d "$d" ] || return 1
  mkdir -p "$d/tests" "$d/src"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  printf 'app\n' > "$d/src/app.txt"
  printf 'echo b\n' > "$d/tests/b.test.sh"
  tab_lock "$d"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q -b feature 2>/dev/null
  printf 'app v2\n' > "$d/src/app.txt"
  git -C "$d" add src/app.txt   # not add -A: Windows can't hold the tab path
  git -C "$d" commit -q -m "unrelated work"
  assert_true "fixture: the base tip holds the quoted lock path" \
    bash -c 'git -C "$1" ls-tree -r --name-only "$2" | grep -qxF "\"cortex/changes/a\\tb/lock.md\""' _ "$d" "$BASE"
  assert_true "fixture: HEAD holds it with the same blob" \
    test "$(git -C "$d" rev-parse "HEAD:$TAB_FOLDER/lock.md")" = "$(git -C "$d" rev-parse "$BASE:$TAB_FOLDER/lock.md")"
  assert_true "fixture: the branch touches nothing under cortex/changes/" \
    test -z "$(git -C "$d" diff --name-only "$BASE" HEAD -- cortex/changes)"
  ci_gates "$d" "$BASE"
  assert_not_contains "$OUT" 'ci-gates: FAIL "cortex/changes/a\tb/lock.md"' "no failure for the inherited quoted path"
  assert_exit 0 "$CODE" "inherited tab-named lock -> exit 0"
  assert_true "ci-gates: ok is the last line" test "$(last_line "$OUT")" = "ci-gates: ok"
}

case_archived_after_merge() {
  # the usual order: cortex/changes/x merged into the base, then a later branch
  # archives it
  local d; d="$(ci_repo)"
  git -C "$d" update-ref "refs/remotes/$BASE" HEAD
  git -C "$d" checkout -q -b archive-x
  git -C "$d" mv cortex/changes/x cortex/changes/archive/x
  git -C "$d" commit -q -m "archive cortex/changes/x"
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "archiving a merged change -> exit 0"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: ok" "archived folder is not gated after the merge"
  assert_not_contains "$OUT" "LOCK " "the archived lock.md was not checked"
}

# ---- AC65/AC66 (Amendment 11, M1/M2): a base merge is a re-lock -----------------

# move_base DIR [no-config] : the base moves on (edits tests/a.test.sh, matched
# by TEST_GLOBS, and, unless "no-config", cortex/config; adds tests/c.test.sh);
# feature checked out again, not merged
move_base() {
  git -C "$1" checkout -q -B main "$BASE"
  printf 'echo a from base\n' > "$1/tests/a.test.sh"
  [ "${2-}" = no-config ] || append "$1/cortex/config" "# base: a later config line"
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
ci-gates: FAIL cortex/changes/x
ci-gates: 1 failed" "the folder fails after an un-relocked base merge"
}

case_base_merged_and_relocked() {
  local d m; d="$(ci_repo)"
  move_base "$d" no-config
  git -C "$d" merge -q --no-edit "$BASE"
  m="$(git -C "$d" rev-parse HEAD)"
  relock_folder "$d" cortex/changes/x
  assert_true "fixture: the re-lock follows the merge" test "$(git -C "$d" rev-parse HEAD^1)" = "$m"
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "base merged, then a signed re-lock naming the merge -> exit 0"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: cortex/changes/x ok
ci-gates: ok" "the folder is gated and passes after a re-locked base merge"
  assert_not_contains "$OUT" "LOCK " "no LOCK lines after a re-locked base merge"
}

# ---- AC35 (Amendment 6, F1): the base's parser, never the branch's ----------------

case_AC35_branch_stub_parser() {
  # the branch replaces _config.sh with one that reads nothing; the base copies
  # of check.sh and gates.sh still read the base's filled config correctly
  local d; d="$(ci_repo)"
  printf '%s\n' '# stub: config_value reads its input and prints nothing' \
    'config_value() { cat > /dev/null; }' > "$d/cortex/bin/_config.sh"
  commit_all "$d" "replace the config parser"
  assert_true "fixture: the branch's _config.sh differs from the base's" \
    test -n "$(git -C "$d" diff --name-only "$BASE" HEAD -- cortex/bin/_config.sh)"
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "ci-gates passes with the base's parser"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: cortex/changes/x ok
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
    git -C "$d" diff --quiet HEAD^1 HEAD -- cortex/changes/x/lock.md
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "side-branch weakening merged in -> exit 1"
  assert_contains "$OUT" "LOCK modified: tests/b.test.sh" "the base tests-locked.sh names the weakened test"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: FAIL cortex/changes/x
ci-gates: 1 failed" "the folder fails, nothing else"
}

# ---- spec 3.1.0 G3, criterion 10: an open task fails CI ------------------------------

case_G3_open_task_fails_ci() {
  # a pull request whose locked change folder has an open task fails; once
  # the task is ticked (and committed) it passes
  local d; d="$(base_only)"
  printf 'echo b\n' > "$d/tests/b.test.sh"
  mkdir -p "$d/cortex/changes/x"
  printf '# Tasks: x\n\n- [x] zz-done\n- [ ] zz-still-open -- done when: it runs\n\n## Manual verification\n' \
    > "$d/cortex/changes/x/tasks.md"
  lock_folder "$d" cortex/changes/x
  ci_gates "$d" "$BASE"
  assert_exit 1 "$CODE" "an open task in the locked change folder -> exit 1"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: FAIL cortex/changes/x
ci-gates: 1 failed" "the folder fails, nothing else"
  assert_line "$OUT" "gate tasks: FAIL (exit 1)" "the base gates.sh's tasks gate fails"
  assert_contains "$OUT" "zz-still-open" "the open task is named"
  assert_line "$OUT" "gate tests-locked: ok" "the lock itself is fine"
  printf '# Tasks: x\n\n- [x] zz-done\n- [x] zz-still-open -- done when: it runs\n\n## Manual verification\n' \
    > "$d/cortex/changes/x/tasks.md"
  commit_all "$d" "tick the last task"
  ci_gates "$d" "$BASE"
  assert_exit 0 "$CODE" "every task ticked -> exit 0"
  expect_ci_lines "ci-gates: using scripts from $BASE
ci-gates: check ok
ci-gates: cortex/changes/x ok
ci-gates: ok" "the folder passes once the task is ticked"
  assert_line "$OUT" "gate tasks: ok" "the tasks gate passes"
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
run_case "AC72 the same merge, folder moved under cortex/changes/archive/ -> FAIL" case_AC72_merge_prunes_lock_archived
run_case "AC72 the same merge, archived copy already on the first parent -> FAIL" case_AC72_merge_prunes_lock_archived_first_parent
run_case "AC74 lock.md added and removed only by merges -> FAIL" case_AC74_lock_only_in_merges
run_case "AC75 base deleted a finished lock.md, merged in -> ok" case_AC75_base_deleted_lock_merged
run_case "AC75 base archived and rewrote a finished lock.md, merged in -> ok" case_AC75_base_archived_lock_merged
run_case "AC76 lock at cortex/changes/[o]ld (pattern name) dropped -> FAIL" case_AC76_pattern_folder_name
run_case "AC77 lock at a reused folder name dropped -> FAIL" case_AC77_reused_folder_name
run_case "AC78 lock.md replaced by a directory -> FAIL" case_AC78_lock_replaced_by_directory
run_case "AC78 lock.md replaced by a symlink -> FAIL" case_AC78_lock_replaced_by_symlink
run_case "AC79 new lock in a merge with an old base commit, dropped -> FAIL" case_AC79_merge_with_old_base_commit
run_case "AC80 lock at a folder name with a tab, kept -> FAIL" case_AC80_tab_folder_kept
run_case "AC80 lock at a folder name with a tab, deleted -> FAIL" case_AC80_tab_folder_deleted
run_case "AC81 stacked branch after its parent was squash-merged -> no dropped lock" case_AC81_stacked_after_squash
run_case "AC82 a nested lock.md fixture deleted -> no failure" case_AC82_nested_fixture_lock_deleted
run_case "AC83 tab-named lock inherited from the base -> no failure" case_AC83_inherited_tab_lock
run_case "AC29 folder archived after its change merged" case_archived_after_merge
run_case "AC65 base merged into a locked branch, no re-lock -> FAIL" case_base_merged_into_locked_branch
run_case "AC66 base merged, then a signed re-lock -> ok" case_base_merged_and_relocked
run_case "AC35 a branch's stub _config.sh: the base's parser is used" case_AC35_branch_stub_parser
run_case "AC62 a merged side branch weakening a locked test fails" case_AC62_side_branch_weakens_locked_test
run_case "G3 criterion 10: an open task fails CI until ticked" case_G3_open_task_fails_ci
summary
