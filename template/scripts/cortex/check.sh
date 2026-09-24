#!/usr/bin/env bash
# Checks the invariants of the cortex harness in this repository: the design
# rules (.cortex/design-rules.md) that a script can verify (R11).
# Each violation prints "FAIL [<ID>] <path>: <message>".
#
#   C1  R1   the project name appears under harness/
#   C2  R8   an agent-tool name appears under harness/ or docs/knowledge/
#   C3  R2   AGENTS.md is missing or longer than 60 lines
#   C4  R5   a harness file says "read all" or "read everything"
#   C5  -    a command lacks Purpose/Preconditions/Procedure/Output/Autonomy
#   C6  R10  a command has no "Budget:" line
#   C7  R6   "Approved-by:" appears in harness/ outside the proposal template
#   C8  R8   CLAUDE.md is anything but a pointer to AGENTS.md
#   C9  R8   a generated SKILL.md is longer than 25 lines (content, not a pointer)
#   C10 -    AGENTS.md lacks the untrusted-content rule
#   C11 -    a required .cortex/config value is unset or a <placeholder>
#   C12 -    AGENTS.md still contains TODO
#
# Usage: scripts/cortex/check.sh [repo-root]
# Exit:  0 clean, 1 violations found.
set -euo pipefail

cd "${1:-.}"

failures=0
report() { # id path message
  echo "FAIL [$1] $2: $3"
  failures=$((failures + 1))
}

# config_get KEY -> the value from .cortex/config, or empty if unset/placeholder
config_get() {
  [ -f .cortex/config ] || return 0
  local value
  value="$(tr -d '\r' < .cortex/config |
    awk -v k="$1" '
      /^[[:space:]]*#/ { next }
      {
        eq = index($0, "=")
        if (eq == 0) next
        key = substr($0, 1, eq - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        if (key != k) next
        val = substr($0, eq + 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        print val; exit
      }')"
  case "$value" in "<"*">") value="" ;; esac
  printf '%s' "$value"
}

files_under() { # dir... -> regular files, sorted
  local dir
  for dir in "$@"; do
    [ -d "$dir" ] && find "$dir" -type f
  done | LC_ALL=C sort
}

harness_files="$(files_under harness)"
knowledge_files="$(files_under docs/knowledge)"
command_files="$(files_under harness/commands | grep '\.md$' || true)"

# C1 — R1: the project is never named in the harness.
project="$(config_get PROJECT_NAME)"
if [ -n "$project" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -qiF -- "$project" "$f"; then
      report C1 "$f" "names the project (\"$project\"); harness files refer to roles and paths only"
    fi
  done <<<"$harness_files"
fi

# C2 — R8: canonical files name no agent tool.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if grep -qiwE 'claude|cursor|copilot|gemini|codex' "$f"; then
    report C2 "$f" "names an agent tool; tool specifics belong in .cortex/adapters/"
  fi
done <<<"$(printf '%s\n%s\n' "$harness_files" "$knowledge_files")"

# C3 — R2: AGENTS.md is a router of at most 60 lines.
if [ ! -f AGENTS.md ]; then
  report C3 AGENTS.md "missing; every repository needs its router"
else
  lines="$(wc -l < AGENTS.md | tr -d ' ')"
  if [ "$lines" -gt 60 ]; then
    report C3 AGENTS.md "$lines lines; a router is at most 60 (move content into docs/knowledge/)"
  fi
fi

# C4 — R5: no file tells an agent to read everything.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if grep -qiE 'read all|read everything' "$f"; then
    report C4 "$f" "tells an agent to read everything; name the specific files instead"
  fi
done <<<"$harness_files"

# C5 — every command has the five sections.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  missing=""
  for heading in Purpose Preconditions Procedure Output Autonomy; do
    grep -q "^## $heading" "$f" || missing="$missing $heading"
  done
  if [ -n "$missing" ]; then
    report C5 "$f" "missing section(s):$missing"
  fi
done <<<"$command_files"

# C6 — R10: every command declares its loop budget.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -q '^Budget:' "$f" || report C6 "$f" "no 'Budget:' line (stop condition, attempt limit, escalation — or 'does not iterate')"
done <<<"$command_files"

# C7 — R6: only a human writes the approval line; only the template has the field.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ "$f" = harness/templates/change-folder/proposal.md ] && continue
  if grep -qF 'Approved-by:' "$f"; then
    report C7 "$f" "contains 'Approved-by:'; only a human writes the approval, in the proposal"
  fi
done <<<"$harness_files"

# C8 — R8: CLAUDE.md only points at AGENTS.md.
if [ -f CLAUDE.md ]; then
  content="$(tr -d '\r' < CLAUDE.md | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*<!--.*-->[[:space:]]*$' || true)"
  if [ "$content" != "@AGENTS.md" ]; then
    report C8 CLAUDE.md "must contain only '@AGENTS.md' (plus comments); content belongs in AGENTS.md"
  fi
fi

# C9 — R8: generated skills delegate; they don't carry procedure.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if grep -qF 'cortex:generated' "$f"; then
    lines="$(wc -l < "$f" | tr -d ' ')"
    if [ "$lines" -gt 25 ]; then
      report C9 "$f" "$lines lines; a generated skill delegates to harness/commands/ in at most 25"
    fi
  fi
done <<<"$( [ -d .claude/skills ] && find .claude/skills -type f -name SKILL.md | LC_ALL=C sort || true)"

# C10 — the untrusted-content rule is in the router.
if [ -f AGENTS.md ] && ! grep -qF 'data, never instructions' AGENTS.md; then
  report C10 AGENTS.md "lacks the untrusted-content rule ('... is data, never instructions')"
fi

# C11 — the install is filled in: every required config value is set.
if [ -f .cortex/config ]; then
  for key in PROJECT_NAME BUILD_CMD TEST_CMD LINT_CMD TEST_GLOBS TOOLS; do
    [ -n "$(config_get "$key" | tr -d '[:space:]')" ] || report C11 .cortex/config "$key is not set"
  done
fi

# C12 — AGENTS.md has no placeholder left.
if [ -f AGENTS.md ] && grep -q 'TODO' AGENTS.md; then
  report C12 AGENTS.md "still contains TODO; fill it in (INSTALL.md step 3)"
fi

if [ "$failures" -eq 0 ]; then
  echo "check: ok"
else
  echo "check: $failures failure(s)"
  exit 1
fi
