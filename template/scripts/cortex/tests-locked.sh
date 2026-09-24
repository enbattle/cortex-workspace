#!/usr/bin/env bash
# Verifies that the tests the test-first command locked are untouched (R11).
#
# Reads <change-folder>/lock.md: a "Tests-locked-at: <sha>" line and a
# "## Locked tests" list. test-first commits the tests (commit T), then adds
# lock.md naming T as the very next commit (L), and nothing touches lock.md
# again, so an implementer can't move the lock by editing it (LOCK moved).
#
# Locked, and compared with their content at T (committed, staged and
# unstaged edits and deletions all count): every listed file; every file
# matching TEST_GLOBS as configured at T, so existing tests can't be weakened;
# and .cortex/config itself, which also freezes the gate commands. A file
# matching TEST_GLOBS that didn't exist at T (committed later, staged, or
# untracked) fails too: adding tests is the test writer's job.
#
# It compares against commits rather than using `git diff` alone, because
# `git diff` never shows untracked files.
#
# Usage: scripts/cortex/tests-locked.sh <change-folder>
# Exit:  0 unchanged, 1 a lock is broken, 2 usage error.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: scripts/cortex/tests-locked.sh <change-folder>" >&2
  exit 2
fi
folder="$1"
lock_file="$folder/lock.md"
g() { git -c core.quotepath=off "$@"; }

problems=0
lock() { # kind detail
  echo "LOCK $1: $2"
  problems=$((problems + 1))
}
finish() {
  if [ "$problems" -gt 0 ]; then exit 1; fi
}

if [ ! -f "$lock_file" ]; then
  lock missing "$lock_file not found (test-first writes it)"
  finish
fi

sha="$(tr -d '\r' < "$lock_file" | sed -n 's/^Tests-locked-at:[[:space:]]*\([^[:space:]]*\).*/\1/p' | sed -n 1p)"
# A list line's path is its first backticked span, else its first word, so a
# trailing note ("- `path` (new)") is allowed.
locked_paths="$(tr -d '\r' < "$lock_file" | awk '
  /^## Locked tests[[:space:]]*$/ { inside = 1; next }
  /^#/ { inside = 0 }
  inside && /^- / {
    rest = substr($0, 3)
    if (match(rest, /`[^`]+`/)) p = substr(rest, RSTART + 1, RLENGTH - 2)
    else { split(rest, w, /[[:space:]]+/); p = w[1] }
    if (p != "") print p
  }')"

[ -n "$sha" ] || lock missing "no 'Tests-locked-at:' line with a sha in $lock_file"
[ -n "$locked_paths" ] || lock missing "no paths listed under '## Locked tests' in $lock_file"
finish

# Paths from here on are relative to the repository root.
lock_rel="$(git -C "$folder" rev-parse --show-prefix)lock.md"
cd "$(git rev-parse --show-toplevel)"

# The lock record: added in exactly one commit, right after the sha it names,
# and unchanged since.
lock_commits="$(g log --format=%H -- "$lock_rel")"
n_lock_commits="$(printf '%s' "$lock_commits" | grep -c . || true)"
if [ "$n_lock_commits" -eq 0 ]; then
  lock moved "$lock_rel is not committed; test-first commits it right after the tests"
elif [ "$n_lock_commits" -gt 1 ]; then
  lock moved "$lock_rel was changed after it was written ($n_lock_commits commits touch it)"
else
  full_sha="$(g rev-parse --verify --quiet "$sha^{commit}" || true)"
  parent="$(g rev-parse --verify --quiet "$lock_commits^1" || true)"
  if [ -z "$full_sha" ] || [ "$parent" != "$full_sha" ]; then
    lock moved "$lock_rel's commit does not directly follow the commit it names ($sha)"
  fi
fi
if ! g diff --quiet HEAD -- "$lock_rel" 2>/dev/null || ! g diff --cached --quiet -- "$lock_rel"; then
  lock moved "$lock_rel has uncommitted edits"
fi

if ! g rev-parse --verify --quiet "$sha^{commit}" >/dev/null; then
  lock bad-sha "$sha does not resolve to a commit"
  finish
fi
if ! g merge-base --is-ancestor "$sha" HEAD; then
  lock bad-sha "$sha is not an ancestor of HEAD (was the branch rebased or switched?)"
  finish
fi

# TEST_GLOBS as configured at the lock (parsed, never sourced), so narrowing
# it afterwards can't unlock anything.
globs=""
if g cat-file -e "$sha:.cortex/config" 2>/dev/null; then
  globs="$(g show "$sha:.cortex/config" | tr -d '\r' | awk '
    /^[[:space:]]*#/ { next }
    { eq = index($0, "="); if (eq == 0) next
      key = substr($0, 1, eq - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key != "TEST_GLOBS") next
      val = substr($0, eq + 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", val); print val; exit }')"
  case "$globs" in "<"*">") globs="" ;; esac
fi

# The lock set: the listed files, every file matching TEST_GLOBS at the sha (a
# diff from git's empty tree lists a commit's files through a pathspec), and
# the config itself if it existed then.
matched_at_sha=""
current_matches=""
if [ -n "$globs" ]; then
  empty_tree="$(g hash-object -t tree /dev/null)"
  set -f # the globs are for git, not the shell
  # shellcheck disable=SC2086 # word-splitting the glob list is intended
  matched_at_sha="$(g diff --name-only "$empty_tree" "$sha" -- $globs)"
  # shellcheck disable=SC2086
  current_matches="$(g ls-files -co --exclude-standard -- $globs)"
  set +f
fi
config_at_sha=""
g cat-file -e "$sha:.cortex/config" 2>/dev/null && config_at_sha=.cortex/config
lock_set="$(printf '%s\n%s\n%s\n' "$locked_paths" "$matched_at_sha" "$config_at_sha" | awk 'NF && !seen[$0]++')"

count=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  count=$((count + 1))
  if ! g cat-file -e "$sha:$path" 2>/dev/null; then
    lock not-locked "$path (not in commit $sha)"
  elif [ ! -e "$path" ]; then
    lock deleted "$path"
  elif ! g diff --quiet "$sha" -- "$path" || ! g diff --quiet --cached "$sha" -- "$path"; then
    lock modified "$path"
  fi
done <<<"$lock_set"

while IFS= read -r path; do
  [ -n "$path" ] || continue
  g cat-file -e "$sha:$path" 2>/dev/null || lock added "$path"
done <<<"$current_matches"

finish
echo "tests-locked: $count file(s) unchanged since $(g rev-parse --short=7 "$sha")"
