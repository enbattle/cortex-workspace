#!/usr/bin/env bash
# Tests for cortex/bin/adapt.sh (spec acceptance criteria 7, 8, 11 and 20;
# 3.0.0 per docs/specs/2026-10-05-v3-removable-layout.md: criteria 8, 10 and
# 11, D4/D8/D11, Amendment 1 A1-A4).
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

# A4: the cortex:generated marker is dropped (was: MARKER="cortex:generated",
# asserted in every generated file); the footprint records what is cortex's.
ADAPTERS="cortex/adapters/claude-code"
# the 2.x message for an existing settings.json; 3.0.0 prints entries instead (Q1)
SETTINGS_SKIP="skipped .claude/settings.json (exists; merge the permissions block from cortex/adapters/claude-code/.claude/settings.json)"

tools_install() { # tools -> fresh install with TOOLS set
  local d
  d="$(fresh_install)" || return 1
  set_config "$d/cortex/config" TOOLS "$1"
  printf '%s\n' "$d"
}

adapt() { # dir -> run installed adapt.sh with cwd = dir
  run bash -c 'cd "$1" && ./cortex/bin/adapt.sh' _ "$1"
}

# adapter source files, relative to cortex/adapters/claude-code/
adapter_files() {
  (cd "$1/$ADAPTERS" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
}

# first adapter file that is not settings.json
an_adapter_file() {
  adapter_files "$1" | grep -v 'settings\.json$' | sed -n 1p
}

nonblank() { grep -v '^[[:space:]]*$' "$1" || true; }

case_missing_config() {
  local d; d="$(fresh_install)"
  rm "$d/cortex/config"
  adapt "$d"
  assert_exit 2 "$CODE" "missing cortex/config exits 2"
}

case_template_has_adapters() {
  assert_file_exists "$ROOT/template/$ADAPTERS/.claude/settings.json" "template ships the Claude settings.json source"
  if [ -d "$ROOT/template/$ADAPTERS" ] && [ -n "$(adapter_files "$ROOT/template" | grep -v 'settings\.json$' || true)" ]; then
    pass
  else
    fail "template ships Claude adapter files besides settings.json"
  fi
}

case_all_tools() {
  local d f expected
  d="$(tools_install claude,cursor,copilot,gemini,codex)"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0"
  # D4/C8: a created CLAUDE.md holds only the claude block, whose content is
  # @AGENTS.md (was: the generated-marker comment + @AGENTS.md)
  expected="$(printf '<!-- cortex:begin claude -->\n@AGENTS.md\n<!-- cortex:end claude -->')"
  assert_true "CLAUDE.md is the claude block holding @AGENTS.md" test "$(nonblank "$d/CLAUDE.md")" = "$expected"
  # A1: a block line (was: "wrote CLAUDE.md"); A3: created, content in a block
  assert_line "$OUT" "block CLAUDE.md claude" "reports block CLAUDE.md claude (A1)"
  assert_true "CLAUDE.md recorded created (A3)" has_record "$d" created CLAUDE.md
  assert_true "CLAUDE.md's claude block recorded (A3)" has_record "$d" block CLAUDE.md claude
  # claude: every adapter source copied to the repo root
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    assert_same_file "$d/$ADAPTERS/$f" "$d/$f" "adapter $f copied verbatim"
    if [ "${f##*/}" != "settings.json" ]; then
      # A4: no marker assertion (was: "adapter $f carries the marker")
      # A1: "created $f" (was: "wrote $f"); A3: a whole file, recorded created
      assert_line "$OUT" "created $f" "reports created $f (A1)"
      assert_true "$f recorded created (A3)" has_record "$d" created "$f"
    fi
  done <<<"$(adapter_files "$d")"
  assert_file_exists "$d/.claude/settings.json" "settings.json copied when absent"
  # cursor
  f="$d/.cursor/rules/cortex.mdc"
  assert_file_exists "$f" "cursor rule written"
  assert_file_contains "$f" "alwaysApply: true" "cursor rule always applies"
  assert_file_contains "$f" "AGENTS.md" "cursor rule points to AGENTS.md"
  # A4: no marker assertion (was: "cursor rule carries the marker")
  # A1: "created" (was: "wrote .cursor/rules/cortex.mdc"); A3: a whole file
  assert_line "$OUT" "created .cursor/rules/cortex.mdc" "reports cursor rule (A1)"
  assert_true "cursor rule recorded created (A3)" has_record "$d" created .cursor/rules/cortex.mdc
  # copilot
  f="$d/.github/copilot-instructions.md"
  assert_file_contains "$f" "AGENTS.md" "copilot file points to AGENTS.md"
  # A4: no marker assertion (was: "copilot file carries the marker")
  # A3: a shared tool file holds cortex's content in a block even when created
  assert_true "copilot file's content is in a copilot block (A3)" \
    grep -qF "AGENTS.md" <<<"$(block_content "$f" copilot)"
  assert_true "copilot file recorded created and block (A3)" \
    eval 'has_record "$d" created .github/copilot-instructions.md && has_record "$d" block .github/copilot-instructions.md copilot'
  # A1: a block line (was: "wrote .github/copilot-instructions.md")
  assert_line "$OUT" "block .github/copilot-instructions.md copilot" "reports copilot block (A1)"
  # gemini
  assert_file_contains "$d/GEMINI.md" "AGENTS.md" "GEMINI.md points to AGENTS.md"
  # A4: no marker assertion (was: "GEMINI.md carries the marker")
  assert_true "GEMINI.md's content is in a gemini block (A3)" \
    grep -qF "AGENTS.md" <<<"$(block_content "$d/GEMINI.md" gemini)"
  assert_true "GEMINI.md recorded created and block (A3)" \
    eval 'has_record "$d" created GEMINI.md && has_record "$d" block GEMINI.md gemini'
  # A1: a block line (was: "wrote GEMINI.md")
  assert_line "$OUT" "block GEMINI.md gemini" "reports GEMINI.md block (A1)"
  # codex
  assert_line "$OUT" "codex: reads AGENTS.md natively" "codex needs no file"
}

case_second_run_idempotent() {
  local d; d="$(tools_install claude,cursor,copilot,gemini,codex)"
  adapt "$d"
  assert_exit 0 "$CODE" "first run exits 0"
  adapt "$d"
  assert_exit 0 "$CODE" "second run exits 0"
  # A1: no created or block lines (was: no "wrote" lines)
  assert_true "second run prints no created or block lines (A1)" test -z "$(grep -E '^(created|block) ' <<<"$OUT" || true)"
  assert_line "$OUT" "unchanged CLAUDE.md" "CLAUDE.md unchanged"
  assert_line "$OUT" "unchanged GEMINI.md" "GEMINI.md unchanged"
  assert_line "$OUT" "unchanged .cursor/rules/cortex.mdc" "cursor rule unchanged"
  assert_line "$OUT" "unchanged .github/copilot-instructions.md" "copilot file unchanged"
}

case_handwritten_claude_md_gets_block() {
  # was "hand-written CLAUDE.md skipped": D4/D11, a hand-written file is no
  # longer skipped but gets a block; the project's content stays
  local d; d="$(tools_install claude)"
  printf '# My notes\nUse tabs.\n' > "$d/CLAUDE.md"
  cp "$d/CLAUDE.md" "$TEST_TMP/claude.orig"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0 with a hand-written CLAUDE.md"
  # D4: the claude block is inserted (was: the "skipped CLAUDE.md" line)
  assert_true "hand-written CLAUDE.md gets the claude block holding @AGENTS.md (D4)" \
    test "$(block_content "$d/CLAUDE.md" claude | grep -v '^[[:space:]]*$' || true)" = "@AGENTS.md"
  # D11: the project's bytes stay, ahead of the block (was: whole file untouched)
  assert_true "hand-written CLAUDE.md content kept ahead of the block (D11)" \
    file_starts_with "$d/CLAUDE.md" "$TEST_TMP/claude.orig"
}

case_edited_block_regenerated() {
  # was "marked file is regenerated" (a file carrying the 2.x generated
  # marker): in 3.0.0 cortex's content lives in the claude block, and an edit
  # inside the block is overwritten on the next run ("Marked blocks", D4)
  local d; d="$(tools_install claude)"
  adapt "$d"
  set_block "$d/CLAUDE.md" claude "stale"
  # "Marked blocks": the overwrite is reported (was: "wrote CLAUDE.md")
  adapt "$d"
  assert_line "$OUT" "overwrote edited block CLAUDE.md claude" "an edited claude block is regenerated and reported"
  assert_file_not_contains "$d/CLAUDE.md" "stale" "stale content replaced"
  assert_file_contains "$d/CLAUDE.md" "@AGENTS.md" "regenerated pointer"
}

case_handwritten_adapter_refused() {
  # was "hand-written adapter file skipped": every Claude adapter path is
  # cortex-named (.claude/agents/cortex-*.md, .claude/skills/cortex-*/), so
  # an unrecorded file there is refused, naming it (D11)
  local d f; d="$(tools_install claude)"
  f="$(an_adapter_file "$d")"
  [ -n "$f" ] || { fail "no adapter file to test"; return 0; }
  mkdir -p "$(dirname "$d/$f")"
  printf 'hand-written\n' > "$d/$f"
  adapt "$d"
  # D11: refused, naming the file (was: the "skipped $f" line)
  # A2: the refusal exits 2 (was: any nonzero exit)
  assert_exit 2 "$CODE" "an unrecorded cortex-named $f is refused (D11, A2)"
  assert_contains "$OUT$ERR" "$f" "the refusal names $f (D11)"
  assert_true "A1: a refused line" has_line_starting "$OUT$ERR" "refused "
  assert_true "$f untouched" test "$(cat "$d/$f")" = "hand-written"
}

case_existing_settings_untouched() {
  local d; d="$(tools_install claude)"
  mkdir -p "$d/.claude"
  printf '{"mine": true}\n' > "$d/.claude/settings.json"
  cp "$d/.claude/settings.json" "$TEST_TMP/settings.orig"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0 with existing settings.json"
  # Q1/D4: cortex's rules missing from an existing settings.json are printed
  # for merging as entries (was: the 2.x skip message)
  assert_contains "$OUT" 'Bash(bash cortex/bin/*)' "settings.json: missing rules printed for merging (Q1)"
  # A1: printed as "entry <path> <line>" lines
  assert_true "the rules are entry lines (A1)" \
    grep -qF 'Bash(bash cortex/bin/*)' <<<"$(grep '^entry \.claude/settings\.json ' <<<"$OUT" || true)"
  assert_same_file "$TEST_TMP/settings.orig" "$d/.claude/settings.json" "settings.json never touched"
  adapt "$d"
  assert_same_file "$TEST_TMP/settings.orig" "$d/.claude/settings.json" "settings.json untouched on second run"
}

case_claude_only() {
  local d; d="$(tools_install claude)"
  adapt "$d"
  assert_exit 0 "$CODE" "claude-only exits 0"
  assert_file_exists "$d/CLAUDE.md" "CLAUDE.md written"
  assert_file_absent "$d/GEMINI.md" "no GEMINI.md for claude-only"
  assert_file_absent "$d/.cursor/rules/cortex.mdc" "no cursor rule for claude-only"
  assert_file_absent "$d/.github/copilot-instructions.md" "no copilot file for claude-only"
}

case_unknown_tool() {
  local d; d="$(tools_install claude,bogus)"
  adapt "$d"
  assert_exit 0 "$CODE" "unknown tool does not fail"
  assert_contains "$OUT$ERR" "warning: unknown tool bogus" "unknown tool warned"
  assert_file_exists "$d/CLAUDE.md" "known tools still handled"
}

case_root_argument() {
  local d; d="$(tools_install gemini)"
  run bash -c 'cd "$1" && "$2/cortex/bin/adapt.sh" "$2"' _ "$TEST_TMP" "$d"
  assert_exit 0 "$CODE" "repo-root argument from another cwd"
  assert_file_exists "$d/GEMINI.md" "wrote into the given root"
}

case_check_ok_after_adapt() {
  local d; d="$(filled_install)"   # A2: a filled baseline, TOOLS=claude
  assert_file_contains "$d/cortex/config" "TOOLS=claude" "fixture sets TOOLS=claude"
  run bash -c 'cd "$1" && ./cortex/bin/check.sh' _ "$d"
  assert_exit 0 "$CODE" "filled baseline passes check before adapt"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0"
  run bash -c 'cd "$1" && ./cortex/bin/check.sh' _ "$d"
  assert_exit 0 "$CODE" "check passes after install + adapt (AC8)"
  assert_line "$OUT" "check: ok" "check: ok after adapt"
}

# ---- AC11 (A3): TOOLS unset -> warning, nothing written --------------------------

TOOLS_WARNING="warning: TOOLS is not set in cortex/config; no adapters written"

# expect_no_adapters DIR LABEL : exit 0, the A3 warning, no files, no wrote lines
expect_no_adapters() {
  local d="$1" what="$2"
  adapt "$d"
  assert_exit 0 "$CODE" "$what: exits 0"
  assert_contains "$OUT$ERR" "$TOOLS_WARNING" "$what: warns TOOLS is not set"
  # A1: no created or block lines (was: no "wrote" lines)
  assert_true "$what: no created or block lines (A1)" test -z "$(grep -E '^(created|block) ' <<<"$OUT" || true)"
  assert_file_absent "$d/CLAUDE.md" "$what: no CLAUDE.md"
  assert_file_absent "$d/GEMINI.md" "$what: no GEMINI.md"
  assert_file_absent "$d/.claude" "$what: no .claude/"
  assert_file_absent "$d/.cursor" "$what: no .cursor/"
  assert_file_absent "$d/.github/copilot-instructions.md" "$what: no copilot file"
}

case_tools_placeholder() {
  local d; d="$(fresh_install)"
  assert_true "template TOOLS is a placeholder" grep -q '^TOOLS=<.*>' "$d/cortex/config"
  expect_no_adapters "$d" "TOOLS placeholder"
}

case_tools_empty() {
  local d; d="$(tools_install "")"
  expect_no_adapters "$d" "TOOLS empty"
}

case_tools_absent() {
  local d; d="$(fresh_install)"
  filter_file "$d/cortex/config" awk '!/^[[:space:]]*TOOLS[[:space:]]*=/'
  assert_true "TOOLS line removed" test -z "$(grep 'TOOLS[[:space:]]*=' "$d/cortex/config" || true)"
  expect_no_adapters "$d" "TOOLS absent"
}

# ---- AC20 (B7): unchanged settings.json; adapters of removed tools --------------
# 3.0.0 ("Other scripts", adapt.sh): a file for a tool removed from TOOLS is
# removed by remove.sh step 4's rules (an unedited created file is deleted)
# instead of reported as stale. The removal's wording isn't specified, so the
# report is checked as a line naming the path.

# names_path: removed; A1 fixed the removal lines, which the cases now match exactly

case_settings_unchanged_on_rerun() {
  local d; d="$(tools_install claude)"
  adapt "$d"
  assert_exit 0 "$CODE" "first run exits 0"
  assert_same_file "$d/$ADAPTERS/.claude/settings.json" "$d/.claude/settings.json" "fixture: settings.json copied"
  adapt "$d"
  assert_exit 0 "$CODE" "second run exits 0"
  assert_line "$OUT" "unchanged .claude/settings.json" "identical settings.json reported unchanged"
  assert_not_contains "$OUT" "$SETTINGS_SKIP" "no merge message for an identical settings.json"
}

case_stale_cursor() {
  local d; d="$(tools_install claude,cursor)"
  adapt "$d"
  assert_file_exists "$d/.cursor/rules/cortex.mdc" "fixture: cursor rule written"
  set_config "$d/cortex/config" TOOLS claude
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0 with a removed tool"
  # 3.0.0 adapt.sh: the removal is reported (was: the "stale" line); A1 fixes
  # its wording (was: a line naming the path)
  assert_line "$OUT" "removed .cursor/rules/cortex.mdc" "the cursor rule's removal is reported (A1)"
  # 3.0.0 adapt.sh, remove.sh step 4: unedited created file deleted (was: kept)
  assert_file_absent "$d/.cursor/rules/cortex.mdc" "unedited cursor rule deleted"
  # was: no "stale CLAUDE.md" line; now: claude's file is kept
  assert_file_exists "$d/CLAUDE.md" "claude is still in TOOLS: CLAUDE.md kept"
}

case_stale_all_known() {
  local d; d="$(tools_install claude,cursor,copilot,gemini)"
  adapt "$d"
  set_config "$d/cortex/config" TOOLS codex
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0"
  # 3.0.0 adapt.sh: each removal is reported (was: four "stale" lines); A1
  # fixes the wording (was: a line naming the path)
  assert_line "$OUT" "removed CLAUDE.md" "CLAUDE.md's removal reported (A1)"
  assert_line "$OUT" "removed .cursor/rules/cortex.mdc" "the cursor rule's removal reported (A1)"
  assert_line "$OUT" "removed .github/copilot-instructions.md" "the copilot file's removal reported (A1)"
  assert_line "$OUT" "removed GEMINI.md" "GEMINI.md's removal reported (A1)"
  # 3.0.0 adapt.sh, remove.sh step 4: each unedited created file is deleted;
  # a created CLAUDE.md left with only whitespace once its block goes is
  # deleted too (was: all four kept)
  assert_file_absent "$d/CLAUDE.md" "CLAUDE.md deleted"
  assert_file_absent "$d/.cursor/rules/cortex.mdc" "cursor rule deleted"
  assert_file_absent "$d/.github/copilot-instructions.md" "copilot file deleted"
  assert_file_absent "$d/GEMINI.md" "GEMINI.md deleted"
}

case_stale_ignores_handwritten() {
  local d; d="$(tools_install claude)"
  printf '# my gemini notes\n' > "$d/GEMINI.md"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0"
  assert_not_contains "$OUT" "stale GEMINI.md" "a hand-written (unmarked) file is not reported stale"
  assert_true "hand-written GEMINI.md untouched" test "$(cat "$d/GEMINI.md")" = "# my gemini notes"
}

# ---- AC32-34 (Amendment 6, F1/F2): one config parser ----------------------------

ac32_adapt() { # KIND : TOOLS parsed per the format section (real gemini, other cursor)
  local kind="$1" d; d="$(fresh_install)"
  config_variant "$d/cortex/config" "$kind" TOOLS gemini cursor
  adapt "$d"
  assert_exit 0 "$CODE" "$kind: adapt exits 0"
  # A1: a block line (was: "wrote GEMINI.md")
  assert_line "$OUT" "block GEMINI.md gemini" "$kind: the real TOOLS value is used (A1)"
  # A4: the marker is dropped; the gemini block shows it was written
  assert_true "$kind: GEMINI.md written (A4)" test "$(block_count "$d/GEMINI.md" gemini)" = 1
  assert_file_absent "$d/.cursor" "$kind: the other value is not read as TOOLS"
  assert_not_contains "$OUT$ERR" "$TOOLS_WARNING" "$kind: TOOLS is set"
  assert_not_contains "$OUT$ERR" "unknown tool" "$kind: no unknown tool"
}

case_AC32_spaced() { ac32_adapt spaced; }
case_AC32_comment() { ac32_adapt comment; }
case_AC32_no_equals() { ac32_adapt no-equals; }
case_AC32_twice() { ac32_adapt twice; }

case_AC33_spaced_list() {
  local d; d="$(tools_install "claude , cursor")"
  assert_file_contains "$d/cortex/config" "TOOLS=claude , cursor" "fixture: TOOLS has spaces around the comma"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0"
  # A1: a block line (was: "wrote CLAUDE.md")
  assert_line "$OUT" "block CLAUDE.md claude" "claude adapter written (A1)"
  assert_file_exists "$d/CLAUDE.md" "CLAUDE.md written"
  # A1: "created" (was: "wrote .cursor/rules/cortex.mdc")
  assert_line "$OUT" "created .cursor/rules/cortex.mdc" "cursor adapter written (A1)"
  assert_file_exists "$d/.cursor/rules/cortex.mdc" "cursor rule written"
  assert_not_contains "$OUT$ERR" "unknown tool" "whitespace is not part of a tool name"
}

case_AC34_stub_parser() {
  local d; d="$(tools_install claude,cursor,copilot,gemini)"
  write_stub_parser "$d"
  expect_no_adapters "$d" "stub _config.sh"
}

# ---- 3.0.0 ownership (spec 2026-10-05-v3-removable-layout, D4, D11, Q1) -----------

case_v3_settings_created() {
  # criterion 8: without .claude/settings.json, adapt.sh creates it, recorded
  local d; d="$(tools_install claude)"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0"
  assert_file_exists "$d/.claude/settings.json" "settings.json created"
  assert_true "settings.json recorded created (criterion 8)" has_record "$d" created .claude/settings.json
  assert_line "$OUT" "created .claude/settings.json" "A1: created .claude/settings.json"
  assert_true "no entries for a created settings.json" test "$(entry_count "$d")" = 0
}

case_v3_settings_entries() {
  # criterion 8, D11, Q1: a rule already in the file is neither printed nor
  # recorded; the others are printed (A1 entry lines) and recorded; the file
  # is byte-identical
  local d rule other printed
  d="$(tools_install claude)"
  rule="$(seed_rule)"
  other="$(grep -m1 -F 'Bash(git diff' "$d/$ADAPTERS/.claude/settings.json" || true)"
  [ -n "$other" ] || { fail "fixture: no git diff rule in the adapter source"; return 0; }
  mkdir -p "$d/.claude"
  printf '{\n  "permissions": {\n    "allow": [\n%s\n    ]\n  }\n}\n' "$rule" > "$d/.claude/settings.json"
  cp "$d/.claude/settings.json" "$TEST_TMP/settings.orig"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0 with an existing settings.json"
  assert_same_file "$TEST_TMP/settings.orig" "$d/.claude/settings.json" "settings.json byte-identical (criterion 8)"
  assert_true "settings.json not recorded created (D11)" eval '! has_record "$d" created .claude/settings.json'
  assert_not_contains "$OUT" "entry .claude/settings.json $rule" "the rule already there is not printed (D11)"
  assert_true "the rule already there is not recorded (D11)" eval '! has_record "$d" entry .claude/settings.json "$rule"'
  assert_line "$OUT" "entry .claude/settings.json $other" "a missing rule is printed as an entry line (A1)"
  assert_true "a missing rule is recorded as an entry (criterion 8)" has_record "$d" entry .claude/settings.json "$other"
  printed="$(grep -c '^entry \.claude/settings\.json ' <<<"$OUT" || true)"
  assert_true "one entry line printed per recorded entry" test "$printed" = "$(entry_count "$d")"
}

case_v3_gemini_handwritten() {
  # criterion 10: a hand-written GEMINI.md gets a gemini block, its own
  # content unchanged; dropping gemini from TOOLS removes the block and its
  # record, leaving the file byte for byte as it was (A6)
  local d; d="$(tools_install claude,gemini)"
  printf '# my gemini notes\nBe brief.\n' > "$d/GEMINI.md"
  cp "$d/GEMINI.md" "$TEST_TMP/gemini.orig"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0 with a hand-written GEMINI.md"
  assert_true "GEMINI.md holds one gemini block" test "$(block_count "$d/GEMINI.md" gemini)" = 1
  assert_true "GEMINI.md's own content kept first" file_starts_with "$d/GEMINI.md" "$TEST_TMP/gemini.orig"
  assert_true "nothing outside the block changed" test "$(outside_blocks "$d/GEMINI.md")" = "$(cat "$TEST_TMP/gemini.orig")"
  assert_true "the gemini block recorded" has_record "$d" block GEMINI.md gemini
  assert_true "GEMINI.md not recorded created (D11)" eval '! has_record "$d" created GEMINI.md'
  assert_line "$OUT" "block GEMINI.md gemini" "A1: block GEMINI.md gemini"
  set_config "$d/cortex/config" TOOLS claude
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0 after dropping gemini"
  assert_true "the gemini block is gone" test "$(block_count "$d/GEMINI.md" gemini)" = 0
  assert_true "its record is gone" eval '! has_record "$d" block GEMINI.md gemini'
  assert_same_file "$TEST_TMP/gemini.orig" "$d/GEMINI.md" "GEMINI.md byte for byte as written by hand (A6)"
  assert_line "$OUT" "removed block GEMINI.md gemini" "A1: removed block GEMINI.md gemini"
}

# ---- Amendment 3 (2026-10-09): F1 formatter-stable blocks, F2 .prettierignore,
# F4 TEST_GLOBS notes --------------------------------------------------------------

case_F1_blocks_framed() {
  # F1: every block adapt.sh writes (CODEOWNERS excepted) has one blank line
  # after its begin marker and one before its end marker
  local d; d="$(tools_install claude,copilot,gemini)"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0"
  printf '<!-- cortex:begin claude -->\n\n@AGENTS.md\n\n<!-- cortex:end claude -->\n' > "$TEST_TMP/claude.expected"
  assert_same_file "$TEST_TMP/claude.expected" "$d/CLAUDE.md" "a created CLAUDE.md is the framed claude block (F1)"
  assert_true "the gemini block is framed (F1)" block_framed "$d/GEMINI.md" gemini
  assert_true "the copilot block is framed (F1)" block_framed "$d/.github/copilot-instructions.md" copilot
  # F1: the framing is not part of the block's sha (A7)
  assert_true "the claude block's sha is git hash-object of '@AGENTS.md', framing excluded (F1)" \
    test "$(footprint_records "$d" | awk -F'\t' '$1 == "block" && $2 == "CLAUDE.md" { print $4 }')" = \
      "$(printf '@AGENTS.md\n' | git hash-object --no-filters --stdin)"
}

# blank_variant D TEXT LABEL : set CLAUDE.md's claude block to TEXT (differing
# from what adapt.sh writes only in blank lines); adapt.sh leaves it as is,
# printing unchanged, and check.sh (C13 included) passes (F1)
blank_variant() {
  local d="$1" text="$2" what="$3"
  set_block "$d/CLAUDE.md" claude "$text"
  if [ "$(block_body "$d/CLAUDE.md" claude | grep -v '^$' || true)" != "@AGENTS.md" ]; then
    fail "fixture ($what): the block's non-blank content is not @AGENTS.md"; return 0
  fi
  cp "$d/CLAUDE.md" "$TEST_TMP/claude.variant"
  adapt "$d"
  assert_exit 0 "$CODE" "$what: adapt exits 0"
  assert_line "$OUT" "unchanged CLAUDE.md" "$what: adapt prints unchanged CLAUDE.md (F1)"
  assert_not_contains "$OUT" "overwrote edited block CLAUDE.md" "$what: not an edited block (F1)"
  assert_same_file "$TEST_TMP/claude.variant" "$d/CLAUDE.md" "$what: CLAUDE.md left as is (F1)"
  run bash -c 'cd "$1" && ./cortex/bin/check.sh' _ "$d"
  assert_exit 0 "$CODE" "$what: check passes (F1)"
  assert_not_contains "$OUT" "[C13]" "$what: C13 accepts the block (F1)"
}

case_F1_blank_lines_not_edited() {
  # F1: a block differing from cortex's only in blank lines is not edited
  local d; d="$(adapted_install)" || return 0
  blank_variant "$d" $'\n\n@AGENTS.md\n\n' "extra blank lines (a formatter's)"
  blank_variant "$d" "@AGENTS.md" "no blank lines"
}

case_F2_prettierignore_entry() {
  # F2: a root .prettierignore without the line: "merge this line into
  # .prettierignore:", then the entry line (A1), recorded; the file untouched
  local d; d="$(tools_install claude)"
  printf 'node_modules/\ndist/\n' > "$d/.prettierignore"
  cp "$d/.prettierignore" "$TEST_TMP/pi.orig"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0 with a .prettierignore"
  assert_line "$OUT" "merge this line into .prettierignore:" "the merge request is printed (F2)"
  assert_line "$OUT" "entry .prettierignore cortex/" "the line is printed as an entry line (F2, A1)"
  assert_true "the request comes right before its entry line (F2)" \
    grep -qxF "entry .prettierignore cortex/" <<<"$(grep -A1 -xF "merge this line into .prettierignore:" <<<"$OUT" || true)"
  assert_true "the entry is recorded: entry<TAB>.prettierignore<TAB>cortex/ (F2)" has_record "$d" entry .prettierignore "cortex/"
  assert_true "one entry recorded for .prettierignore (F2)" test "$(entry_count "$d" .prettierignore)" = 1
  assert_same_file "$TEST_TMP/pi.orig" "$d/.prettierignore" ".prettierignore never edited (F2)"
  assert_true ".prettierignore not recorded created (D11)" eval '! has_record "$d" created .prettierignore'
  # merged by hand: no request on the next run, the record stays for removal
  append "$d/.prettierignore" "cortex/"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0 after the merge"
  assert_not_contains "$OUT" "merge this line into .prettierignore" "no request once merged (F2)"
  assert_true "the entry stays recorded once merged (F2)" has_record "$d" entry .prettierignore "cortex/"
}

case_F2_prettierignore_has_line() {
  # F2, D11: the line already there is neither printed nor recorded
  local d; d="$(tools_install claude)"
  printf 'node_modules/\ncortex/\n' > "$d/.prettierignore"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0"
  assert_not_contains "$OUT" ".prettierignore" "nothing printed for a .prettierignore that has the line (F2)"
  assert_true "nothing recorded (F2)" test "$(entry_count "$d" .prettierignore)" = 0
}

case_F2_no_prettierignore() {
  # F2: without a root .prettierignore nothing is printed, recorded or created
  local d; d="$(tools_install claude)"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0"
  assert_not_contains "$OUT" ".prettierignore" "nothing printed without a .prettierignore (F2)"
  assert_true "nothing recorded (F2)" test "$(entry_count "$d" .prettierignore)" = 0
  assert_file_absent "$d/.prettierignore" "no .prettierignore created (F2)"
}

case_F4_test_globs_note() {
  # F4: one note per TEST_GLOBS glob that matches no tracked file (pathspecs
  # anchor at the root unless they start with *); none for a matching glob
  local d; d="$(tools_install claude)"
  mkdir -p "$d/sub"
  printf 'echo a\n' > "$d/sub/a.test.sh"
  set_config "$d/cortex/config" TEST_GLOBS '*.test.sh a.test.sh tests/**'
  commit_all "$d" "tracked: sub/a.test.sh"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0 with unmatched globs (a note, not a check)"
  assert_line "$OUT$ERR" "note: TEST_GLOBS a.test.sh matches no tracked file" "an anchored glob matching nothing is noted (F4)"
  assert_line "$OUT$ERR" "note: TEST_GLOBS tests/** matches no tracked file" "a directory glob matching nothing is noted (F4)"
  assert_not_contains "$OUT$ERR" "note: TEST_GLOBS *.test.sh " "a glob that matches is not noted (F4)"
  assert_true "one note per unmatched glob (F4)" \
    test "$(grep -c '^note: TEST_GLOBS ' <<<"$OUT$ERR" || true)" = 2
}

case_F4_test_globs_all_match() {
  # F4: every glob matches: no note
  local d; d="$(tools_install claude)"
  mkdir -p "$d/tests"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  set_config "$d/cortex/config" TEST_GLOBS '*.test.sh tests/**'
  commit_all "$d" "tracked: tests/a.test.sh"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0"
  assert_not_contains "$OUT$ERR" "note: TEST_GLOBS" "no note when every glob matches (F4)"
}

# ---- spec 3.1.0 G1 (criterion 1): one rule for "already ignores cortex" -------------
#
# docs/specs/2026-10-09-v3.1-pilot-followups.md, G1: a .prettierignore line
# ignores cortex when, without a carriage return and surrounding spaces and
# tabs, it is exactly cortex, /cortex, cortex/ or /cortex/.

# g1_variants FORM -> one .prettierignore per line of output, \n-escaped for
# printf %b: FORM plain, with CRLF line endings, and with spaces and tabs
# around it
g1_variants() {
  printf '%s\n' 'node_modules/\n'"$1"'\n' 'node_modules/\r\n'"$1"'\r\n' \
    'node_modules/\n  '"$1"' \t\n' 'node_modules/\n\t'"$1"'\n'
}

g1_already_ignored() { # FORM
  local d v n=0
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    n=$((n + 1))
    d="$(tools_install claude)"
    printf '%b' "$v" > "$d/.prettierignore"
    adapt "$d"
    assert_exit 0 "$CODE" "'$1' variant $n: adapt exits 0"
    assert_not_contains "$OUT" "merge this line into .prettierignore" "'$1' variant $n: no merge line"
    assert_not_contains "$OUT" ".prettierignore" "'$1' variant $n: nothing printed for .prettierignore"
    assert_true "'$1' variant $n: nothing recorded" test "$(entry_count "$d" .prettierignore)" = 0
  done <<<"$(g1_variants "$1")"
  assert_true "fixture: four variants of '$1' tried" test "$n" = 4
}

case_G1_form_cortex() { g1_already_ignored cortex; }
case_G1_form_slash_cortex() { g1_already_ignored /cortex; }
case_G1_form_cortex_slash() { g1_already_ignored cortex/; }
case_G1_form_slash_cortex_slash() { g1_already_ignored /cortex/; }

case_G1_other_path_asks() {
  # a line naming a path under some other directory's cortex/ doesn't count
  local d; d="$(tools_install claude)"
  printf 'node_modules/\nsrc/cortex/x\n' > "$d/.prettierignore"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0"
  assert_line "$OUT" "merge this line into .prettierignore:" "src/cortex/x: the merge line is printed"
  assert_line "$OUT" "entry .prettierignore cortex/" "src/cortex/x: the entry line is printed"
  assert_true "src/cortex/x: the entry is recorded" has_record "$d" entry .prettierignore "cortex/"
}

run_case "missing cortex/config -> exit 2" case_missing_config
run_case "AC11 TOOLS placeholder warns, writes nothing" case_tools_placeholder
run_case "AC11 TOOLS empty warns, writes nothing" case_tools_empty
run_case "AC11 TOOLS key absent warns, writes nothing" case_tools_absent
run_case "template ships Claude adapter sources" case_template_has_adapters
run_case "all tools write documented files (AC7)" case_all_tools
run_case "second run idempotent (AC7)" case_second_run_idempotent
run_case "hand-written CLAUDE.md gets the claude block (AC7, D4/D11)" case_handwritten_claude_md_gets_block
run_case "edited claude block is regenerated" case_edited_block_regenerated
run_case "hand-written cortex-named adapter file refused (D11)" case_handwritten_adapter_refused
run_case "existing settings.json untouched (AC7)" case_existing_settings_untouched
run_case "claude only" case_claude_only
run_case "unknown tool warns" case_unknown_tool
run_case "repo-root argument" case_root_argument
run_case "check ok after install + adapt (AC8)" case_check_ok_after_adapt
run_case "AC20 settings.json unchanged on re-run" case_settings_unchanged_on_rerun
run_case "AC20 removed tool: cursor rule removed" case_stale_cursor
run_case "AC20 every removed tool's files removed" case_stale_all_known
run_case "stale ignores hand-written files" case_stale_ignores_handwritten
run_case "AC32 TOOLS with spaces around =" case_AC32_spaced
run_case "AC32 TOOLS after a commented-out line" case_AC32_comment
run_case "AC32 TOOLS after a line without =" case_AC32_no_equals
run_case "AC32 TOOLS twice: the first wins" case_AC32_twice
run_case "AC33 TOOLS=claude , cursor writes both" case_AC33_spaced_list
run_case "AC34 a stub _config.sh changes what adapt.sh reads" case_AC34_stub_parser
run_case "criterion 8: settings.json created when absent, recorded" case_v3_settings_created
run_case "criterion 8: existing settings.json gets entries, never edited" case_v3_settings_entries
run_case "criterion 10: hand-written GEMINI.md gets a block, then loses it" case_v3_gemini_handwritten
run_case "F1: blocks written with one blank line inside each marker" case_F1_blocks_framed
run_case "F1: a block differing only in blank lines is not edited" case_F1_blank_lines_not_edited
run_case "F2: .prettierignore without the line gets an entry" case_F2_prettierignore_entry
run_case "F2: .prettierignore with the line: nothing printed or recorded" case_F2_prettierignore_has_line
run_case "F2: no .prettierignore: nothing printed or recorded" case_F2_no_prettierignore
run_case "F4: a note per TEST_GLOBS glob matching no tracked file" case_F4_test_globs_note
run_case "F4: no TEST_GLOBS note when every glob matches" case_F4_test_globs_all_match
run_case "G1 criterion 1: .prettierignore with cortex (four variants)" case_G1_form_cortex
run_case "G1 criterion 1: .prettierignore with /cortex (four variants)" case_G1_form_slash_cortex
run_case "G1 criterion 1: .prettierignore with cortex/ (four variants)" case_G1_form_cortex_slash
run_case "G1 criterion 1: .prettierignore with /cortex/ (four variants)" case_G1_form_slash_cortex_slash
run_case "G1 criterion 1: .prettierignore with src/cortex/x asks" case_G1_other_path_asks
summary
