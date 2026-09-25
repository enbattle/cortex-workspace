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
# before the lock, the workflow file itself) is covered by required human
# review of those paths (CODEOWNERS).
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

# 4. Every change folder whose lock was added or changed on this branch.
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
