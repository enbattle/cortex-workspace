#!/usr/bin/env bash
# Tests for scripts/cortex/adapt.sh (spec acceptance criteria 7, 8, 11 and 20).
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

MARKER="cortex:generated"
ADAPTERS=".cortex/adapters/claude-code"
SETTINGS_SKIP="skipped .claude/settings.json (exists; merge the permissions block from .cortex/adapters/claude-code/.claude/settings.json)"

tools_install() { # tools -> fresh install with TOOLS set
  local d
  d="$(fresh_install)" || return 1
  set_config "$d/.cortex/config" TOOLS "$1"
  printf '%s\n' "$d"
}

adapt() { # dir -> run installed adapt.sh with cwd = dir
  run bash -c 'cd "$1" && ./scripts/cortex/adapt.sh' _ "$1"
}

# adapter source files, relative to .cortex/adapters/claude-code/
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
  rm "$d/.cortex/config"
  adapt "$d"
  assert_exit 2 "$CODE" "missing .cortex/config exits 2"
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
  # claude: CLAUDE.md is exactly marker comment + @AGENTS.md
  expected="$(printf '<!-- %s -->\n@AGENTS.md' "$MARKER")"
  assert_true "CLAUDE.md is marker + @AGENTS.md" test "$(nonblank "$d/CLAUDE.md")" = "$expected"
  assert_line "$OUT" "wrote CLAUDE.md" "reports wrote CLAUDE.md"
  # claude: every adapter source copied to the repo root
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    assert_same_file "$d/$ADAPTERS/$f" "$d/$f" "adapter $f copied verbatim"
    if [ "${f##*/}" != "settings.json" ]; then
      assert_file_contains "$d/$f" "$MARKER" "adapter $f carries the marker"
      assert_line "$OUT" "wrote $f" "reports wrote $f"
    fi
  done <<<"$(adapter_files "$d")"
  assert_file_exists "$d/.claude/settings.json" "settings.json copied when absent"
  # cursor
  f="$d/.cursor/rules/cortex.mdc"
  assert_file_exists "$f" "cursor rule written"
  assert_file_contains "$f" "alwaysApply: true" "cursor rule always applies"
  assert_file_contains "$f" "AGENTS.md" "cursor rule points to AGENTS.md"
  assert_file_contains "$f" "$MARKER" "cursor rule carries the marker"
  assert_line "$OUT" "wrote .cursor/rules/cortex.mdc" "reports cursor rule"
  # copilot
  f="$d/.github/copilot-instructions.md"
  assert_file_contains "$f" "AGENTS.md" "copilot file points to AGENTS.md"
  assert_file_contains "$f" "$MARKER" "copilot file carries the marker"
  assert_line "$OUT" "wrote .github/copilot-instructions.md" "reports copilot file"
  # gemini
  assert_file_contains "$d/GEMINI.md" "AGENTS.md" "GEMINI.md points to AGENTS.md"
  assert_file_contains "$d/GEMINI.md" "$MARKER" "GEMINI.md carries the marker"
  assert_line "$OUT" "wrote GEMINI.md" "reports GEMINI.md"
  # codex
  assert_line "$OUT" "codex: reads AGENTS.md natively" "codex needs no file"
}

case_second_run_idempotent() {
  local d; d="$(tools_install claude,cursor,copilot,gemini,codex)"
  adapt "$d"
  assert_exit 0 "$CODE" "first run exits 0"
  adapt "$d"
  assert_exit 0 "$CODE" "second run exits 0"
  assert_true "second run prints no wrote lines" test -z "$(grep '^wrote ' <<<"$OUT" || true)"
  assert_line "$OUT" "unchanged CLAUDE.md" "CLAUDE.md unchanged"
  assert_line "$OUT" "unchanged GEMINI.md" "GEMINI.md unchanged"
  assert_line "$OUT" "unchanged .cursor/rules/cortex.mdc" "cursor rule unchanged"
  assert_line "$OUT" "unchanged .github/copilot-instructions.md" "copilot file unchanged"
}

