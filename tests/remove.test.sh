#!/usr/bin/env bash
# Tests for cortex/bin/remove.sh (spec docs/specs/2026-10-05-v3-removable-layout.md:
# "cortex/bin/remove.sh", D6, D11, D14, D15; acceptance criteria 9, 12-20, 32
# and 43; Amendment 1: A1 output lines and summary, A2 exit codes, A6 the
# block's sep field, A8 non-interactive runs).
#
# Every run here is non-interactive (stdin from /dev/null, A8), so remove.sh
# asks nothing: steps 1 and 2 stop without their flags, and records follow
# step 3's default. Most fixtures are a seeded project (seeded_repo, lib.sh)
# with cortex installed, filled, CI=github, adapt.sh run, the printed
# settings entries merged, and everything committed (D14); the tree before
# install is saved beside the repository as "<repo>.pre".
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

SETTINGS=.claude/settings.json

# remove_in DIR [ARGS...] : run DIR's remove.sh from the root, non-interactive (A8)
remove_in() {
  local d="$1"; shift
  run bash -c 'd="$1"; shift; cd "$d" && bash cortex/bin/remove.sh "$@" < /dev/null' _ "$d" "$@"
}

# cortex_seeded -> a seeded project with cortex installed as above, committed;
# its pre-install tree_snapshot is in "<repo>.pre"
cortex_seeded() {
  local d
  d="$(seeded_repo)" || return 1
  tree_snapshot "$d" > "$d.pre"
  install_adapt_github "$d" || return 1
  merge_entries "$d"
  commit_all "$d" "install cortex"
  printf '%s\n' "$d"
}

# insert_after FILE HEADING LINE : LINE right after the line equal to HEADING
insert_after() {
  filter_file "$1" env IA_H="$2" IA_L="$3" awk '
    { print } $0 == ENVIRON["IA_H"] && !done { print ENVIRON["IA_L"]; done = 1 }'
  grep -qxF -- "$3" "$1" || { fail "fixture: $3 not inserted into $1"; return 1; }
}

# add_records DIR : the project's records, committed (D6, D10): a change
# folder, a knowledge edit, a project rule in the constitution, a convention
add_records() {
  local d="$1"
  mkdir -p "$d/cortex/changes/2026-10-08-demo"
  printf '# Proposal: demo\n\nA change the project made.\n' > "$d/cortex/changes/2026-10-08-demo/proposal.md"
  append "$d/cortex/knowledge/glossary.md" "- zz-term: a knowledge edit"
  insert_after "$d/cortex/constitution.md" "## Project" "- P1. zz-project-rule" || return 1
  insert_after "$d/cortex/AGENTS.md" "## Conventions" "- zz-convention" || return 1
  commit_all "$d" "records"
}

# listed_entries TEXT -> the lines remove.sh listed as "entry .claude/settings.json <line>"
listed_entries() {
  printf '%s\n' "$1" | EP="entry $SETTINGS " awk 'index($0, ENVIRON["EP"]) == 1 { print substr($0, length(ENVIRON["EP"]) + 1) }'
}

# unmerge_listed DIR : remove the entry lines remove.sh listed (OUT) from
# settings.json, as the person it lists them for would
unmerge_listed() {
  local d="$1" t="$TEST_TMP/.unmerge.$$"
  listed_entries "$OUT" > "$t"
  [ -f "$d/$SETTINGS" ] || { rm -f "$t"; return 0; }
  filter_file "$d/$SETTINGS" awk -v t="$t" 'BEGIN { while ((getline x < t) > 0) drop[x] = 1 } !($0 in drop) { print }'
  rm -f "$t"
}

last_line() { printf '%s\n' "$1" | sed -n '$p'; }

# block_sep DIR PATH -> the sep field (A6) of PATH's first block record
block_sep() {
  footprint_records "$1" | BS_P="$2" awk -F'\t' '$1 == "block" && $2 == ENVIRON["BS_P"] { print $5; exit }'
}

