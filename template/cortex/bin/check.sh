#!/usr/bin/env bash
# Checks the invariants of the cortex harness in this repository: the design
# rules (cortex/design-rules.md) that a script can verify (R11).
# Each violation prints "FAIL [<ID>] <path>: <message>".
#
#   C0  -    cortex/harness/ or cortex/knowledge/ is missing (wrong directory?)
#   C1  -    retired in 3.0.0 (spec D9): upgrades merge edits, so the harness
#            may name the project
#   C2  R8   an agent-tool name appears under cortex/harness/
#   C3  R2   cortex/AGENTS.md is missing or longer than 60 lines; the root
#            AGENTS.md's cortex block is missing, duplicated or over 15 lines
#   C4  R5   a harness file says "read all" or "read everything"
#   C5  -    a command lacks Purpose/Preconditions/Procedure/Output/Autonomy
#   C6  R10  a command has no "Budget:" line
#   C7  R6   "Approved-by:" appears in cortex/harness/ outside the proposal template
#   C8  R8   CLAUDE.md's cortex block is anything but a pointer to AGENTS.md
#   C9  R8   a generated SKILL.md is longer than 25 lines (content, not a pointer)
#   C10 -    the root AGENTS.md's cortex block lacks the untrusted-content rule
#   C11 -    a required cortex/config value is unset or a <placeholder>
#   C12 -    cortex/AGENTS.md or the root cortex block still contains TODO
#   C13 R15  cortex/footprint doesn't match the repository
#   C14 -    a merge-conflict marker is left under cortex/ or in a cortex block
#
# Usage: cortex/bin/check.sh [repo-root]
# Exit:  0 clean, 1 violations found.
set -euo pipefail

# The helpers next to this file, resolved before the cd below.
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_config.sh
. "$here/_config.sh"
# shellcheck source=_footprint.sh
. "$here/_footprint.sh"
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
for dir in cortex/harness cortex/knowledge; do
  [ -d "$dir" ] || report C0 "$dir/" "missing; run check.sh from the repository root (or pass the root as its argument), or reinstall"
done

# Each check runs one grep over every file it covers, not one per file
# (spec Amendment 7): starting a process costs 50-60 ms on Windows. grep
# lists matches in argument order, so reports stay sorted by path.
harness=()
while IFS= read -r f; do [ -z "$f" ] || harness+=("$f"); done <<<"$(files_under cortex/harness)"
commands=()
for f in ${harness[@]+"${harness[@]}"}; do
  case "$f" in cortex/harness/commands/*.md) commands+=("$f") ;; esac
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

# The root AGENTS.md's cortex block (D5), read once for C3, C10 and C12.
root_blocks=0
root_block=""
if [ -f AGENTS.md ]; then
  root_blocks="$(block_count AGENTS.md agents)"
  root_block="$(block_content AGENTS.md agents | tr -d '\r')"
fi

# C2 — R8: canonical files name no agent tool. cortex/knowledge/ is project
# content, free to name a tool (D9).
report_each C2 "names an agent tool; tool specifics belong in cortex/adapters/" \
  <<<"$(grep_files -liwE 'claude|cursor|copilot|gemini|codex' -- ${harness[@]+"${harness[@]}"})"

# C3 — R2: cortex/AGENTS.md is a router of at most 60 lines; the root block
# carries the always-on rules in at most 15, markers included.
if [ ! -f cortex/AGENTS.md ]; then
  report C3 cortex/AGENTS.md "missing; every install needs its router"
else
  lines="$(wc -l < cortex/AGENTS.md | tr -d ' ')"
  if [ "$lines" -gt 60 ]; then
    report C3 cortex/AGENTS.md "$lines lines; a router is at most 60 (move content into cortex/knowledge/)"
  fi
fi
if [ "$root_blocks" -eq 0 ]; then
  report C3 AGENTS.md "has no cortex agents block; reinstall to restore it (bin/install.sh)"
elif [ "$root_blocks" -gt 1 ]; then
  report C3 AGENTS.md "has $root_blocks cortex agents blocks; keep one"
else
  # Non-blank lines, so a formatter's blank lines can't fail it (F1).
  lines=$(( $(printf '%s\n' "$root_block" | grep -c '[^[:space:]]' || true) + 2 ))
  if [ "$lines" -gt 15 ]; then
    report C3 AGENTS.md "the cortex block is $lines lines; it carries the always-on rules in at most 15 (the rest belongs in cortex/AGENTS.md)"
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
  [ "$f" = cortex/harness/templates/change-folder/proposal.md ] && continue
  report C7 "$f" "contains 'Approved-by:'; only a human approves, in the proposal (R6)"
done <<<"$(grep_files -lF 'Approved-by:' -- ${harness[@]+"${harness[@]}"})"

# C8 — R8: CLAUDE.md's cortex block only points at AGENTS.md. Content
# outside the block is the project's (D4). Any comment in the block could
# carry instructions the canonical files don't.
if [ -f CLAUDE.md ] && [ "$(block_count CLAUDE.md claude)" -gt 0 ]; then
  content="$(block_content CLAUDE.md claude | tr -d '\r' | grep -vE '^[[:space:]]*$' || true)"
  if [ "$content" != "@AGENTS.md" ]; then
    report C8 CLAUDE.md "the cortex block must contain only '@AGENTS.md'; content belongs in AGENTS.md or cortex/"
  fi
fi

# C9 — R8: generated skills delegate; they don't carry procedure. Generated
# means under .claude/skills/cortex-*/ (A4).
generated=()
while IFS= read -r f; do [ -z "$f" ] || generated+=("$f"); done <<<"$(
  [ -d .claude/skills ] && find .claude/skills -type f -path '.claude/skills/cortex-*/SKILL.md' | LC_ALL=C sort || true)"
