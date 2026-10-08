#!/usr/bin/env bash
# The server-side boundary for the test lock (design rule R11). Run in CI on
# every pull request, from a fresh checkout with full history:
#
#   bash scripts/cortex/ci-gates.sh origin/<base branch>
#
# The local scripts are guardrails: an agent with git access on its own
# machine can rewrite history, hide edits with --skip-worktree, or edit the
# checker. Here every checker comes from the base branch (the template
# workflow extracts this script from the base too), so a change can't weaken
# the scripts that judge it; a fresh checkout has no hidden edits, and any
# flagged file is refused anyway; and the gates run on the branch as pushed.
# What no script can judge (the tests' assertions, .cortex/config edits made
# before the lock, what a re-lock's sign-off blesses, the workflow file
# itself) is covered by required human review of those paths (CODEOWNERS).
#
# Usage: scripts/cortex/ci-gates.sh <base-ref>
# Exit:  0 all passed, 1 something failed, 2 usage error.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: scripts/cortex/ci-gates.sh <base-ref>" >&2
  exit 2
fi
base="$1"
root="$(git rev-parse --show-toplevel)"
cd "$root"
if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  echo "error: $base does not resolve to a commit" >&2
  exit 2
fi
g() { git -c core.quotepath=off "$@"; }

failed=0
fail() { # message
  echo "ci-gates: FAIL $1"
  failed=$((failed + 1))
}

# 1. The checker comes from the base branch.
tools="$(mktemp -d)"
trap 'rm -rf "$tools"' EXIT
if g cat-file -e "$base:scripts/cortex/gates.sh" 2>/dev/null; then
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    g show "$base:$path" > "$tools/$(basename "$path")"
  done <<<"$(g ls-tree --name-only "$base" -- scripts/cortex/ | grep '\.sh$' || true)"
  echo "ci-gates: using scripts from $base"
else
  cp scripts/cortex/*.sh "$tools/"
  echo "ci-gates: note: $base has no cortex scripts; using this branch's copy"
fi

# 2. No tracked file may hide its working-tree state from git.
while IFS= read -r line; do
  [ -n "$line" ] || continue
  tag="${line%% *}"
  path="${line#* }"
  case "$tag" in
    S | [a-z]) fail "hidden $path" ;;
  esac
done <<<"$(g ls-files -v)"

# 3. The harness itself.
if bash "$tools/check.sh" "$root"; then
  echo "ci-gates: check ok"
else
  fail check
fi

# 4. A branch can't drop its own lock (spec Amendments 11 and 12): every
# change folder's lock.md that a commit this branch brings holds (any commit
# reachable from HEAD and not from the base, read from its tree, so merges
# need no special case) must still be a regular file at HEAD, unless the
# base's history held that exact content at that path: then it is a finished
# change's lock, not this branch's. A lock is changes/<folder>/lock.md, one
# folder deep, so archived copies (changes/archive/<folder>/) never count as
# kept. Paths are compared literally; a name git has to quote can't be, so it
# fails unless the base's tip holds it unchanged.

# lock_entries : "<path>\t<blob>" for each lock in the trees of the commits
# named on stdin
lock_entries() {
  local c
  while IFS= read -r c; do
    g ls-tree -r "$c" -- changes/
  done | awk -F '\t' '$2 ~ /^"?changes\/[^\/]+\/lock\.md"?$/ && $2 !~ /^"?changes\/archive\// {
    split($1, m, " "); print $2 "\t" m[3] }' | LC_ALL=C sort -u
}
# base_had PATH BLOB : the base's history held BLOB at PATH
base_had() {
  local c
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    [ "$(g rev-parse --verify --quiet "$c:$1" || true)" = "$2" ] && return 0
  done <<<"$(g --literal-pathspecs rev-list --full-history "$base" -- "$1")"
  return 1
}
base_locks="$(printf '%s\n' "$base" | lock_entries)"
# Sorted, so a path's entries (one per content it had) are adjacent; a path
# fails once, as soon as one of its contents isn't the base's.
last_failed=""
while IFS=$'\t' read -r path blob; do
  [ -n "$path" ] && [ "$path" != "$last_failed" ] || continue
  case "$path" in
    \"*)
      grep -qxF -- "$path"$'\t'"$blob" <<<"$base_locks" && continue
      last_failed="$path"
      fail "$path (a lock.md path git has to quote, so CI can't check it)"
      continue ;;
  esac
  mode="$(g --literal-pathspecs ls-tree HEAD -- "$path" | cut -d ' ' -f 1)"
  case "$mode" in 100644 | 100755) continue ;; esac
  base_had "$path" "$blob" && continue
  last_failed="$path"
  fail "${path%/lock.md} (lock.md added on this branch is gone)"
done <<<"$(g rev-list "$base..HEAD" | lock_entries)"

# 5. Every change folder whose lock was added or changed on this branch.
# Archived changes (changes/archive/) finished earlier and are not gated.
folders="$(g diff --name-only "$base...HEAD" -- 'changes/*/lock.md' | grep -v '^changes/archive/' | sed 's|/lock\.md$||' | LC_ALL=C sort -u || true)"
while IFS= read -r folder; do
  [ -n "$folder" ] || continue
  [ -f "$folder/lock.md" ] || continue
  if bash "$tools/gates.sh" "$folder"; then
    echo "ci-gates: $folder ok"
  else
    fail "$folder"
  fi
done <<<"$folders"

if [ "$failed" -eq 0 ]; then
  echo "ci-gates: ok"
else
  echo "ci-gates: $failed failed"
  exit 1
fi
