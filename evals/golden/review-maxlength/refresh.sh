#!/usr/bin/env bash
# Refreshes fixture.bundle after the installed copies changed in template/
# (tests/golden-fixture.test.sh names them). It rewrites the fixture's
# history so that, at every commit with cortex installed, each copy matches
# this checkout: the files under cortex/ that install.sh copies (not the ones
# filled in when the fixture was built), .claude/ (adapt.sh's copies of the
# Claude Code adapter), cortex/design-rules.md, cortex/version's first line,
# the root AGENTS.md's agents block, and cortex/footprint's shas. It remaps
# lock.md's Tests-locked-at to the rewritten test commit. Source, tests,
# planted content, messages, authors and dates stay as they are.
#
# The bundle is replaced only if gates.sh prints "gates: ok" at each of the
# three tags (golden-clean, golden-planted, golden-quality) and the project's
# own files (src/, test/, package.json) are unchanged at each, which also
# keeps the rubric's reproductions valid. A file removed from template/ is
# not removed from the fixture; rebuild it then (README).
#
# Usage: evals/golden/review-maxlength/refresh.sh [bundle]
#   bundle: the fixture to refresh (default: fixture.bundle next to this
#   script); the result always replaces fixture.bundle.
# Exit:  0 refreshed, 1 a check failed (bundle untouched).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
CORTEX="$(cd "$here/../../.." && pwd)"
export CORTEX
bundle="$here/fixture.bundle"
source_bundle="${1:-$bundle}"
folder=cortex/changes/20260924-slugify-maxlength
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git clone -q -c core.autocrlf=false "$source_bundle" "$work/fx"
cd "$work/fx"
git checkout -q --detach
for b in main cortex-install "change/${folder#cortex/changes/}"; do
  git branch -q -f "$b" "origin/$b"
done
git remote remove origin
before=""
for tag in golden-clean golden-planted golden-quality; do
  before="$before $tag=$(git rev-parse "$tag")"
done

# Sourced by filter-branch at each commit, in the commit's tree, with its
# map function in scope.
cat > "$work/filter.sh" <<'EOF'
if [ -f cortex/harness/commands/review.md ]; then
  T="$CORTEX/template/cortex"
  while IFS= read -r rel; do
    case "$rel" in config | AGENTS.md | constitution.md | deferred-practices.md | knowledge/* | changes/*) continue ;; esac
    mkdir -p "$(dirname "cortex/$rel")"
    cp "$T/$rel" "cortex/$rel"
  done <<<"$(cd "$T" && find . -type f | sed 's|^\./||')"
  rm -rf .claude
  mkdir -p .claude
  cp -R "$T/adapters/claude-code/.claude/." .claude/
  cp "$CORTEX/docs/01-design-rules.md" cortex/design-rules.md
  commit_line="$(sed -n 2p cortex/version 2>/dev/null || true)"
  printf '%s\n%s\n' "$(tr -d '\r\n' < "$CORTEX/VERSION")" "$commit_line" > cortex/version
  # The root AGENTS.md and CLAUDE.md are cortex's (created by the install),
  # each one block; the footprint records them and adapt.sh's .claude files.
  { printf '<!-- cortex:begin agents -->\n'; cat "$CORTEX/template/blocks/AGENTS.md"; printf '<!-- cortex:end agents -->\n'; } > AGENTS.md
  printf '<!-- cortex:begin claude -->\n@AGENTS.md\n<!-- cortex:end claude -->\n' > CLAUDE.md
  . "$CORTEX/template/cortex/bin/_footprint.sh"
  FP_RECORDS=""
  fp_add created AGENTS.md "$(file_sha AGENTS.md)"
  fp_add block AGENTS.md agents "$(block_sha AGENTS.md agents)" 0
  fp_add created CLAUDE.md "$(file_sha CLAUDE.md)"
  fp_add block CLAUDE.md claude "$(block_sha CLAUDE.md claude)" 0
  while IFS= read -r f; do
    [ -n "$f" ] && fp_add created "$f" "$(file_sha "$f")"
  done <<<"$(find .claude -type f | LC_ALL=C sort)"
  fp_save
fi
lock=cortex/changes/20260924-slugify-maxlength/lock.md
if [ -f "$lock" ]; then
  old="$(sed -n 's/^Tests-locked-at:[[:space:]]*\([0-9a-f]*\).*/\1/p' "$lock")"
  new="$(map "$old")"
  sed "s/$old/$new/" "$lock" > "$lock.tmp" && mv "$lock.tmp" "$lock"
fi
EOF
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f \
  --tree-filter ". '$work/filter.sh'" --tag-name-filter cat -- --branches --tags >/dev/null 2>&1

failed=0
for pair in $before; do
  tag="${pair%=*}" old="${pair#*=}"
  for path in src test package.json; do
    if [ "$(git rev-parse "$old:$path")" != "$(git rev-parse "$tag:$path")" ]; then
      echo "refresh: FAIL $path changed at $tag"
      failed=1
    fi
  done
  git checkout -q --detach "$tag"
  # gates.sh exits 1 on a failure; capture its last line either way
  result="$( (bash cortex/bin/gates.sh "$folder" 2>&1 || true) | tail -1)"
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