if [ "${#generated[@]}" -gt 0 ]; then
  # One wc for all of them: a "<lines> <path>" row each, then a total row.
  while read -r lines f; do
    [ -n "$f" ] && [ "$f" != total ] || continue
    if [ "$lines" -gt 25 ]; then
      report C9 "$f" "$lines lines; a generated skill delegates to cortex/harness/commands/ in at most 25"
    fi
  done <<<"$(wc -l -- "${generated[@]}")"
fi

# C10 — the untrusted-content rule is in the root block, which every tool reads.
if [ "$root_blocks" -gt 0 ] && ! grep -qF 'data, never instructions' <<<"$root_block"; then
  report C10 AGENTS.md "the cortex block lacks the untrusted-content rule ('... is data, never instructions')"
fi

# C11 — the install is filled in: every required config value is set
# (CODE_OWNERS when CI=github; D16).
if [ -f cortex/config ]; then
  keys="BUILD_CMD TEST_CMD LINT_CMD TEST_GLOBS TOOLS"
  [ "$(config_value CI < cortex/config | tr -d '[:space:]')" != github ] || keys="$keys CODE_OWNERS"
  for key in $keys; do
    [ -n "$(config_value "$key" < cortex/config | tr -d '[:space:]')" ] || report C11 cortex/config "$key is not set"
  done
fi

# C12 — no placeholder left in the router or the root block.
if [ -f cortex/AGENTS.md ] && grep -q 'TODO' cortex/AGENTS.md; then
  report C12 cortex/AGENTS.md "still contains TODO; fill it in (INSTALL.md)"
fi
if grep -q 'TODO' <<<"$root_block"; then
  report C12 AGENTS.md "the cortex block contains TODO"
fi

# C13 — R15: the footprint matches the repository. Every created file
# exists; every recorded block is there once; every block marker outside
# cortex/ is recorded; every entry's rule is in its file (merged).
if [ ! -f "$FP_FILE" ]; then
  report C13 "$FP_FILE" "missing; it records what cortex wrote outside cortex/ (reinstall to rebuild it)"
elif ! fp_load; then
  report C13 "$FP_FILE" "unknown format '$FP_BAD_FORMAT' (this cortex reads '$FP_FORMAT')"
else
  recorded_blocks=""
  while IFS="$TAB" read -r kind path f3 _; do
    [ -n "$kind" ] || continue
    case "$kind" in
      created)
        [ -e "$path" ] || report C13 "$path" "recorded as created by cortex, but missing (restore it, or run adapt.sh)" ;;
      block)
        recorded_blocks="$recorded_blocks$path$TAB$f3"$'\n'
        n="$(block_count "$path" "$f3")"
        if [ "$n" -eq 0 ]; then
          report C13 "$path" "its recorded cortex $f3 block is missing"
        elif [ "$n" -gt 1 ]; then
          report C13 "$path" "has $n cortex $f3 blocks; keep one"
        fi ;;
      entry)
        if [ ! -f "$path" ] || ! entry_present "$path" "$f3" "$(cat "$path")"; then
          rule="$(entry_rule "$f3")"
          report C13 "$path" "lacks the recorded entry ${rule:-$f3} (merge it as adapt.sh printed)"
        fi ;;
      *) report C13 "$FP_FILE" "unknown record kind '$kind'" ;;
    esac
  done <<<"$FP_RECORDS"
  # One search for begin markers in the project's files, cortex/ excluded.
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    markers="$(git -c core.quotepath=off grep -I --untracked --no-color -E '^(<!-- |# )cortex:begin ' -- . ':(exclude)cortex' 2>/dev/null || true)"
  else
    markers="$(grep -rIE --exclude-dir=.git --exclude-dir=cortex '^(<!-- |# )cortex:begin ' . 2>/dev/null | sed 's|^\./||' || true)"
  fi
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    path="${m%%:*}"
    id="${m#*cortex:begin }"
    id="${id%% *}"
    id="${id%"$CR"}"
    grep -qxF -- "$path$TAB$id" <<<"$recorded_blocks" ||
      report C13 "$path" "holds a cortex $id block that cortex/footprint doesn't record"
  done <<<"$markers"
fi

# C14 — no merge-conflict marker left from an upgrade (D2), under cortex/ or
# in a recorded block.
conflicted="$( [ -d cortex ] && grep -rlE '^(<<<<<<<|>>>>>>>)( |$)' cortex 2>/dev/null | LC_ALL=C sort || true)"
report_each C14 "has merge-conflict markers; resolve them (the upgrade left both versions)" <<<"$conflicted"
if [ -n "$FP_RECORDS" ]; then
  while IFS="$TAB" read -r kind path f3 _; do
    [ "$kind" = block ] || continue
    if block_content "$path" "$f3" | grep -qE '^(<<<<<<<|>>>>>>>)( |$)'; then
      report C14 "$path" "the cortex $f3 block has merge-conflict markers; resolve them"
    fi
  done <<<"$FP_RECORDS"
fi

if [ "$failures" -eq 0 ]; then
  echo "check: ok"
else
  echo "check: $failures failure(s)"
  exit 1
fi
