#!/usr/bin/env bash
# Verifies that the tests the test-first command locked are untouched (R11).
#
# Reads <change-folder>/lock.md: a "Tests-locked-at: <sha>" line and a
# "## Locked tests" list. test-first commits the tests (commit T), then adds
# lock.md naming T as the very next commit (L). Nothing touches lock.md again
# unless test-first re-runs: a re-lock commits new tests (T2) and then lock.md
# naming them (L2), with the user's "Re-lock signed off by:" line, and the
# newest lock governs (spec Amendment 9). Any other edit is LOCK moved.
#
# Locked, and compared with their content at T (committed, staged and
# unstaged edits and deletions all count): every listed file; every file
# matching TEST_GLOBS as configured at T, so existing tests can't be weakened;
# and .cortex/config itself, which also freezes the gate commands. A file
# matching TEST_GLOBS that didn't exist at T (committed later, staged, or
# untracked) fails too: adding tests is the test writer's job.
#
# A branch may bring itself up to date by merging its base: a locked file
# whose current content is exactly the base's version, as taken by a merge
# after the lock, is accepted (likewise a new test file that came in whole
# from the base). Anything else, including a merge resolved to content
# matching neither side, still fails. Rebasing after the lock is not
# supported: the lock commit stops being an ancestor.
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
# shellcheck source=_config.sh
. "$(cd "$(dirname "$0")" && pwd)/_config.sh"
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

# The lock record (spec Amendments 2 and 9): every commit that touches it,
# oldest first, directly follows the commit its lock.md names, and each one
# after the first is a re-lock that carries the user's sign-off. The newest
# governs, and the working tree's lock.md must equal it (checked below).
lock_commits="$(g log --reverse --format=%H -- "$lock_rel")"
n_lock_commits="$(printf '%s' "$lock_commits" | grep -c . || true)"
if [ "$n_lock_commits" -eq 0 ]; then
  lock moved "$lock_rel is not committed; test-first commits it right after the tests"
else
  i=0
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    i=$((i + 1))
    content="$(g show "$c:$lock_rel" | tr -d '\r')"
    named="$(sed -n 's/^Tests-locked-at:[[:space:]]*\([^[:space:]]*\).*/\1/p' <<<"$content" | sed -n 1p)"
    named_full="$(g rev-parse --verify --quiet "$named^{commit}" || true)"
    parent="$(g rev-parse --verify --quiet "$c^1" || true)"
    if [ -z "$named_full" ] || [ "$parent" != "$named_full" ]; then
      lock moved "$lock_rel's commit $(g rev-parse --short=7 "$c") does not directly follow the commit it names ($named)"
    fi
    if [ "$i" -gt 1 ]; then
      signoff="$(sed -n 's/^Re-lock signed off by:[[:space:]]*//p' <<<"$content" | sed -n 1p)"
      signoff="${signoff%"${signoff##*[![:space:]]}"}"
      case "$signoff" in
        "" | "<"*">")
          lock moved "$lock_rel was changed after it was written ($n_lock_commits commits touch it) without a re-lock sign-off in $(g rev-parse --short=7 "$c")" ;;
      esac
    fi
  done <<<"$lock_commits"
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
  globs="$(g show "$sha:.cortex/config" | config_value TEST_GLOBS)"
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

# The base versions a merge after the lock brought in: the non-first
# parents of every merge commit on the branch's first-parent line.
base_parents="$(g log --first-parent --merges --format='%P' "$sha..HEAD" | awk '{ for (i = 2; i <= NF; i++) print $i }')"

# from_base PATH : true if PATH's working-tree and index content are both
# exactly its content at one of those merged base commits.
from_base() {
  local path="$1" parent want worktree index
  [ -n "$base_parents" ] && [ -e "$path" ] || return 1
  worktree="$(g hash-object -- "$path")"
  index="$(g rev-parse --verify --quiet ":$path" || true)"
  while IFS= read -r parent; do
    [ -n "$parent" ] || continue
    want="$(g rev-parse --verify --quiet "$parent:$path" || true)"
    if [ -n "$want" ] && [ "$want" = "$worktree" ] && [ "$want" = "$index" ]; then
      return 0
    fi
  done <<<"$base_parents"
  return 1
}

count=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  count=$((count + 1))
  if ! g cat-file -e "$sha:$path" 2>/dev/null; then
    lock not-locked "$path (not in commit $sha)"
  elif [ ! -e "$path" ]; then
    lock deleted "$path"
  elif ! g diff --quiet "$sha" -- "$path" || ! g diff --quiet --cached "$sha" -- "$path"; then
    from_base "$path" || lock modified "$path"
  fi
done <<<"$lock_set"

while IFS= read -r path; do
  [ -n "$path" ] || continue
  g cat-file -e "$sha:$path" 2>/dev/null || from_base "$path" || lock added "$path"
done <<<"$current_matches"

finish
echo "tests-locked: $count file(s) unchanged since $(g rev-parse --short=7 "$sha")"