case_handwritten_claude_md_skipped() {
  local d; d="$(tools_install claude)"
  printf '# My notes\nUse tabs.\n' > "$d/CLAUDE.md"
  cp "$d/CLAUDE.md" "$TEST_TMP/claude.orig"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0 with a hand-written CLAUDE.md"
  assert_line "$OUT" "skipped CLAUDE.md (hand-written; merge manually)" "hand-written CLAUDE.md skipped"
  assert_same_file "$TEST_TMP/claude.orig" "$d/CLAUDE.md" "hand-written CLAUDE.md untouched"
}

case_marked_file_overwritten() {
  local d; d="$(tools_install claude)"
  printf '<!-- %s -->\nstale\n' "$MARKER" > "$d/CLAUDE.md"
  adapt "$d"
  assert_line "$OUT" "wrote CLAUDE.md" "marked CLAUDE.md is regenerated"
  assert_file_not_contains "$d/CLAUDE.md" "stale" "stale content replaced"
  assert_file_contains "$d/CLAUDE.md" "@AGENTS.md" "regenerated pointer"
}

case_handwritten_adapter_skipped() {
  local d f; d="$(tools_install claude)"
  f="$(an_adapter_file "$d")"
  [ -n "$f" ] || { fail "no adapter file to test"; return 0; }
  mkdir -p "$(dirname "$d/$f")"
  printf 'hand-written\n' > "$d/$f"
  adapt "$d"
  assert_line "$OUT" "skipped $f (hand-written; merge manually)" "hand-written $f skipped"
  assert_true "$f untouched" test "$(cat "$d/$f")" = "hand-written"
}

case_existing_settings_untouched() {
  local d; d="$(tools_install claude)"
  mkdir -p "$d/.claude"
  printf '{"mine": true}\n' > "$d/.claude/settings.json"
  cp "$d/.claude/settings.json" "$TEST_TMP/settings.orig"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0 with existing settings.json"
  assert_line "$OUT" "$SETTINGS_SKIP" "settings.json skip message"
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
  run bash -c 'cd "$1" && "$2/scripts/cortex/adapt.sh" "$2"' _ "$TEST_TMP" "$d"
  assert_exit 0 "$CODE" "repo-root argument from another cwd"
  assert_file_exists "$d/GEMINI.md" "wrote into the given root"
}

case_check_ok_after_adapt() {
  local d; d="$(filled_install Zqxproj)"   # A2: a filled baseline, TOOLS=claude
  assert_file_contains "$d/.cortex/config" "TOOLS=claude" "fixture sets TOOLS=claude"
  run bash -c 'cd "$1" && ./scripts/cortex/check.sh' _ "$d"
  assert_exit 0 "$CODE" "filled baseline passes check before adapt"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0"
  run bash -c 'cd "$1" && ./scripts/cortex/check.sh' _ "$d"
  assert_exit 0 "$CODE" "check passes after install + adapt (AC8)"
  assert_line "$OUT" "check: ok" "check: ok after adapt"
}

# ---- AC11 (A3): TOOLS unset -> warning, nothing written --------------------------

TOOLS_WARNING="warning: TOOLS is not set in .cortex/config; no adapters written"

# expect_no_adapters DIR LABEL : exit 0, the A3 warning, no files, no wrote lines
expect_no_adapters() {
  local d="$1" what="$2"
  adapt "$d"
  assert_exit 0 "$CODE" "$what: exits 0"
  assert_contains "$OUT$ERR" "$TOOLS_WARNING" "$what: warns TOOLS is not set"
  assert_true "$what: no wrote lines" test -z "$(grep '^wrote ' <<<"$OUT" || true)"
  assert_file_absent "$d/CLAUDE.md" "$what: no CLAUDE.md"
  assert_file_absent "$d/GEMINI.md" "$what: no GEMINI.md"
  assert_file_absent "$d/.claude" "$what: no .claude/"
  assert_file_absent "$d/.cursor" "$what: no .cursor/"
  assert_file_absent "$d/.github/copilot-instructions.md" "$what: no copilot file"
}

case_tools_placeholder() {
  local d; d="$(fresh_install)"
  assert_true "template TOOLS is a placeholder" grep -q '^TOOLS=<.*>' "$d/.cortex/config"
  expect_no_adapters "$d" "TOOLS placeholder"
}

