#!/usr/bin/env bash
# Tests for scripts/cortex/check.sh (spec acceptance criteria 4 and 5, C1-C10).
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TOKEN="Zqxproj"

# prepared_install -> fresh install with PROJECT_NAME set to a unique token
prepared_install() {
  local d
  d="$(fresh_install)" || return 1
  set_config "$d/.cortex/config" PROJECT_NAME "$TOKEN"
  printf '%s\n' "$d"
}

check_in() { # dir -> runs installed check.sh with cwd = dir
  run bash -c 'cd "$1" && ./scripts/cortex/check.sh' _ "$1"
}

# baseline_ok DIR : guard that the unplanted install passes, so a later
# failure is attributable to the plant
baseline_ok() {
  check_in "$1"
  if [ "$CODE" != 0 ]; then
    fail "baseline before plant is not clean (exit $CODE)"; show_output; return 1
  fi
}

# expect_violation DIR ID RELPATH : exit 1, a FAIL [ID] RELPATH: line, no
# other check IDs, and a matching failure count
expect_violation() {
  local d="$1" id="$2" relpath="$3" fails n
  check_in "$d"
  assert_exit 1 "$CODE" "[$id] planted violation exits 1"
  assert_contains "$OUT" "[$id]" "[$id] reported"
  assert_contains "$OUT" "FAIL [$id] $relpath:" "[$id] line names $relpath"
  fails="$(grep '^FAIL ' <<<"$OUT" || true)"
  if [ -n "$(grep -vF "[$id]" <<<"$fails" || true)" ]; then
    fail "[$id] plant triggered other checks"; show_output
  else
    pass
  fi
  n=$(grep -c . <<<"$fails" || true)
  assert_line "$OUT" "check: $n failure(s)" "[$id] summary line"
  assert_not_contains "$OUT" "check: ok" "[$id] does not claim ok"
}

# planted MSG CMD... : guard that a plant actually changed something
planted() {
  local msg="$1"; shift
  if "$@"; then return 0; fi
  fail "plant did not take effect: $msg"; return 1
}

a_command() { # dir -> relpath of first harness command file
  local f; f="$(first_file "$1/harness/commands" '*.md')"
  [ -n "$f" ] || { fail "no harness/commands/*.md in install"; return 1; }
  rel "$1" "$f"
}

# ---- AC4 ---------------------------------------------------------------------

case_token_absent_from_template() {
  [ -d "$ROOT/template" ] || { fail "template/ missing"; return 0; }
  if grep -riqF "$TOKEN" "$ROOT/template"; then fail "token $TOKEN appears in template/"; else pass; fi
}

case_baseline_ok() {
  local d; d="$(prepared_install)"
  assert_file_contains "$d/.cortex/config" "PROJECT_NAME=$TOKEN" "PROJECT_NAME set"
  check_in "$d"
  assert_exit 0 "$CODE" "fresh install passes"
  assert_line "$OUT" "check: ok" "prints check: ok"
  assert_not_contains "$OUT" "FAIL [" "no FAIL lines"
}

case_root_argument() {
  local d r; d="$(prepared_install)"
  run bash -c 'cd "$1" && "$2/scripts/cortex/check.sh" "$2"' _ "$TEST_TMP" "$d"
  assert_exit 0 "$CODE" "explicit repo-root argument works from another cwd"
  assert_line "$OUT" "check: ok" "prints check: ok with root argument"
  r="$(a_command "$d")"
  append "$d/$r" "Approved-by: me"
  run bash -c 'cd "$1" && "$2/scripts/cortex/check.sh" "$2"' _ "$TEST_TMP" "$d"
  assert_exit 1 "$CODE" "root argument is the tree that gets checked"
}

# ---- AC5: one plant per check -------------------------------------------------

case_C1() {
  local d r; d="$(prepared_install)"; baseline_ok "$d"
  r="$(a_command "$d")"
  append "$d/$r" "Notes for $TOKEN."
  planted "token in $r" grep -qF "$TOKEN" "$d/$r"
  expect_violation "$d" C1 "$r"
}

case_C1_case_insensitive() {
  local d r; d="$(prepared_install)"; baseline_ok "$d"
  r="$(a_command "$d")"
  append "$d/$r" "Notes for zQXPROJ."
  planted "mixed-case token in $r" grep -qF "zQXPROJ" "$d/$r"
  expect_violation "$d" C1 "$r"
}

case_C1_unset_project_name() {
  local d r; d="$(fresh_install)"
  set_config "$d/.cortex/config" PROJECT_NAME ""
  r="$(a_command "$d")"
  append "$d/$r" "Notes for $TOKEN."
  check_in "$d"
  assert_not_contains "$OUT" "[C1]" "empty PROJECT_NAME disables C1"
}