# remove_summary_re KEPT ENTRIES -> A1's remove summary, any removed count
remove_summary_re() { printf '^remove: [0-9]+ removed, %s kept, %s entries to remove by hand$' "$1" "$2"; }

# ---- criterion 12: the round trip ------------------------------------------------

case_round_trip_delete_records() {
  # criterion 12 (D15: remove.sh runs from a copy while cortex/ is deleted);
  # A1 lines and summary
  local d n head index
  d="$(cortex_seeded)" || return 0
  add_records "$d" || return 0
  n="$(entry_count "$d")"
  head="$(git -C "$d" rev-parse HEAD)"; index="$(git -C "$d" ls-files -s | git hash-object --stdin)"
  assert_true "fixture: settings entries recorded and merged" test "$n" -gt 0
  remove_in "$d" --hosting-done --delete-records
  assert_exit 0 "$CODE" "remove.sh exits 0"
  assert_file_absent "$d/cortex" "cortex/ deleted"
  assert_line "$OUT" "removed block AGENTS.md agents" "A1: removed block AGENTS.md agents"
  assert_line "$OUT" "removed block CLAUDE.md claude" "A1: removed block CLAUDE.md claude"
  assert_line "$OUT" "removed block .github/CODEOWNERS codeowners" "A1: removed block .github/CODEOWNERS codeowners"
  assert_line "$OUT" "removed .github/workflows/cortex.yml" "A1: removed the workflow"
  assert_line "$OUT" "records deleted" "A1: records deleted"
  assert_true "one entry line listed per recorded entry (D4, A1)" test "$(listed_entries "$OUT" | grep -c . || true)" = "$n"
  assert_true "A1: the remove summary is the last line" \
    grep -qE "$(remove_summary_re 0 "$n")" <<<"$(last_line "$OUT")"
  unmerge_listed "$d"
  assert_true "the tree equals the pre-install tree byte for byte, empty directories included (criterion 12)" \
    test "$(tree_snapshot "$d")" = "$(cat "$d.pre")"
  assert_true "no commit made (step 6)" test "$(git -C "$d" rev-parse HEAD)" = "$head"
  assert_true "the index untouched (step 6)" test "$(git -C "$d" ls-files -s | git hash-object --stdin)" = "$index"
}

case_round_trip_keep_records() {
  # criterion 13: --keep-records <dir>: the pre-install tree plus the records
  local d rest
  d="$(cortex_seeded)" || return 0
  add_records "$d" || return 0
  remove_in "$d" --hosting-done --keep-records kept/records
  assert_exit 0 "$CODE" "remove.sh --keep-records exits 0"
  assert_file_absent "$d/cortex" "cortex/ deleted"
  assert_line "$OUT" "records kept/records" "A1: records <dir>"
  unmerge_listed "$d"
  rest="$(tree_snapshot "$d" | awk '{ p = $2 } p !~ /^kept\//')"
  assert_true "outside kept/, the tree equals the pre-install tree (criterion 13)" test "$rest" = "$(cat "$d.pre")"
  assert_true "kept/records holds exactly changes/, knowledge/, constitution.md, conventions.md" \
    test "$(ls -A "$d/kept/records" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')" = "changes constitution.md conventions.md knowledge "
  assert_file_contains "$d/kept/records/changes/2026-10-08-demo/proposal.md" "A change the project made." "the change folder is kept"
  assert_file_exists "$d/kept/records/changes/pipeline-log.md" "the pipeline log is kept"
  assert_file_contains "$d/kept/records/knowledge/glossary.md" "zz-term" "the knowledge edit is kept"
  assert_file_contains "$d/kept/records/constitution.md" "zz-project-rule" "the constitution's project section is kept"
  assert_file_not_contains "$d/kept/records/constitution.md" "## Engineering" "cortex's own rules are not kept (step 3)"
  assert_file_contains "$d/kept/records/conventions.md" "zz-convention" "the Conventions section is kept (D10)"
}

