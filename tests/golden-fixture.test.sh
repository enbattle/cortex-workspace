#!/usr/bin/env bash
# Checks that the golden fixture's installed harness still matches template/.
#
# evals/golden/review-maxlength/fixture.bundle holds a repository with cortex
# installed. A golden run tests the installed copies, so once template/
# changes, a stale bundle silently tests the old text. This suite fails,
# naming each file, when an installed copy at the golden-clean tag differs
# from its source here, or is missing, or when golden-planted changes one.
#
# What must match (the fixture README, "Which template this fixture matches"):
# every file install.sh copies from template/, at the same path, except the
# ones filled in when the fixture was built (.cortex/config, AGENTS.md,
# docs/**, changes/**); .cortex/design-rules.md (docs/01-design-rules.md);
# .cortex/version (VERSION); and .claude/**, which adapt.sh copies from
# .cortex/adapters/claude-code/.claude/.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

BUNDLE="$ROOT/evals/golden/review-maxlength/fixture.bundle"
ADAPTER=.cortex/adapters/claude-code

# expected_pairs SRC : "<fixture path><TAB><source path relative to SRC>"
expected_pairs() {
  (cd "$1/template" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) | awk -v a="$ADAPTER/.claude/" '
    $0 == ".cortex/config" || $0 == "AGENTS.md" || /^docs\// || /^changes\// { next }
    { print $0 "\ttemplate/" $0 }
    index($0, a) == 1 { r = substr($0, length(a) + 1); print ".claude/" r "\ttemplate/" $0 }'
  printf '.cortex/design-rules.md\tdocs/01-design-rules.md\n'
  printf '.cortex/version\tVERSION\n'
}

# fixture_drift CLONE SRC : prints one line per mismatch, exits 1 if any.
#   stale <path> (differs from <source>)
#   missing <path> (<source> exists)
#   planted-changes <path>
# Three git calls in all, not one per file (process start-up is slow on
# Windows).
fixture_drift() {
  local clone="$1" src="$2" pairs out
  pairs="$(expected_pairs "$src")"
  out="$(
    {
      cut -f2 <<<"$pairs" | (cd "$src" && xargs git hash-object --no-filters --) |
        paste - <(printf '%s\n' "$pairs") | awk -F'\t' '{ print "S\t" $2 "\t" $3 "\t" $1 }'
      git -C "$clone" ls-tree -r golden-clean | awk -F'\t' '{ split($1, m, " "); print "F\t" $2 "\t" m[3] }'
      cut -f1 <<<"$pairs" | xargs git -C "$clone" diff --name-only golden-clean golden-planted -- |
        sed 's/^/P\t/'
    } | awk -F'\t' '
      $1 == "S" { n++; path[n] = $2; source[n] = $3; want[n] = $4; next }
      $1 == "F" { have[$2] = $3; next }
      $1 == "P" { planted[++np] = $2 }
      END {
        for (i = 1; i <= n; i++) {
          if (!(path[i] in have)) print "missing " path[i] " (" source[i] " exists)"
          else if (have[path[i]] != want[i]) print "stale " path[i] " (differs from " source[i] ")"
        }
        for (i = 1; i <= np; i++) print "planted-changes " planted[i]
      }'
  )"
  [ -z "$out" ] || { printf '%s\n' "$out"; return 1; }
}

clone_bundle() { # bundle -> path of a bare clone
  local d
  d="$(mktemp -d "$TEST_TMP/clone.XXXXXX")"
  git clone -q --bare "$1" "$d"
  printf '%s\n' "$d"
}

# copy_src -> a copy of the sources fixture_drift reads, to plant drift in
copy_src() {
  local d
  d="$(mktemp -d "$TEST_TMP/src.XXXXXX")"
  mkdir -p "$d/docs"
  cp -R "$ROOT/template" "$d/template"
  cp "$ROOT/docs/01-design-rules.md" "$d/docs/"
  cp "$ROOT/VERSION" "$d/"
  printf '%s\n' "$d"
}

CLONE="$(clone_bundle "$BUNDLE")"

case_committed_bundle_matches() {
  run fixture_drift "$CLONE" "$ROOT"
  assert_exit 0 "$CODE" "fixture.bundle matches template/ (refresh it: evals/golden/review-maxlength/README.md)"
  assert_contains "$(expected_pairs "$ROOT")" "harness/commands/review.md" "review.md is among the checked files"
}

# One copy carries every planted drift, so one fixture_drift call (and its
# process start-ups) covers them all; the line count proves that the edits to
# files filled in at build time are not reported.
case_planted_source_drift() {
  local s a; s="$(copy_src)"; a="$ADAPTER/.claude/agents/cortex-reviewer.md"
  append "$s/template/harness/commands/review.md" "edited after the fixture was built"
  append "$s/template/scripts/cortex/gates.sh" "# edited"
  append "$s/docs/01-design-rules.md" "R99 new rule"
  printf '9.9.9\n' > "$s/VERSION"
  append "$s/template/$a" "edited"
  printf 'new command\n' > "$s/template/harness/commands/zz-new.md"
  append "$s/template/AGENTS.md" "edited"
  append "$s/template/.cortex/config" "EXTRA=1"
  append "$s/template/docs/constitution.md" "edited"
  append "$s/template/changes/pipeline-log.md" "edited"
  run fixture_drift "$CLONE" "$s"
  assert_exit 1 "$CODE" "planted drift fails"
  assert_line "$OUT" "stale harness/commands/review.md (differs from template/harness/commands/review.md)" "names review.md"
  assert_line "$OUT" "stale scripts/cortex/gates.sh (differs from template/scripts/cortex/gates.sh)" "names gates.sh"
  assert_line "$OUT" "stale .cortex/design-rules.md (differs from docs/01-design-rules.md)" "names design-rules.md"
  assert_line "$OUT" "stale .cortex/version (differs from VERSION)" "names version"
  assert_line "$OUT" "stale $a (differs from template/$a)" "names the installed adapter source"
  assert_line "$OUT" "stale .claude/agents/cortex-reviewer.md (differs from template/$a)" "names the generated adapter"
  assert_line "$OUT" "missing harness/commands/zz-new.md (template/harness/commands/zz-new.md exists)" "names the missing file"
  assert_true "only the seven planted files are named (filled-in files are not compared)" \
    [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 7 ]
}

case_planted_tag_changes_harness() {
  local w b
  w="$(mktemp -d "$TEST_TMP/work.XXXXXX")"
  git clone -q "$BUNDLE" "$w"
  git -C "$w" -c advice.detachedHead=false checkout -q golden-planted
  append "$w/harness/commands/review.md" "planted edit"
  git -C "$w" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -am "edit review.md"
  git -C "$w" tag -f golden-planted >/dev/null
  b="$TEST_TMP/planted.bundle"
  git -C "$w" bundle create -q "$b" --all 2>/dev/null
  run fixture_drift "$(clone_bundle "$b")" "$ROOT"
  assert_exit 1 "$CODE" "golden-planted changing a harness file fails"
  assert_line "$OUT" "planted-changes harness/commands/review.md" "names the file the planted tag changes"
}

run_case "committed fixture.bundle matches template/" case_committed_bundle_matches
run_case "planted: every drifted or missing source file is named" case_planted_source_drift
run_case "planted: golden-planted changing a harness file is named" case_planted_tag_changes_harness
summary