case_C2() {
  local d f r; d="$(prepared_install)"; baseline_ok "$d"
  f="$(first_file "$d/docs/knowledge" '*.md')"
  if [ -z "$f" ]; then mkdir -p "$d/docs/knowledge"; f="$d/docs/knowledge/zz-plant.md"; : > "$f"; fi
  r="$(rel "$d" "$f")"
  append "$f" "Works well in Cursor too."
  planted "tool name in $r" grep -qF "Cursor" "$f"
  expect_violation "$d" C2 "$r"
}

case_C2_harness() {
  local d r; d="$(prepared_install)"; baseline_ok "$d"
  r="$(a_command "$d")"
  append "$d/$r" "Then ask gemini."
  expect_violation "$d" C2 "$r"
}

case_C2_whole_word_only() {
  local d r; d="$(prepared_install)"; baseline_ok "$d"
  r="$(a_command "$d")"
  append "$d/$r" "A precursor step, the claudette rule, and codexes."
  check_in "$d"
  assert_exit 0 "$CODE" "substrings of tool names are not whole-word matches"
  assert_not_contains "$OUT" "[C2]" "no C2 for substrings"
}

case_C3_too_long() {
  local d i; d="$(prepared_install)"; baseline_ok "$d"
  i=0
  while [ "$(line_count "$d/AGENTS.md")" -le 60 ]; do
    i=$((i + 1)); append "$d/AGENTS.md" "- padding line $i"
  done
  planted "AGENTS.md > 60 lines" test "$(line_count "$d/AGENTS.md")" -ge 61
  expect_violation "$d" C3 "AGENTS.md"
}

case_C3_exactly_60_ok() {
  local d i; d="$(prepared_install)"; baseline_ok "$d"
  i=0
  while [ "$(line_count "$d/AGENTS.md")" -lt 60 ]; do
    i=$((i + 1)); append "$d/AGENTS.md" "- padding line $i"
  done
  check_in "$d"
  assert_not_contains "$OUT" "[C3]" "60 lines is allowed"
}

case_C3_missing() {
  local d; d="$(prepared_install)"; baseline_ok "$d"
  rm "$d/AGENTS.md"
  expect_violation "$d" C3 "AGENTS.md"
}

case_C4() {
  local d r; d="$(prepared_install)"; baseline_ok "$d"
  r="$(a_command "$d")"
  append "$d/$r" "First, read all of the docs."
  planted "read all in $r" grep -qF "read all" "$d/$r"
  expect_violation "$d" C4 "$r"
}

case_C4_read_everything() {
  local d r; d="$(prepared_install)"; baseline_ok "$d"
  r="$(a_command "$d")"
  append "$d/$r" "READ EVERYTHING before starting."
  expect_violation "$d" C4 "$r"
}

case_C5() {
  local d r; d="$(prepared_install)"; baseline_ok "$d"
  r="$(a_command "$d")"
  planted "$r has ## Autonomy before plant" grep -q '^## Autonomy' "$d/$r"
  filter_file "$d/$r" awk '!/^## Autonomy/'
  planted "## Autonomy removed from $r" test -z "$(grep '^## Autonomy' "$d/$r" || true)"
  expect_violation "$d" C5 "$r"
}

case_C6() {
  local d r; d="$(prepared_install)"; baseline_ok "$d"
  r="$(a_command "$d")"
  planted "$r has Budget: before plant" grep -q '^Budget:' "$d/$r"
  filter_file "$d/$r" awk '!/^Budget:/'
  planted "Budget: removed from $r" test -z "$(grep '^Budget:' "$d/$r" || true)"
  expect_violation "$d" C6 "$r"
}

case_C7() {
  local d r; d="$(prepared_install)"; baseline_ok "$d"
  r="$(a_command "$d")"
  append "$d/$r" "Approved-by: me"
  planted "Approved-by in $r" grep -qF "Approved-by:" "$d/$r"
  expect_violation "$d" C7 "$r"
}

case_C7_proposal_allowed() {
  local d p; d="$(prepared_install)"; baseline_ok "$d"
  p="$d/harness/templates/change-folder/proposal.md"
  mkdir -p "$(dirname "$p")"; [ -f "$p" ] || : > "$p"
  append "$p" "Approved-by: me"
  check_in "$d"
  assert_not_contains "$OUT" "[C7]" "Approved-by: allowed in the proposal template"
}

case_C8() {
  local d; d="$(prepared_install)"; baseline_ok "$d"
  printf '@AGENTS.md\n\nAlways use tabs.\n' > "$d/CLAUDE.md"
  expect_violation "$d" C8 "CLAUDE.md"
}