case_default_records() {
  # criterion 14: non-interactive, no records flag: kept in docs/cortex-records/
  local d
  d="$(cortex_seeded)" || return 0
  add_records "$d" || return 0
  remove_in "$d" --hosting-done
  assert_exit 0 "$CODE" "remove.sh without a records flag exits 0"
  assert_line "$OUT" "records docs/cortex-records" "A1: the records path is printed"
  assert_file_contains "$d/docs/cortex-records/knowledge/glossary.md" "zz-term" "records kept in docs/cortex-records/"
  assert_file_absent "$d/cortex" "cortex/ deleted"
}

case_default_records_target_not_empty() {
  # criterion 14: a non-empty target is refused (exit 2, A2) and nothing changes
  local d before
  d="$(cortex_seeded)" || return 0
  mkdir -p "$d/docs/cortex-records"
  printf 'already here\n' > "$d/docs/cortex-records/note.md"
  commit_all "$d" "a records directory already in use"
  before="$(tree_snapshot "$d")"
  remove_in "$d" --hosting-done
  assert_exit 2 "$CODE" "a non-empty records target exits 2 (A2)"
  assert_contains "$OUT$ERR" "docs/cortex-records" "the refusal names the target"
  assert_true "A1: a refused line" has_line_starting "$OUT$ERR" "refused "
  assert_true "nothing changed on the refusal" test "$(tree_snapshot "$d")" = "$before"
}

case_keep_records_target_not_empty() {
  # step 3: --keep-records names a non-empty directory: refused (exit 2)
  local d before
  d="$(cortex_seeded)" || return 0
  mkdir -p "$d/kept"
  printf 'x\n' > "$d/kept/x.md"
  commit_all "$d" "kept/ in use"
  before="$(tree_snapshot "$d")"
  remove_in "$d" --hosting-done --keep-records kept
  assert_exit 2 "$CODE" "a non-empty --keep-records target exits 2 (A2)"
  assert_true "nothing changed on the refusal" test "$(tree_snapshot "$d")" = "$before"
}

# ---- criterion 15: hosting first --------------------------------------------------

case_hosting_steps() {
  # criterion 15, step 1: no --hosting-done and no confirmation: the hosting
  # steps, in order, and nothing changed; a stop exits 0 (A2)
  local d before req own
  d="$(cortex_seeded)" || return 0
  before="$(tree_snapshot "$d")"
  remove_in "$d"
  assert_exit 0 "$CODE" "the stop for confirmation exits 0 (A2)"
  assert_true "nothing changed without --hosting-done" test "$(tree_snapshot "$d")" = "$before"
  req="$(grep -n -i 'required' <<<"$OUT" | grep -i 'check' | sed -n 1p | cut -d: -f1)"
  own="$(grep -n 'Code Owners' <<<"$OUT" | sed -n 1p | cut -d: -f1)"
  assert_true "prints the required-check step" test -n "$req"
  assert_true "prints the Code Owners step" test -n "$own"
  assert_true "the required check comes first (step 1)" test "${req:-0}" -lt "${own:-0}"
  assert_not_contains "$OUT" "removed" "nothing reported removed"
}

# ---- criterion 16: references to cortex/ ------------------------------------------

case_references_listed() {
  # criterion 16, step 2: a project line naming cortex/ is listed (A1
  # "reference <path>:<line>: <text>"); cortex's own blocks, created files
  # and entries are not; "mycortex/" lacks the word boundary; nothing changes
  local d before refs
  d="$(cortex_seeded)" || return 0
  mkdir -p "$d/scripts" "$d/notes"
  printf '#!/bin/sh\nbash cortex/bin/gates.sh cortex/changes/x\n' > "$d/scripts/ci.sh"
  printf 'see mycortex/notes for more\n' > "$d/notes/other.md"
  commit_all "$d" "a project script calling cortex"
  before="$(tree_snapshot "$d")"
  remove_in "$d" --hosting-done --delete-records
  assert_exit 0 "$CODE" "the stop for confirmation exits 0 (A2)"
  assert_line "$OUT" "reference scripts/ci.sh:2: bash cortex/bin/gates.sh cortex/changes/x" "the project line is listed with its file and line (A1)"
  refs="$(grep '^reference ' <<<"$OUT" || true)"
  assert_true "only that line is listed: no blocks, created files, entries or mycortex/" \
    test "$(grep -c . <<<"$refs" || true)" = 1
  assert_true "nothing changed without --references-ok" test "$(tree_snapshot "$d")" = "$before"
  remove_in "$d" --hosting-done --references-ok --delete-records
  assert_exit 0 "$CODE" "with --references-ok remove.sh proceeds"
  assert_file_absent "$d/cortex" "cortex/ deleted"
  assert_file_contains "$d/scripts/ci.sh" "bash cortex/bin/gates.sh" "the project's script is never edited"
}

