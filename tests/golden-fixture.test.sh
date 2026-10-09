#!/usr/bin/env bash
# Checks that the golden fixture's installed harness still matches template/.
#
# evals/golden/review-maxlength/fixture.bundle holds a repository with cortex
# installed. A golden run tests the installed copies, so once template/
# changes, a stale bundle silently tests the old text. This suite fails,
# naming each file, when an installed copy at the golden-clean tag differs
# from its source here, or is missing, or when golden-planted changes one.
#
# What must match (the fixture README, "Which template this fixture matches"),
# in the 3.0.0 layout (spec 2026-10-05-v3-removable-layout, criterion 46):
# every file install.sh copies from template/cortex/, at the same path,
# except the ones filled in when the fixture was built (cortex/config,
# cortex/AGENTS.md, cortex/constitution.md, cortex/deferred-practices.md,
# cortex/knowledge/**, cortex/changes/**: 2.x's docs/** and changes/**);
# cortex/design-rules.md (docs/01-design-rules.md); the first line of
# cortex/version (VERSION; D3 adds the commit as a second line, which is the
# fixture build's own); and .claude/**, which adapt.sh copies from
# cortex/adapters/claude-code/.claude/.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

BUNDLE="$ROOT/evals/golden/review-maxlength/fixture.bundle"
ADAPTER=cortex/adapters/claude-code
VERSION_FILE=cortex/version

# expected_pairs SRC : "<fixture path><TAB><source path relative to SRC>"
expected_pairs() {
  (cd "$1/template" && find cortex -type f | LC_ALL=C sort) | awk -v a="$ADAPTER/.claude/" '
    $0 == "cortex/config" || $0 == "cortex/AGENTS.md" || $0 == "cortex/constitution.md" ||
      $0 == "cortex/deferred-practices.md" || /^cortex\/knowledge\// || /^cortex\/changes\// { next }
    { print $0 "\ttemplate/" $0 }
    index($0, a) == 1 { r = substr($0, length(a) + 1); print ".claude/" r "\ttemplate/" $0 }'
  printf 'cortex/design-rules.md\tdocs/01-design-rules.md\n'
}

# The fixture's three tags; the compared files must be identical at all three.
TAGS="golden-clean golden-planted golden-quality"

# fixture_drift CLONE SRC : prints one line per mismatch, exits 1 if any.
#   missing-tag <tag>
#   stale <path> (differs from <source>)
#   missing <path> (<source> exists)
#   planted-changes <path>
#   quality-changes <path>
# A missing tag skips the comparisons that need it. At most six git calls in
# all, not one per file (process start-up is slow on Windows); the sixth
# reads cortex/version's first line (D3: the version, then the commit).
fixture_drift() {
  local clone="$1" src="$2" pairs out have t
  pairs="$(expected_pairs "$src")"
  # shellcheck disable=SC2086 # TAGS is a word list
  have=" $(git -C "$clone" tag -l $TAGS | tr '\n' ' ')"
  out="$(
    {
      for t in $TAGS; do
        case "$have" in *" $t "*) ;; *) printf 'T\t%s\n' "$t" ;; esac
      done
      cut -f2 <<<"$pairs" | (cd "$src" && xargs git hash-object --no-filters --) |
        paste - <(printf '%s\n' "$pairs") | awk -F'\t' '{ print "S\t" $2 "\t" $3 "\t" $1 }'
      printf 'V\t%s\n' "$(tr -d '\r\n' < "$src/VERSION")"
      case "$have" in *" golden-clean "*)
        git -C "$clone" ls-tree -r golden-clean | awk -F'\t' '{ split($1, m, " "); print "F\t" $2 "\t" m[3] }'
        printf 'W\t%s\n' "$(git -C "$clone" show "golden-clean:$VERSION_FILE" 2>/dev/null | sed -n 1p | tr -d '\r')"
        printf 'C\n'
        case "$have" in *" golden-planted "*)
          { cut -f1 <<<"$pairs"; printf '%s\n' "$VERSION_FILE"; } |
            xargs git -C "$clone" diff --name-only golden-clean golden-planted -- |
            sed 's/^/P\t/' ;;
        esac
        case "$have" in *" golden-quality "*)
          { cut -f1 <<<"$pairs"; printf '%s\n' "$VERSION_FILE"; } |
            xargs git -C "$clone" diff --name-only golden-clean golden-quality -- |
            sed 's/^/Q\t/' ;;
        esac ;;
      esac
    } | awk -F'\t' -v vf="$VERSION_FILE" '
      $1 == "T" { print "missing-tag " $2; next }
      $1 == "S" { n++; path[n] = $2; source[n] = $3; want[n] = $4; next }
      $1 == "V" { vwant = $2; next }
      $1 == "W" { vhave = $2; next }
      $1 == "C" { clean = 1; next }
      $1 == "F" { have[$2] = $3; next }
      $1 == "P" { planted[++np] = $2; next }
      $1 == "Q" { quality[++nq] = $2 }
      END {
        for (i = 1; clean && i <= n; i++) {
          if (!(path[i] in have)) print "missing " path[i] " (" source[i] " exists)"
          else if (have[path[i]] != want[i]) print "stale " path[i] " (differs from " source[i] ")"
        }
        if (clean && !(vf in have)) print "missing " vf " (VERSION exists)"
        else if (clean && vhave != vwant) print "stale " vf " (differs from VERSION)"
        for (i = 1; i <= np; i++) print "planted-changes " planted[i]
        for (i = 1; i <= nq; i++) print "quality-changes " quality[i]
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
  assert_contains "$(expected_pairs "$ROOT")" "cortex/harness/commands/review.md" "review.md is among the checked files"
}

