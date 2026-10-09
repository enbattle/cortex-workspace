#!/usr/bin/env bash
# Verifies that the tests the test-first command locked are untouched (R11).
#
# Reads <change-folder>/lock.md: a "Tests-locked-at: <sha>" line and a
# "## Locked tests" list. test-first commits the tests (commit T), then adds
# lock.md naming T as the very next commit (L). Nothing touches lock.md again
# except a signed re-lock (test-first step 7; spec Amendments 9 to 11).
# Any other edit, including a lock.md brought in by a merge, is LOCK moved.
#
# Locked, and compared with their content at T (committed, staged and
# unstaged edits and deletions all count): every listed file; every file
# matching TEST_GLOBS as configured at T, so existing tests can't be weakened;
# and cortex/config itself, which also freezes the gate commands. A file
# matching TEST_GLOBS that didn't exist at T (committed later, staged, or
# untracked) fails too: adding tests is the test writer's job.
#
# There is no allowance for merges (spec Amendment 11): a merge that changes a
# locked file fails like any other edit. To bring a locked branch up to date
# with a base that changed locked files, merge it and re-lock, the merge
# commit being the re-lock's tests commit. A re-lock blesses only its own
# tests commit and may not change cortex/config. Rebasing after the lock is
# not supported: the lock commit stops being an ancestor.
#
# It compares against commits rather than using `git diff` alone, because
# `git diff` never shows untracked files.
#
# Usage: cortex/bin/tests-locked.sh <change-folder>
# Exit:  0 unchanged, 1 a lock is broken, 2 usage error.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: cortex/bin/tests-locked.sh <change-folder>" >&2
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