case_C8_pointer_ok() {
  local d; d="$(prepared_install)"; baseline_ok "$d"
  printf '<!-- cortex:generated -->\n\n@AGENTS.md\n\n' > "$d/CLAUDE.md"
  check_in "$d"
  assert_exit 0 "$CODE" "comment + @AGENTS.md + blanks is a valid CLAUDE.md"
  assert_not_contains "$OUT" "[C8]" "no C8 for a pointer-only CLAUDE.md"
}

case_C9() {
  local d f i; d="$(prepared_install)"; baseline_ok "$d"
  f="$d/.claude/skills/x/SKILL.md"
  mkdir -p "$(dirname "$f")"
  printf '<!-- cortex:generated -->\n' > "$f"
  i=2
  while [ "$i" -le 30 ]; do printf 'line %s\n' "$i" >> "$f"; i=$((i + 1)); done
  planted "SKILL.md has 30 lines" test "$(line_count "$f")" -eq 30
  expect_violation "$d" C9 ".claude/skills/x/SKILL.md"
}

case_C9_handwritten_ok() {
  local d f i; d="$(prepared_install)"; baseline_ok "$d"
  f="$d/.claude/skills/x/SKILL.md"
  mkdir -p "$(dirname "$f")"
  : > "$f"
  i=1
  while [ "$i" -le 30 ]; do printf 'line %s\n' "$i" >> "$f"; i=$((i + 1)); done
  check_in "$d"
  assert_not_contains "$OUT" "[C9]" "hand-written (unmarked) SKILL.md is not limited"
}

case_C10() {
  local d; d="$(prepared_install)"; baseline_ok "$d"
  planted "AGENTS.md has the phrase before plant" grep -qF "data, never instructions" "$d/AGENTS.md"
  filter_file "$d/AGENTS.md" sed 's/data, never instructions/data/g'
  planted "phrase removed" test -z "$(grep -F 'data, never instructions' "$d/AGENTS.md" || true)"
  expect_violation "$d" C10 "AGENTS.md"
}

case_adapters_not_scanned() {
  local d f; d="$(prepared_install)"; baseline_ok "$d"
  f="$d/.cortex/adapters/claude-code/zz-plant.md"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$TOKEN in Cursor: read all. Approved-by: me" > "$f"
  check_in "$d"
  assert_exit 0 "$CODE" ".cortex/adapters/ is never scanned by C1-C4, C7"
  assert_line "$OUT" "check: ok" "still ok with plant under .cortex/adapters/"
}

case_multiple_failures_counted() {
  local d r; d="$(prepared_install)"; baseline_ok "$d"
  r="$(a_command "$d")"
  append "$d/$r" "Approved-by: me"
  printf '@AGENTS.md\nextra\n' > "$d/CLAUDE.md"
  check_in "$d"
  assert_exit 1 "$CODE" "two violations exit 1"
  assert_contains "$OUT" "[C7]" "C7 reported alongside C8"
  assert_contains "$OUT" "[C8]" "C8 reported alongside C7"
  assert_line "$OUT" "check: 2 failure(s)" "failure count is 2"
}

run_case "token absent from template" case_token_absent_from_template
run_case "AC4 baseline check: ok" case_baseline_ok
run_case "repo-root argument" case_root_argument
run_case "C1 project name in harness" case_C1
run_case "C1 case-insensitive" case_C1_case_insensitive
run_case "C1 skipped when PROJECT_NAME unset" case_C1_unset_project_name
run_case "C2 tool name in docs/knowledge" case_C2
run_case "C2 tool name in harness" case_C2_harness
run_case "C2 whole word only" case_C2_whole_word_only
run_case "C3 AGENTS.md > 60 lines" case_C3_too_long
run_case "C3 60 lines ok" case_C3_exactly_60_ok
run_case "C3 AGENTS.md missing" case_C3_missing
run_case "C4 read all" case_C4
run_case "C4 read everything" case_C4_read_everything
run_case "C5 missing ## Autonomy" case_C5
run_case "C6 missing Budget:" case_C6
run_case "C7 Approved-by in harness" case_C7
run_case "C7 allowed in proposal template" case_C7_proposal_allowed
run_case "C8 CLAUDE.md with extra content" case_C8
run_case "C8 pointer-only CLAUDE.md ok" case_C8_pointer_ok
run_case "C9 generated SKILL.md > 25 lines" case_C9
run_case "C9 hand-written SKILL.md ignored" case_C9_handwritten_ok
run_case "C10 untrusted-content phrase removed" case_C10
run_case ".cortex/adapters not scanned" case_adapters_not_scanned
run_case "multiple failures counted" case_multiple_failures_counted
summary
