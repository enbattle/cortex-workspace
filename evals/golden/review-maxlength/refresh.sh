#!/usr/bin/env bash
# Refreshes fixture.bundle after the installed copies changed in template/
# (tests/golden-fixture.test.sh names them). It rewrites the fixture's
# history so that, at every commit with the harness installed, each copy
# matches this checkout, and remaps lock.md's Tests-locked-at to the
# rewritten test commit. Source, tests, planted content, messages, authors
# and dates stay as they are.
#
# The bundle is replaced only if gates.sh prints "gates: ok" at both tags and
# the project's own files (src/, test/, package.json) are unchanged at both,
# which also keeps the rubric's reproductions valid. A file removed from
# template/ is not removed from the fixture; rebuild it then (README).
#
# Usage: evals/golden/review-maxlength/refresh.sh
# Exit:  0 refreshed, 1 a check failed (bundle untouched).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
CORTEX="$(cd "$here/../../.." && pwd)"
export CORTEX
bundle="$here/fixture.bundle"
folder=changes/20260924-slugify-maxlength
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git clone -q -c core.autocrlf=false "$bundle" "$work/fx"
cd "$work/fx"
git checkout -q --detach
for b in main cortex-install "change/${folder#changes/}"; do
  git branch -q -f "$b" "origin/$b"
done
git remote remove origin
old_clean="$(git rev-parse golden-clean)"
old_planted="$(git rev-parse golden-planted)"

# Sourced by filter-branch at each commit, in the commit's tree, with its
# map function in scope.
cat > "$work/filter.sh" <<'EOF'
adapter=.cortex/adapters/claude-code/.claude/
if [ -f harness/commands/review.md ]; then
  while IFS= read -r rel; do
    case "$rel" in .cortex/config | AGENTS.md | docs/* | changes/*) continue ;; esac
    mkdir -p "$(dirname "$rel")"
    cp "$CORTEX/template/$rel" "$rel"
    case "$rel" in
      "$adapter"*)
        out=".claude/${rel#"$adapter"}"
        mkdir -p "$(dirname "$out")"
        cp "$CORTEX/template/$rel" "$out" ;;
    esac
  done <<<"$(cd "$CORTEX/template" && find . -type f | sed 's|^\./||')"
  cp "$CORTEX/docs/01-design-rules.md" .cortex/design-rules.md
  cp "$CORTEX/VERSION" .cortex/version
fi
lock=changes/20260924-slugify-maxlength/lock.md
if [ -f "$lock" ]; then
  old="$(sed -n 's/^Tests-locked-at:[[:space:]]*\([0-9a-f]*\).*/\1/p' "$lock")"
  new="$(map "$old")"
  sed "s/$old/$new/" "$lock" > "$lock.tmp" && mv "$lock.tmp" "$lock"
fi
EOF
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f \
  --tree-filter ". '$work/filter.sh'" --tag-name-filter cat -- --branches --tags >/dev/null 2>&1

failed=0
for pair in "golden-clean $old_clean" "golden-planted $old_planted"; do
  tag="${pair% *}" old="${pair#* }"
  for path in src test package.json; do
    if [ "$(git rev-parse "$old:$path")" != "$(git rev-parse "$tag:$path")" ]; then
      echo "refresh: FAIL $path changed at $tag"
      failed=1
    fi
  done
  git checkout -q --detach "$tag"
  result="$(bash scripts/cortex/gates.sh "$folder" 2>&1 | tail -1)"
  echo "refresh: $tag $(git rev-parse --short=7 HEAD): $result"
  [ "$result" = "gates: ok" ] || failed=1
done
if [ "$failed" -ne 0 ]; then
  echo "refresh: fixture.bundle left unchanged"
  exit 1
fi

git checkout -q main
git bundle create -q "$work/new.bundle" HEAD --branches --tags
mv "$work/new.bundle" "$bundle"
locked_at="$(git show "golden-clean:$folder/lock.md" | sed -n 's/^Tests-locked-at:[[:space:]]*\([0-9a-f]\{7\}\).*/\1/p')"
echo "refresh: base $(git rev-parse --short=7 "$(git merge-base main golden-clean)"), Tests-locked-at $locked_at"
echo "refresh: fixture.bundle replaced; run tests/golden-fixture.test.sh"