# ---- criterion 17: created files edited after install ---------------------------

case_created_edited_kept() {
  # criterion 17: an edited created file is listed and kept (A1 "kept <path>
  # (edited after install)"); the summary counts it
  local d n
  d="$(cortex_seeded)" || return 0
  append "$d/.github/workflows/cortex.yml" "# the project's own step"
  commit_all "$d" "edit the workflow"
  n="$(entry_count "$d")"
  remove_in "$d" --hosting-done --delete-records
  assert_exit 0 "$CODE" "remove.sh exits 0"
  assert_line "$OUT" "kept .github/workflows/cortex.yml (edited after install)" "A1: the edited created file is kept"
  assert_file_contains "$d/.github/workflows/cortex.yml" "# the project's own step" "the edited file is kept with its edit"
  assert_true "A1: the summary counts one kept" grep -qE "$(remove_summary_re 1 "$n")" <<<"$(last_line "$OUT")"
}

case_created_edited_force() {
  # criterion 17: --force deletes an edited created file
  local d
  d="$(cortex_seeded)" || return 0
  append "$d/.github/workflows/cortex.yml" "# the project's own step"
  commit_all "$d" "edit the workflow"
  remove_in "$d" --hosting-done --delete-records --force
  assert_exit 0 "$CODE" "remove.sh --force exits 0"
  assert_file_absent "$d/.github/workflows/cortex.yml" "--force deletes the edited created file"
  assert_line "$OUT" "removed .github/workflows/cortex.yml" "A1: removed"
}

case_created_agents_with_project_text() {
  # criterion 17: a created AGENTS.md the project added text to keeps that
  # text and loses the block
  local d
  d="$(new_git_repo)"
  run "$CORTEX_INSTALL" "$d"
  assert_exit 0 "$CODE" "fixture: install exits 0"
  printf '\n## Ours\nproject-text\n' >> "$d/AGENTS.md"
  commit_all "$d" "install, then the project's own section"
  remove_in "$d" --hosting-done --delete-records
  assert_exit 0 "$CODE" "remove.sh exits 0"
  assert_file_exists "$d/AGENTS.md" "AGENTS.md kept: it holds project text"
  assert_file_contains "$d/AGENTS.md" "project-text" "the project's text stays"
  assert_file_contains "$d/AGENTS.md" "## Ours" "the project's heading stays"
  assert_file_not_contains "$d/AGENTS.md" "cortex:begin" "the block is gone"
  assert_file_not_contains "$d/AGENTS.md" "cortex/AGENTS.md" "the block's content is gone"
}

case_created_agents_unedited_deleted() {
  # step 4: a created AGENTS.md left with only whitespace is deleted; an
  # empty repository round-trips to empty (criteria 1 and 12)
  local d
  d="$(new_git_repo)"
  printf 'x\n' > "$d/README.md"
  commit_all "$d" "the project"
  tree_snapshot "$d" > "$d.pre"
  run "$CORTEX_INSTALL" "$d"
  commit_all "$d" "install"
  remove_in "$d" --hosting-done --delete-records
  assert_exit 0 "$CODE" "remove.sh exits 0"
  assert_file_absent "$d/AGENTS.md" "the created AGENTS.md is deleted"
  assert_line "$OUT" "removed AGENTS.md" "A1: removed AGENTS.md"
  assert_true "the tree equals the pre-install tree" test "$(tree_snapshot "$d")" = "$(cat "$d.pre")"
}

