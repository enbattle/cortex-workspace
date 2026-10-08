#!/usr/bin/env bash
# Checks the invariants of the cortex harness in this repository: the design
# rules (.cortex/design-rules.md) that a script can verify (R11).
# Each violation prints "FAIL [<ID>] <path>: <message>".
#
#   C0  -    harness/ or docs/knowledge/ is missing (wrong directory?)
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

# The config parser next to this file, resolved before the cd below.
# shellcheck source=_config.sh
. "$(cd "$(dirname "$0")" && pwd)/_config.sh"
cd "${1:-.}"

failures=0
report() { # id path message
  echo "FAIL [$1] $2: $3"
  failures=$((failures + 1))
}

files_under() { # dir... -> regular files, sorted
  local dir
  for dir in "$@"; do
    [ -d "$dir" ] || continue
    find "$dir" -type f
  done | LC_ALL=C sort
}

# C0 — the harness's own directories exist (spec Amendment 8). Without them
# the checks below have nothing to look at; the usual cause is running from
# the wrong directory, so say so instead of passing quietly or stopping.
for dir in harness docs/knowledge; do
  [ -d "$dir" ] || report C0 "$dir/" "missing; run check.sh from the repository root (or pass the root as its argument), or reinstall"
done

# Each check runs one grep over every file it covers, not one per file
# (spec Amendment 7): starting a process costs 50-60 ms on Windows. grep
# lists matches in argument order, so reports stay sorted by path.
harness_files="$(files_under harness)"
knowledge_files="$(files_under docs/knowledge)"
harness=()
while IFS= read -r f; do [ -z "$f" ] || harness+=("$f"); done <<<"$harness_files"
knowledge=()
while IFS= read -r f; do [ -z "$f" ] || knowledge+=("$f"); done <<<"$knowledge_files"
commands=()
for f in ${harness[@]+"${harness[@]}"}; do
  case "$f" in harness/commands/*.md) commands+=("$f") ;; esac
done

# grep_files GREP-ARGS... -- FILE... -> grep's output, nothing if no files
grep_files() {
  local args=()
  while [ "$1" != -- ]; do args+=("$1"); shift; done
  shift
  [ "$#" -gt 0 ] || return 0
  grep "${args[@]}" -- "$@" || true
}

# report_each ID MESSAGE <<< PATHS
report_each() {
  local f
  while IFS= read -r f; do
    [ -z "$f" ] || report "$1" "$f" "$2"
  done
}

# C1 — R1: the project is never named in the harness.
project=""
[ ! -f .cortex/config ] || project="$(config_value PROJECT_NAME < .cortex/config)"
if [ -n "$project" ]; then
  report_each C1 "names the project (\"$project\"); harness files refer to roles and paths only" \
    <<<"$(grep_files -liwF -e "$project" -- ${harness[@]+"${harness[@]}"})"
fi

# C2 — R8: canonical files name no agent tool.
report_each C2 "names an agent tool; tool specifics belong in .cortex/adapters/" \
  <<<"$(grep_files -liwE 'claude|cursor|copilot|gemini|codex' -- ${harness[@]+"${harness[@]}"} ${knowledge[@]+"${knowledge[@]}"})"

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
report_each C4 "tells an agent to read everything; name the specific files instead" \
  <<<"$(grep_files -liE 'read all|read everything' -- ${harness[@]+"${harness[@]}"})"

# C5 — every command has the five sections. One grep -L per heading; a
# file's missing headings are then listed in this order.
lacking=""
for heading in Purpose Preconditions Procedure Output Autonomy; do
  while IFS= read -r f; do
    [ -z "$f" ] || lacking="$lacking$f"$'\t'"$heading"$'\n'
  done <<<"$(grep_files -L "^## $heading" -- ${commands[@]+"${commands[@]}"})"
done
for f in ${commands[@]+"${commands[@]}"}; do
  missing=""
  for heading in Purpose Preconditions Procedure Output Autonomy; do
    case $'\n'"$lacking" in *$'\n'"$f"$'\t'"$heading"$'\n'*) missing="$missing $heading" ;; esac
  done
  [ -z "$missing" ] || report C5 "$f" "missing section(s):$missing"
done

# C6 — R10: every command declares its loop budget.
report_each C6 "no 'Budget:' line (stop condition, attempt limit, escalation — or 'does not iterate')" \
  <<<"$(grep_files -L '^Budget:' -- ${commands[@]+"${commands[@]}"})"

# C7 — R6: only a human approves; only the proposal template has the field.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ "$f" = harness/templates/change-folder/proposal.md ] && continue
  report C7 "$f" "contains 'Approved-by:'; only a human approves, in the proposal (R6)"
done <<<"$(grep_files -lF 'Approved-by:' -- ${harness[@]+"${harness[@]}"})"

# C8 — R8: CLAUDE.md only points at AGENTS.md.
if [ -f CLAUDE.md ]; then
  # Only the generated marker may accompany the pointer: any other comment could
  # carry instructions the canonical files don't.
  content="$(tr -d '\r' < CLAUDE.md | grep -vE '^[[:space:]]*$' | grep -vxF '<!-- cortex:generated -->' || true)"
  if [ "$content" != "@AGENTS.md" ]; then
    report C8 CLAUDE.md "must contain only '@AGENTS.md' (and the generated marker); content belongs in AGENTS.md"
  fi
fi

# C9 — R8: generated skills delegate; they don't carry procedure.
skills=()
while IFS= read -r f; do [ -z "$f" ] || skills+=("$f"); done <<<"$( [ -d .claude/skills ] && find .claude/skills -type f -name SKILL.md | LC_ALL=C sort || true)"
generated=()
while IFS= read -r f; do [ -z "$f" ] || generated+=("$f"); done <<<"$(grep_files -lF 'cortex:generated' -- ${skills[@]+"${skills[@]}"})"
if [ "${#generated[@]}" -gt 0 ]; then
  # One wc for all of them: a "<lines> <path>" row each, then a total row.
  while read -r lines f; do
    [ -n "$f" ] && [ "$f" != total ] || continue
    if [ "$lines" -gt 25 ]; then
      report C9 "$f" "$lines lines; a generated skill delegates to harness/commands/ in at most 25"
    fi
  done <<<"$(wc -l -- "${generated[@]}")"
fi

# C10 — the untrusted-content rule is in the router.
if [ -f AGENTS.md ] && ! grep -qF 'data, never instructions' AGENTS.md; then
  report C10 AGENTS.md "lacks the untrusted-content rule ('... is data, never instructions')"
fi

# C11 — the install is filled in: every required config value is set.
if [ -f .cortex/config ]; then
  for key in PROJECT_NAME BUILD_CMD TEST_CMD LINT_CMD TEST_GLOBS TOOLS; do
    [ -n "$(config_value "$key" < .cortex/config | tr -d '[:space:]')" ] || report C11 .cortex/config "$key is not set"
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