# One copy carries every planted drift, so one fixture_drift call (and its
# process start-ups) covers them all; the line count proves that the edits to
# files filled in at build time are not reported.
case_planted_source_drift() {
  local s a; s="$(copy_src)"; a="$ADAPTER/.claude/agents/cortex-reviewer.md"
  append "$s/template/cortex/harness/commands/review.md" "edited after the fixture was built"
  append "$s/template/cortex/bin/gates.sh" "# edited"
  append "$s/docs/01-design-rules.md" "R99 new rule"
  printf '9.9.9\n' > "$s/VERSION"
  append "$s/template/$a" "edited"
  printf 'new command\n' > "$s/template/cortex/harness/commands/zz-new.md"
  append "$s/template/cortex/AGENTS.md" "edited"
  append "$s/template/cortex/config" "EXTRA=1"
  append "$s/template/cortex/constitution.md" "edited"
  append "$s/template/cortex/changes/pipeline-log.md" "edited"
  run fixture_drift "$CLONE" "$s"
  assert_exit 1 "$CODE" "planted drift fails"
  assert_line "$OUT" "stale cortex/harness/commands/review.md (differs from template/cortex/harness/commands/review.md)" "names review.md"
  assert_line "$OUT" "stale cortex/bin/gates.sh (differs from template/cortex/bin/gates.sh)" "names gates.sh"
  assert_line "$OUT" "stale cortex/design-rules.md (differs from docs/01-design-rules.md)" "names design-rules.md"
  assert_line "$OUT" "stale cortex/version (differs from VERSION)" "names version"
  assert_line "$OUT" "stale $a (differs from template/$a)" "names the installed adapter source"
  assert_line "$OUT" "stale .claude/agents/cortex-reviewer.md (differs from template/$a)" "names the generated adapter"
  assert_line "$OUT" "missing cortex/harness/commands/zz-new.md (template/cortex/harness/commands/zz-new.md exists)" "names the missing file"
  assert_true "only the seven planted files are named (filled-in files are not compared)" \
    [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 7 ]
}

case_planted_tag_changes_harness() {
  local w b
  w="$(mktemp -d "$TEST_TMP/work.XXXXXX")"
  git clone -q "$BUNDLE" "$w"
  git -C "$w" -c advice.detachedHead=false checkout -q golden-planted
  append "$w/cortex/harness/commands/review.md" "planted edit"
  git -C "$w" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -am "edit review.md"
  git -C "$w" tag -f golden-planted >/dev/null
  b="$TEST_TMP/planted.bundle"
  git -C "$w" bundle create -q "$b" --all 2>/dev/null
  run fixture_drift "$(clone_bundle "$b")" "$ROOT"
  assert_exit 1 "$CODE" "golden-planted changing a harness file fails"
  assert_line "$OUT" "planted-changes cortex/harness/commands/review.md" "names the file the planted tag changes"
}