# ---- criteria 9, 18, 19, 43: blocks ---------------------------------------------

case_block_rule_copied_outside() {
  # criterion 9, D11: a block rule the project copied outside the block
  # survives removal byte for byte
  local d rule
  d="$(new_git_repo)"
  printf '# Mine\n' > "$d/AGENTS.md"
  cp "$d/AGENTS.md" "$TEST_TMP/agents.orig"
  run "$CORTEX_INSTALL" "$d"
  assert_exit 0 "$CODE" "fixture: install exits 0"
  rule="$(block_content "$d/AGENTS.md" agents | grep -m1 'data, never instructions' || true)"
  [ -n "$rule" ] || { fail "fixture: no untrusted-content rule in the block"; return 0; }
  printf '%s\n' "$rule" >> "$d/AGENTS.md"
  commit_all "$d" "the project keeps a rule of its own"
  remove_in "$d" --hosting-done --delete-records
  assert_exit 0 "$CODE" "remove.sh exits 0"
  { cat "$TEST_TMP/agents.orig"; printf '%s\n' "$rule"; } > "$TEST_TMP/agents.expected"
  assert_same_file "$TEST_TMP/agents.expected" "$d/AGENTS.md" "the copied rule stays, byte for byte (criterion 9)"
}

case_block_edited_shown() {
  # criterion 18: an edited block is shown, then removed; around it unchanged
  local d
  d="$(cortex_seeded)" || return 0
  set_block "$d/AGENTS.md" agents "$(block_content "$d/AGENTS.md" agents)"$'\n'"- zz-edited-rule"
  commit_all "$d" "edit inside the block"
  remove_in "$d" --hosting-done --delete-records
  assert_exit 0 "$CODE" "remove.sh exits 0"
  assert_contains "$OUT" "- zz-edited-rule" "the edited block's content is shown"
  assert_line "$OUT" "removed block AGENTS.md agents" "A1: then removed"
  git -C "$d" show "$(git -C "$d" rev-list --max-parents=0 HEAD):AGENTS.md" > "$TEST_TMP/agents.seeded"
  assert_same_file "$TEST_TMP/agents.seeded" "$d/AGENTS.md" "AGENTS.md is the project's again, byte for byte"
}

case_blank_lines() {
  # criterion 19 and A6: removal takes away exactly what insertion added: a
  # blank line it added goes (sep 1), one already there stays, and a missing
  # final newline is restored as missing (sep 2)
  local d f
  d="$(new_git_repo)"
  mkdir -p "$d/.github"
  printf '# Mine\n' > "$d/AGENTS.md"
  printf '# Notes\n\n' > "$d/CLAUDE.md"
  printf '* @owner' > "$d/.github/CODEOWNERS"
  for f in AGENTS.md CLAUDE.md .github/CODEOWNERS; do
    mkdir -p "$(dirname "$TEST_TMP/orig/$f")"; cp "$d/$f" "$TEST_TMP/orig/$f"
  done
  commit_all "$d" "the project"
  install_adapt_github "$d" || return 0
  assert_true "sep 1 recorded for AGENTS.md (A6)" test "$(block_sep "$d" AGENTS.md)" = 1
  assert_true "sep 2 recorded for a CODEOWNERS without a final newline (A6)" test "$(block_sep "$d" .github/CODEOWNERS)" = 2
  commit_all "$d" "install"
  remove_in "$d" --hosting-done --delete-records
  assert_exit 0 "$CODE" "remove.sh exits 0"
  for f in AGENTS.md CLAUDE.md .github/CODEOWNERS; do
    assert_same_file "$TEST_TMP/orig/$f" "$d/$f" "$f restored byte for byte (criterion 19, A6)"
  done
}

