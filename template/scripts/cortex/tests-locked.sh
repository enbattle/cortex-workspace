#!/usr/bin/env bash
# Verifies that the tests the test-first command locked are untouched (R11).
#
# Reads <change-folder>/tasks.md: the "Tests-locked-at: <sha>" line and the
# "## Locked tests" list. Every listed file, and every file matching
# TEST_GLOBS in .cortex/config as of that commit (so existing tests can't be
# weakened either), must be identical in the working tree to its content at
# that commit: committed, staged and unstaged edits and deletions all count.
# A test file matching TEST_GLOBS that didn't exist at the sha (committed
# later, staged, or untracked) fails too: adding tests is the test writer's job.
#
# It compares against a commit rather than using `git diff` alone, because
# `git diff` never shows untracked files.
#
# Usage: scripts/cortex/tests-locked.sh <change-folder>
# Exit:  0 unchanged, 1 a lock is broken, 2 usage error.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: scripts/cortex/tests-locked.sh <change-folder>" >&2
  exit 2
fi
tasks="$1/tasks.md"
root="$(git rev-parse --show-toplevel)"

problems=0
lock() { # kind detail
  echo "LOCK $1: $2"
  problems=$((problems + 1))
}
finish() {
  if [ "$problems" -gt 0 ]; then exit 1; fi
}

if [ ! -f "$tasks" ]; then
  lock missing "$tasks not found"
  finish
fi

sha="$(tr -d '\r' < "$tasks" | sed -n 's/^Tests-locked-at:[[:space:]]*\([^[:space:]]*\).*/\1/p' | sed -n 1p)"
locked_paths="$(tr -d '\r' < "$tasks" | awk '
  /^## Locked tests[[:space:]]*$/ { inside = 1; next }
  /^#/ { inside = 0 }
  inside && /^- / { p = substr($0, 3); gsub(/`/, "", p); gsub(/^[[:space:]]+|[[:space:]]+$/, "", p); if (p != "") print p }')"

[ -n "$sha" ] || lock missing "no 'Tests-locked-at:' line with a sha in $tasks"
[ -n "$locked_paths" ] || lock missing "no paths listed under '## Locked tests' in $tasks"
finish

cd "$root"
if ! git rev-parse --verify --quiet "$sha^{commit}" >/dev/null; then
  lock bad-sha "$sha does not resolve to a commit"
  finish
fi
if ! git merge-base --is-ancestor "$sha" HEAD; then
  lock bad-sha "$sha is not an ancestor of HEAD (was the branch rebased or switched?)"
  finish
fi

# TEST_GLOBS from .cortex/config (parsed, never sourced).
globs=""
if [ -f .cortex/config ]; then
  globs="$(tr -d '\r' < .cortex/config | awk '
    /^[[:space:]]*#/ { next }
    { eq = index($0, "="); if (eq == 0) next
      key = substr($0, 1, eq - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key != "TEST_GLOBS") next
      val = substr($0, eq + 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", val); print val; exit }')"
  case "$globs" in "<"*">") globs="" ;; esac
fi

# The lock set: the listed files, plus every file matching TEST_GLOBS at the
# sha (a diff from git's empty tree lists a commit's files through a pathspec).
matched_at_sha=""
current_matches=""
if [ -n "$globs" ]; then
  empty_tree="$(git hash-object -t tree /dev/null)"
  set -f # the globs are for git, not the shell
  # shellcheck disable=SC2086 # word-splitting the glob list is intended
  matched_at_sha="$(git diff --name-only "$empty_tree" "$sha" -- $globs)"
  # shellcheck disable=SC2086
  current_matches="$(git ls-files -co --exclude-standard -- $globs)"
  set +f
fi
lock_set="$(printf '%s\n%s\n' "$locked_paths" "$matched_at_sha" | awk 'NF && !seen[$0]++')"

count=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  count=$((count + 1))
  if ! git cat-file -e "$sha:$path" 2>/dev/null; then
    lock not-locked "$path (not in commit $sha)"
  elif [ ! -e "$path" ]; then
    lock deleted "$path"
  elif ! git diff --quiet "$sha" -- "$path" || ! git diff --quiet --cached "$sha" -- "$path"; then
    lock modified "$path"
  fi
done <<<"$lock_set"

while IFS= read -r path; do
  [ -n "$path" ] || continue
  git cat-file -e "$sha:$path" 2>/dev/null || lock added "$path"
done <<<"$current_matches"

finish
echo "tests-locked: $count file(s) unchanged since $(git rev-parse --short=7 "$sha")"
