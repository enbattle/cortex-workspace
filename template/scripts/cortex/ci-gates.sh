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

# 4. A branch can't drop its own lock (spec Amendments 11 and 12): a lock.md
# that a commit on this branch touched, that the base never had, and that is
# gone at HEAD (deleted, or moved under changes/archive/) fails. The history,
# not the net diff: a lock added and then removed on the branch nets out to
# nothing. Every commit the branch brings counts, on every side of every merge
# (Amendment 12): without --full-history, git log prunes a merged side the
# merge's result ignores, and without -m it lists nothing a merge itself
# changes; either way a merge could drop the lock.
while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in changes/archive/*) continue ;; esac
  g cat-file -e "HEAD:$path" 2>/dev/null && continue
  # A path the base's history ever had is a finished change's, whatever the
  # base did with it since; a branch can't add to the base's history.
  [ -n "$(g rev-list -1 --full-history "$base" -- "$path")" ] && continue
  fail "${path%/lock.md} (lock.md added on this branch is gone)"
done <<<"$(g log --full-history -m --format= --name-only "$base..HEAD" -- 'changes/*/lock.md' | LC_ALL=C sort -u)"

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