# listed_paths : lock.md text on stdin -> its "## Locked tests" paths. A list
# line's path is its first backticked span, else its first word, so a
# trailing note ("- `path` (new)") is allowed.
listed_paths() {
  awk '
    /^## Locked tests[[:space:]]*$/ { inside = 1; next }
    /^#/ { inside = 0 }
    inside && /^- / {
      rest = substr($0, 3)
      if (match(rest, /`[^`]+`/)) p = substr(rest, RSTART + 1, RLENGTH - 2)
      else { split(rest, w, /[[:space:]]+/); p = w[1] }
      if (p != "") print p
    }'
}

if [ ! -f "$lock_file" ]; then
  lock missing "$lock_file not found (test-first writes it)"
  finish
fi

sha="$(tr -d '\r' < "$lock_file" | sed -n 's/^Tests-locked-at:[[:space:]]*\([^[:space:]]*\).*/\1/p' | sed -n 1p)"
locked_paths="$(tr -d '\r' < "$lock_file" | listed_paths)"

[ -n "$sha" ] || lock missing "no 'Tests-locked-at:' line with a sha in $lock_file"
[ -n "$locked_paths" ] || lock missing "no paths listed under '## Locked tests' in $lock_file"
finish

# Paths from here on are relative to the repository root.
lock_rel="$(git -C "$folder" rev-parse --show-prefix)lock.md"
cd "$(git rev-parse --show-toplevel)"

# The lock record (spec Amendments 2, 9 and 10): every commit on HEAD's
# first-parent line that changes lock.md, oldest first, directly follows the
# commit its lock.md names; each one after the first is a re-lock that carries
# the user's sign-off and lists every path the previous lock listed. A merge
# that brings in another lock.md is such a commit, so it fails. The newest
# governs, and the working tree's lock.md must equal it (checked below).
lock_commits="$(g log --first-parent --reverse --format=%H -- "$lock_rel")"
n_lock_commits="$(printf '%s' "$lock_commits" | grep -c . || true)"
relocks="" # "<previous sha> <re-lock's tests commit> <previous lock commit>" per re-lock
if [ "$n_lock_commits" -eq 0 ]; then
  lock moved "$lock_rel is not committed; test-first commits it right after the tests"
else
  i=0
  prev_named="" prev_list="" prev_commit=""
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    i=$((i + 1))
    short_c="$(g rev-parse --short=7 "$c")"
    if ! g cat-file -e "$c:$lock_rel" 2>/dev/null; then
      lock moved "$lock_rel is deleted in $short_c"
      prev_named="" prev_list="" prev_commit=""
      continue
    fi
    content="$(g show "$c:$lock_rel" | tr -d '\r')"
    named="$(sed -n 's/^Tests-locked-at:[[:space:]]*\([^[:space:]]*\).*/\1/p' <<<"$content" | sed -n 1p)"
    named_full="$(g rev-parse --verify --quiet "$named^{commit}" || true)"
    parent="$(g rev-parse --verify --quiet "$c^1" || true)"
    if [ -z "$named_full" ] || [ "$parent" != "$named_full" ]; then
      lock moved "$lock_rel's commit $short_c does not directly follow the commit it names ($named)"
    fi
    list="$(listed_paths <<<"$content")"
    if [ "$i" -gt 1 ]; then
      signoff="$(sed -n 's/^Re-lock signed off by:[[:space:]]*//p' <<<"$content" | sed -n 1p)"
      signoff="${signoff%"${signoff##*[![:space:]]}"}"
      case "$signoff" in
        "" | "<"*">")
          lock moved "$lock_rel was changed after it was written ($n_lock_commits commits touch it) without a re-lock sign-off in $short_c" ;;
      esac
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        grep -qxF -- "$p" <<<"$list" || lock moved "the re-lock in $short_c drops $p, which the previous lock listed"
      done <<<"$prev_list"
      if [ -n "$prev_named" ] && [ -n "$named_full" ]; then
        relocks="$relocks$prev_named $named_full $prev_commit"$'\n'
      fi
    fi
    prev_named="$named_full" prev_list="$list" prev_commit="$c"
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

empty_tree="$(g hash-object -t tree /dev/null)"

# globs_at SHA : TEST_GLOBS as configured at SHA (parsed, never sourced), so
# narrowing it afterwards can't unlock anything.
globs_at() {
  g cat-file -e "$1:cortex/config" 2>/dev/null || return 0
  g show "$1:cortex/config" | config_value TEST_GLOBS
}

# lock_set_at SHA LIST : what a lock naming SHA covers: the listed paths, every
# file matching TEST_GLOBS at SHA (a diff from git's empty tree lists a
# commit's files through a pathspec), and the config itself if it existed.
lock_set_at() {
  local globs matched="" config=""
  globs="$(globs_at "$1")"
  if [ -n "$globs" ]; then
    set -f # the globs are for git, not the shell
    # shellcheck disable=SC2086 # word-splitting the glob list is intended
    matched="$(g diff --name-only "$empty_tree" "$1" -- $globs)"
    set +f
  fi
  g cat-file -e "$1:cortex/config" 2>/dev/null && config=cortex/config
  printf '%s\n%s\n%s\n' "$2" "$matched" "$config" | awk 'NF && !seen[$0]++'
}

# A re-lock blesses only its own tests commit (Amendments 10 and 11): the
# previous lock must still hold, in committed content, at that commit's
# parent, merges included, and the re-lock may not change the config.
# Reported as if the re-lock hadn't happened.
while read -r prev tests_commit prev_lock_commit; do
  [ -n "$prev" ] || continue
  at="$(g rev-parse --verify --quiet "$tests_commit^1" || true)"
  [ -n "$at" ] || continue
  w_list="$(g show "$prev_lock_commit:$lock_rel" | tr -d '\r' | listed_paths)"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    want="$(g rev-parse --verify --quiet "$prev:$path" || true)"
    [ -n "$want" ] || continue
    have="$(g rev-parse --verify --quiet "$at:$path" || true)"
    if [ -z "$have" ]; then
      lock deleted "$path"
    elif [ "$have" != "$want" ]; then
      lock modified "$path"
    fi
  done <<<"$(lock_set_at "$prev" "$w_list")"
  w_globs="$(globs_at "$prev")"
  if [ -n "$w_globs" ]; then
    set -f
    # shellcheck disable=SC2086
    w_added="$(g diff --name-only --diff-filter=A "$prev" "$at" -- $w_globs)"
    set +f
    while IFS= read -r path; do
      [ -z "$path" ] || lock added "$path"
    done <<<"$w_added"
  fi
  config_prev="$(g rev-parse --verify --quiet "$prev:cortex/config" || true)"
  config_at="$(g rev-parse --verify --quiet "$at:cortex/config" || true)"
  config_relock="$(g rev-parse --verify --quiet "$tests_commit:cortex/config" || true)"
  if [ "$config_prev" = "$config_at" ] && [ "$config_at" != "$config_relock" ]; then
    lock modified "cortex/config"
  fi
done <<<"$relocks"

# The newest lock's set, compared with the working tree and the index.
globs="$(globs_at "$sha")"
lock_set="$(lock_set_at "$sha" "$locked_paths")"
current_matches=""
if [ -n "$globs" ]; then
  set -f
  # shellcheck disable=SC2086
  current_matches="$(g ls-files -co --exclude-standard -- $globs)"
  set +f
fi

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