case_tools_empty() {
  local d; d="$(tools_install "")"
  expect_no_adapters "$d" "TOOLS empty"
}

case_tools_absent() {
  local d; d="$(fresh_install)"
  filter_file "$d/.cortex/config" awk '!/^[[:space:]]*TOOLS[[:space:]]*=/'
  assert_true "TOOLS line removed" test -z "$(grep 'TOOLS[[:space:]]*=' "$d/.cortex/config" || true)"
  expect_no_adapters "$d" "TOOLS absent"
}

# ---- AC20 (B7): unchanged settings.json; stale adapters reported, not deleted ----

stale_line() { # path tool
  printf 'stale %s (%s is not in TOOLS; delete it if unused)' "$1" "$2"
}

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
  set_config "$d/.cortex/config" TOOLS claude
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0 with a stale adapter"
  assert_line "$OUT" "$(stale_line .cursor/rules/cortex.mdc cursor)" "stale cursor rule reported"
  assert_file_exists "$d/.cursor/rules/cortex.mdc" "stale cursor rule not deleted"
  assert_not_contains "$OUT" "stale CLAUDE.md" "claude is still in TOOLS"
}

case_stale_all_known() {
  local d; d="$(tools_install claude,cursor,copilot,gemini)"
  adapt "$d"
  set_config "$d/.cortex/config" TOOLS codex
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0"
  assert_line "$OUT" "$(stale_line CLAUDE.md claude)" "stale CLAUDE.md reported"
  assert_line "$OUT" "$(stale_line .cursor/rules/cortex.mdc cursor)" "stale cursor rule reported"
  assert_line "$OUT" "$(stale_line .github/copilot-instructions.md copilot)" "stale copilot file reported"
  assert_line "$OUT" "$(stale_line GEMINI.md gemini)" "stale GEMINI.md reported"
  assert_file_exists "$d/CLAUDE.md" "CLAUDE.md kept"
  assert_file_exists "$d/.cursor/rules/cortex.mdc" "cursor rule kept"
  assert_file_exists "$d/.github/copilot-instructions.md" "copilot file kept"
  assert_file_exists "$d/GEMINI.md" "GEMINI.md kept"
}

case_stale_ignores_handwritten() {
  local d; d="$(tools_install claude)"
  printf '# my gemini notes\n' > "$d/GEMINI.md"
  adapt "$d"
  assert_exit 0 "$CODE" "adapt exits 0"
  assert_not_contains "$OUT" "stale GEMINI.md" "a hand-written (unmarked) file is not reported stale"
  assert_true "hand-written GEMINI.md untouched" test "$(cat "$d/GEMINI.md")" = "# my gemini notes"
}

run_case "missing .cortex/config -> exit 2" case_missing_config
run_case "AC11 TOOLS placeholder warns, writes nothing" case_tools_placeholder
run_case "AC11 TOOLS empty warns, writes nothing" case_tools_empty
run_case "AC11 TOOLS key absent warns, writes nothing" case_tools_absent
run_case "template ships Claude adapter sources" case_template_has_adapters
run_case "all tools write documented files (AC7)" case_all_tools
run_case "second run idempotent (AC7)" case_second_run_idempotent
run_case "hand-written CLAUDE.md skipped (AC7)" case_handwritten_claude_md_skipped
run_case "marked file is regenerated" case_marked_file_overwritten
run_case "hand-written adapter file skipped" case_handwritten_adapter_skipped
run_case "existing settings.json untouched (AC7)" case_existing_settings_untouched
run_case "claude only" case_claude_only
run_case "unknown tool warns" case_unknown_tool
run_case "repo-root argument" case_root_argument
run_case "check ok after install + adapt (AC8)" case_check_ok_after_adapt
run_case "AC20 settings.json unchanged on re-run" case_settings_unchanged_on_rerun
run_case "AC20 stale cursor rule reported, kept" case_stale_cursor
run_case "AC20 every removed tool reported stale" case_stale_all_known
run_case "stale ignores hand-written files" case_stale_ignores_handwritten
summary