case_crlf_round_trip() {
  # criterion 43, D15: a block in a CRLF AGENTS.md is CRLF; removal restores
  # the file byte for byte
  local d total crlf
  d="$(new_git_repo)"
  printf '# Mine\r\n\r\nRun make test.\r\n' > "$d/AGENTS.md"
  cp "$d/AGENTS.md" "$TEST_TMP/agents.crlf"
  commit_all "$d" "the project"
  run "$CORTEX_INSTALL" "$d"
  assert_exit 0 "$CODE" "install into a CRLF AGENTS.md exits 0"
  total="$(grep -c '' "$d/AGENTS.md")"
  crlf="$(grep -c "$(printf '\r')\$" "$d/AGENTS.md" || true)"
  assert_true "every line of AGENTS.md, the block's included, ends in CRLF (D15)" test "$total" = "$crlf"
  commit_all "$d" "install"
  remove_in "$d" --hosting-done --delete-records
  assert_exit 0 "$CODE" "remove.sh exits 0"
  assert_same_file "$TEST_TMP/agents.crlf" "$d/AGENTS.md" "the CRLF AGENTS.md is restored byte for byte (criterion 43)"
}

# ---- criteria 20 and 32: refusals ---------------------------------------------------

case_dirty_tree_refused() {
  # criterion 20, D14: uncommitted changes (tracked or untracked): exit 2, no change
  local d before
  d="$(cortex_seeded)" || return 0
  append "$d/README.md" "uncommitted"
  before="$(tree_snapshot "$d")"
  remove_in "$d" --hosting-done --delete-records
  assert_exit 2 "$CODE" "a modified file: exit 2 (D14, A2)"
  assert_true "A1: a refused line" has_line_starting "$OUT$ERR" "refused "
  assert_true "nothing changed" test "$(tree_snapshot "$d")" = "$before"
  git -C "$d" checkout -q -- README.md
  printf 'new\n' > "$d/untracked.txt"
  before="$(tree_snapshot "$d")"
  remove_in "$d" --hosting-done --delete-records
  assert_exit 2 "$CODE" "an untracked file: exit 2 (D14)"
  assert_true "nothing changed" test "$(tree_snapshot "$d")" = "$before"
}

case_unknown_footprint_format() {
  # criterion 32: an unknown footprint format: exit 2, named, nothing changed
  local d before
  d="$(cortex_seeded)" || return 0
  filter_file "$d/cortex/footprint" awk 'NR == 1 { print "# cortex footprint 99"; next } { print }'
  commit_all "$d" "a footprint from the future"
  before="$(tree_snapshot "$d")"
  remove_in "$d" --hosting-done --delete-records
  assert_exit 2 "$CODE" "an unknown footprint format exits 2"
  assert_contains "$OUT$ERR" "footprint 99" "the format is named"
  assert_true "nothing changed" test "$(tree_snapshot "$d")" = "$before"
}

run_case "criterion 12: round trip with --delete-records" case_round_trip_delete_records
run_case "criterion 13: round trip with --keep-records <dir>" case_round_trip_keep_records
run_case "criterion 14: records kept in docs/cortex-records/ by default" case_default_records
run_case "criterion 14: a non-empty default target refused" case_default_records_target_not_empty
run_case "step 3: a non-empty --keep-records target refused" case_keep_records_target_not_empty
run_case "criterion 15: hosting steps first, nothing changed" case_hosting_steps
run_case "criterion 16: project references listed, nothing changed" case_references_listed
run_case "criterion 17: an edited created file kept" case_created_edited_kept
run_case "criterion 17: --force deletes an edited created file" case_created_edited_force
run_case "criterion 17: a created AGENTS.md keeps project text" case_created_agents_with_project_text
run_case "step 4: an unedited created AGENTS.md deleted" case_created_agents_unedited_deleted
run_case "criterion 9: a block rule copied outside the block survives" case_block_rule_copied_outside
run_case "criterion 18: an edited block shown, then removed" case_block_edited_shown
run_case "criterion 19, A6: blank lines and final newlines restored" case_blank_lines
run_case "criterion 43: CRLF AGENTS.md round trip" case_crlf_round_trip
run_case "criterion 20: a dirty work tree refused" case_dirty_tree_refused
run_case "criterion 32: unknown footprint format refused by remove" case_unknown_footprint_format
summary