# work_copy -> a working clone of the committed bundle, to move tags in
work_copy() {
  local w
  w="$(mktemp -d "$TEST_TMP/work.XXXXXX")"
  git clone -q "$BUNDLE" "$w"
  printf '%s\n' "$w"
}

# rebundle WORK NAME -> a bare clone of WORK's refs, via a new bundle
rebundle() {
  local b="$TEST_TMP/$2.bundle"
  git -C "$1" bundle create -q "$b" --all 2>/dev/null
  clone_bundle "$b"
}

case_planted_quality_changes_harness() {
  local w
  w="$(work_copy)"
  git -C "$w" -c advice.detachedHead=false checkout -q golden-clean
  append "$w/cortex/harness/commands/review.md" "quality edit"
  git -C "$w" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -am "edit review.md"
  git -C "$w" tag -f golden-quality >/dev/null
  run fixture_drift "$(rebundle "$w" quality)" "$ROOT"
  assert_exit 1 "$CODE" "golden-quality changing a harness file fails"
  assert_line "$OUT" "quality-changes cortex/harness/commands/review.md" "names the file the quality tag changes"
}

case_planted_quality_tag_deleted() {
  local w
  w="$(work_copy)"
  # Exists first (the bundle may or may not carry it yet), then deleted.
  git -C "$w" tag -f golden-quality golden-clean >/dev/null
  git -C "$w" tag -d golden-quality >/dev/null
  run fixture_drift "$(rebundle "$w" no-quality)" "$ROOT"
  assert_exit 1 "$CODE" "a missing golden-quality tag fails"
  assert_line "$OUT" "missing-tag golden-quality" "names the missing tag"
  assert_not_contains "$ERR" "fatal" "the comparisons needing the tag are skipped, not crashed"
}

# ---- A5 (spec 2026-10-05-v3-removable-layout, Amendment 1): the root block ------

# root_block_drift CLONE SRC : prints "stale-block <tag>" for each fixture tag
# whose root AGENTS.md agents block (the lines between its markers) differs
# from SRC/template/blocks/AGENTS.md; exits 1 if any. A missing tag is left
# to fixture_drift.
root_block_drift() {
  local clone="$1" src="$2" t out="" f="$TEST_TMP/.gf-agents.$$"
  for t in $TAGS; do
    git -C "$clone" rev-parse -q --verify "refs/tags/$t" >/dev/null || continue
    git -C "$clone" show "$t:AGENTS.md" > "$f" 2>/dev/null || : > "$f"
    if [ "$(block_count "$f" agents)" != 1 ] ||
      ! block_content "$f" agents | cmp -s - "$src/template/blocks/AGENTS.md"; then
      out="${out}stale-block $t"$'\n'
    fi
  done
  rm -f "$f"
  [ -z "$out" ] || { printf '%s' "$out"; return 1; }
}

case_root_block_matches() {
  # A5: the fixture's root block is template/blocks/AGENTS.md at every tag
  run root_block_drift "$CLONE" "$ROOT"
  assert_exit 0 "$CODE" "the fixture's root agents block matches template/blocks/AGENTS.md (A5)"
}

case_planted_root_block_drift() {
  # A5, planted (R11): an edited block source is named at every tag
  local s t; s="$(copy_src)"
  append "$s/template/blocks/AGENTS.md" "- edited after the fixture was built"
  run root_block_drift "$CLONE" "$s"
  assert_exit 1 "$CODE" "a drifted block source fails (A5)"
  for t in $TAGS; do
    assert_line "$OUT" "stale-block $t" "names $t (A5)"
  done
}

run_case "committed fixture.bundle matches template/" case_committed_bundle_matches
run_case "planted: every drifted or missing source file is named" case_planted_source_drift
run_case "planted: golden-planted changing a harness file is named" case_planted_tag_changes_harness
run_case "planted: golden-quality changing a harness file is named" case_planted_quality_changes_harness
run_case "planted: a deleted golden-quality tag is named" case_planted_quality_tag_deleted
run_case "A5: the fixture's root block matches template/blocks/AGENTS.md" case_root_block_matches
run_case "planted: a drifted root block source is named (A5)" case_planted_root_block_drift
summary
