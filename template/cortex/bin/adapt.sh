#!/usr/bin/env bash
# Generates the agent-tool files from TOOLS in cortex/config (design rule R8)
# and, with CI=github, the pull request boundary (spec D8).
#
# Canonical content lives in AGENTS.md, cortex/AGENTS.md and cortex/harness/;
# every file written here points at it or enforces it with a tool-specific
# mechanism. Everything written outside cortex/ is recorded in
# cortex/footprint (D7), so remove.sh can take it out again:
#   - a file whose path is cortex's own (.claude/agents/cortex-*.md,
#     .claude/skills/cortex-*/, .cursor/rules/cortex.mdc,
#     .github/workflows/cortex.yml) is written whole, recorded "created";
#   - a file whose name a tool fixes and a project may share (CLAUDE.md,
#     GEMINI.md, .github/copilot-instructions.md, CODEOWNERS) gets cortex's
#     content in a marked block; the project's lines stay (A3);
#   - .claude/settings.json, which can't carry a block: created when absent;
#     otherwise the rules it lacks are printed for a person or agent to merge
#     and recorded as entries (Q1). The JSON is never edited here;
#   - a root .prettierignore without a line leaving cortex/ alone (cortex,
#     /cortex, cortex/ or /cortex/): cortex/, printed and recorded as an
#     entry the same way (Amendment 3 F2, G1).
# A block is output, not source: a re-run rewrites it, reporting an edit it
# overwrote. A cortex-named file cortex didn't record is the project's, so
# this script refuses to touch it (D11). Files for a tool dropped from TOOLS
# (or for CI=none) are removed by remove.sh's rules: an edited file is kept.
#
# Tool config formats change. When an adapter stops working, fix its source
# in cortex/adapters/ (or the text below) and re-run.
#
# Usage: cortex/bin/adapt.sh [repo-root]
# Exit:  0 done, 2 cortex/config missing or a refusal (nothing written).
set -euo pipefail

# The helpers next to this file, resolved before the cd below.
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_config.sh
. "$here/_config.sh"
# shellcheck source=_footprint.sh
. "$here/_footprint.sh"
cd "${1:-.}"

ADAPTERS=cortex/adapters/claude-code
POINTER="Read \`AGENTS.md\` in the repository root and follow it; it is the canonical agent context."

refuse() { echo "refused $1: $2"; exit 2; }

if [ ! -f cortex/config ]; then
  echo "error: cortex/config not found (install cortex first: bin/install.sh in a cortex clone)" >&2
  exit 2
fi
fp_load || refuse cortex/footprint "unknown format '$FP_BAD_FORMAT' (this cortex reads '$FP_FORMAT')"

# TOOLS is a comma-separated list; whitespace around the names is dropped.
tools="$(config_value TOOLS < cortex/config | tr -d '[:space:]')"
ci="$(config_value CI < cortex/config | tr -d '[:space:]')"
[ -n "$ci" ] || ci=none
owners="$(config_value CODE_OWNERS < cortex/config)"
globs="$(config_value TEST_GLOBS < cortex/config)"

active() { case ",$tools," in *",$1,"*) return 0 ;; esac; return 1; }
# TOOLS=none says no tools on purpose, so their files go (below). Unset (or a
# placeholder) says nothing, so nothing is removed for it.

# The CODEOWNERS file GitHub reads is the first of these that exists; a
# second one elsewhere would be ignored, or would hide the project's.
codeowners="$(fp_match block | awk -F'\t' '$3 == "codeowners" { print $2; exit }')"
if [ -z "$codeowners" ]; then
  codeowners=.github/CODEOWNERS
  for p in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
    if [ -f "$p" ]; then codeowners="$p"; break; fi
  done
fi

# ---- what this run writes ------------------------------------------------------------

# whole files: "<path>\t<source>"
wholes=""
if active claude && [ -d "$ADAPTERS" ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] && [ "$rel" != .claude/settings.json ] || continue
    wholes="$wholes$rel$TAB$ADAPTERS/$rel"$'\n'
  done <<<"$(cd "$ADAPTERS" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)"
fi
cursor_src=""
if active cursor; then
  cursor_src="$(mktemp)"
  printf -- '---\ndescription: Canonical agent context for this repository\nalwaysApply: true\n---\n%s\n' "$POINTER" > "$cursor_src"
  wholes="$wholes.cursor/rules/cortex.mdc$TAB$cursor_src"$'\n'
fi
if [ "$ci" = github ]; then
  wholes="$wholes.github/workflows/cortex.yml${TAB}cortex/ci/github/cortex.yml"$'\n'
fi

# D11: refuse before writing anything
while IFS="$TAB" read -r p src; do
  [ -n "$p" ] || continue
  if [ -e "$p" ] && [ -z "$(fp_match created "$p")" ]; then
    refuse "$p" "exists and is not recorded as cortex's (D11); rename or remove it, then run adapt.sh again"
  fi
done <<<"$wholes"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" ${cursor_src:+"$cursor_src"}' EXIT
desired=""   # every path this run keeps, one per line
want() { desired="$desired$1"$'\n'; }

# record_created PATH : (re)record a file cortex created, with its sha now
record_created() { fp_drop created "$1"; fp_add created "$1" "$(file_sha "$1")"; }

# emit_file PATH SOURCE : a whole file (A3)
emit_file() {
  local f="$1" src="$2" rec
  want "$f"
  rec="$(fp_match created "$f" | sed -n 1p)"
  if [ ! -e "$f" ]; then
    case "$f" in */*) mkdir -p "${f%/*}" ;; esac
    cp "$src" "$f"
    record_created "$f"
    echo "created $f"
  elif cmp -s "$src" "$f"; then
    echo "unchanged $f"
  elif [ "$(file_sha "$f")" = "$(fp_field "$rec" 3)" ]; then
    cp "$src" "$f"
    record_created "$f"
    echo "replaced $f"
  else
    echo "kept $f (edited)"
  fi
}

# emit_block PATH ID SOURCE : cortex's content in a block (A3)
emit_block() {
  local f="$1" id="$2" src="$3" rec sep new=0
  want "$f"
  rec="$(fp_match block "$f" "$id" | sed -n 1p)"
  # A block written through a link would land in the file it points to,
  # recorded under the wrong path (CLAUDE.md -> AGENTS.md is common, and the
  # tool then reads AGENTS.md, which already holds cortex's block).
  if [ -L "$f" ] && [ -z "$rec" ]; then
    echo "skipped $f (a symbolic link; cortex writes no block through one)"
    return 0
  fi
  [ -e "$f" ] || new=1
  if [ "$(block_count "$f" "$id")" -eq 0 ]; then
    sep="$(block_insert "$f" "$id" "$src")"
    if [ "$new" = 1 ]; then record_created "$f"; echo "created $f"; fi
    fp_add_block "$f" "$id" "$sep"
    echo "block $f $id"
  else
    sep="$(fp_field "$rec" 5)"
    # Blank lines aside (F1): a formatter's blank lines are not an edit, and
    # rewriting them would only start the formatter's next round.
    if [ "$(block_content "$f" "$id" | nonblank_sha)" = "$(nonblank_sha < "$src")" ]; then
      echo "unchanged $f"
    else
      if [ -n "$rec" ] && block_unedited "$f" "$id" "$rec"; then
        echo "block $f $id"
      else
        echo "overwrote edited block $f $id"
      fi
      block_set "$f" "$id" "$src"
    fi
    fp_add_block "$f" "$id" "${sep:-0}"
  fi
  [ -z "$(fp_match created "$f")" ] || record_created "$f"
}

# emit_entries PATH SOURCE : SOURCE's permission rules that PATH lacks,
# printed and recorded as entries; a rule already there is the project's (D11)
emit_entries() {
  local f="$1" src="$2" line rule list="" said=""
  want "$f"
  while IFS= read -r line; do
    line="${line%"$CR"}"
    case "$line" in
      *'"allow"'*'['* | *'"deny"'*'['* | *'"ask"'*'['*)
        list="$(printf '%s\n' "$line" | sed -n 's/^[[:space:]]*"\([a-z]*\)".*/\1/p')"
        continue ;;
    esac
    printf '%s\n' "$line" | grep -qE '^[[:space:]]*"[^"]*",?[[:space:]]*$' || continue
    rule="$(printf '%s\n' "$line" | sed -n 's/^[[:space:]]*\("[^"]*"\).*/\1/p')"
    if grep -qF -- "$rule" "$f"; then
      continue # merged already (a recorded entry stays recorded), or the project's own
    fi
    if [ "$said" != "$list" ]; then
      echo "merge these lines into $f, in permissions.$list (as in $src):"
      said="$list"
    fi
    [ -n "$(fp_match entry "$f" "$line")" ] || fp_add entry "$f" "$line"
    echo "entry $f $line"
  done < "$src"
}

# ---- tools ------------------------------------------------------------------------------

if [ -z "$tools" ]; then
  echo "warning: TOOLS is not set in cortex/config; no adapters written"
else
  IFS=',' read -r -a tool_list <<<"$tools"
  for tool in "${tool_list[@]}"; do
    case "$tool" in
      "") ;;
      claude)
        printf '@AGENTS.md\n' > "$tmp/claude"
        emit_block CLAUDE.md claude "$tmp/claude"
        while IFS="$TAB" read -r p src; do
          [ -n "$p" ] || continue
          case "$src" in "$ADAPTERS"/*) emit_file "$p" "$src" ;; esac
        done <<<"$wholes"
        settings=.claude/settings.json
        # created when absent; replaced while cortex's copy is unedited;
        # otherwise (the project's, or edited) the missing rules are entries
        rec="$(fp_match created "$settings" | sed -n 1p)"
        if [ -f "$ADAPTERS/$settings" ]; then
          if [ ! -e "$settings" ] || cmp -s "$ADAPTERS/$settings" "$settings" ||
            { [ -n "$rec" ] && [ "$(file_sha "$settings")" = "$(fp_field "$rec" 3)" ]; }; then
            if [ -z "$rec" ] && [ -e "$settings" ]; then
              want "$settings"
              echo "unchanged $settings"
            else
              emit_file "$settings" "$ADAPTERS/$settings"
            fi
          else
            emit_entries "$settings" "$ADAPTERS/$settings"
          fi
        fi ;;
      cursor) emit_file .cursor/rules/cortex.mdc "$cursor_src" ;;
      copilot)
        printf '%s\n' "$POINTER" > "$tmp/copilot"
        emit_block .github/copilot-instructions.md copilot "$tmp/copilot" ;;
      gemini)
        printf '%s\n' "$POINTER" > "$tmp/gemini"
        emit_block GEMINI.md gemini "$tmp/gemini" ;;
      codex) echo "codex: reads AGENTS.md natively" ;;
      none) ;;
      *) echo "warning: unknown tool $tool" ;;
    esac
  done
fi

# ---- the pull request boundary (D8) ----------------------------------------------------

case "$ci" in
  github)
    emit_file .github/workflows/cortex.yml cortex/ci/github/cortex.yml
    if [ -z "$owners" ]; then
      want "$codeowners" # an earlier block stays until CODE_OWNERS is set again
      echo "warning: CI=github but CODE_OWNERS is not set in cortex/config; no CODEOWNERS block written"
    else
      {
        grep -v '^#' cortex/ci/github/CODEOWNERS | grep -v '^[[:space:]]*$' || true
        echo "# The tests (TEST_GLOBS in cortex/config):"
        set -f
        # shellcheck disable=SC2086 # the globs are split on purpose, unexpanded
        for g in $globs; do printf '%s\n' "$g"; done
        set +f
      } | awk -v o="$owners" -v co="/$codeowners" '
        /^#/ { print; next }
        { p = $1; if (p == "/.github/CODEOWNERS") p = co; printf "%-40s %s\n", p, o }' > "$tmp/codeowners"
      emit_block "$codeowners" codeowners "$tmp/codeowners"
    fi ;;
  none) ;;
  *) echo "warning: unknown CI value $ci (github or none); nothing written for it" ;;
esac

# ---- the project's formatter (Amendment 3 F2) --------------------------------------------

# cortex's files follow cortex's style, not the project's: Prettier is told
# to leave cortex/ alone, by a line a person merges (the file is the project's).
if [ -f .prettierignore ]; then
  want .prettierignore
  if ! prettierignore_has .prettierignore; then
    echo "merge this line into .prettierignore:"
    [ -n "$(fp_match entry .prettierignore cortex/)" ] || fp_add entry .prettierignore cortex/
    echo "entry .prettierignore cortex/"
  fi
fi

# ---- TEST_GLOBS that lock nothing (Amendment 3 F4) ---------------------------------------

# A glob matching no tracked file locks nothing; often it's anchored at the
# root by mistake (test_*.py for **/test_*.py). A note, not a check: a new
# repository may have no tests yet.
case "$globs" in *'<'*) globs="" ;; esac
if [ -n "$globs" ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  set -f
  # shellcheck disable=SC2086 # the globs are split on purpose, unexpanded
  for g in $globs; do
    [ -n "$(git ls-files -- "$g" 2>/dev/null | sed -n 1p)" ] || echo "note: TEST_GLOBS $g matches no tracked file"
  done
  set +f
fi

# ---- what an earlier run wrote and this one doesn't ------------------------------------

# owner PATH -> the part of the config that writes PATH
owner() {
  case "$1" in
    AGENTS.md) echo install ;;
    CLAUDE.md | .claude/*) echo claude ;;
    .cursor/*) echo cursor ;;
    .github/copilot-instructions.md) echo copilot ;;
    GEMINI.md) echo gemini ;;
    .github/workflows/cortex.yml | CODEOWNERS | .github/CODEOWNERS | docs/CODEOWNERS) echo ci ;;
    *) echo other ;;
  esac
}

dropped_entries=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  grep -qxF -- "$p" <<<"$desired" && continue
  o="$(owner "$p")"
  case "$o" in install | other) continue ;; ci) ;; *) [ -n "$tools" ] || continue ;; esac
  fp_remove_path "$p" 0
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    dropped_entries="$dropped_entries$p$TAB$(printf '%s\n' "$rec" | cut -f3-)"$'\n'
  done <<<"$(fp_match entry "$p")"
  fp_drop entry "$p"
done <<<"$(printf '%s\n' "$FP_RECORDS" | cut -f2 | LC_ALL=C sort -u)"
if [ -n "$dropped_entries" ]; then
  echo "remove these lines by hand; cortex added them and no longer needs them:"
  while IFS="$TAB" read -r p line; do
    [ -z "$p" ] || echo "entry $p $line"
  done <<<"$dropped_entries"
fi

fp_save

# A file git ignores (a project that ignores .claude/, say) never reaches a
# commit, so every other checkout lacks it and C13 fails there.
written=()
while IFS= read -r p; do [ -n "$p" ] && [ -e "$p" ] && written+=("$p"); done <<<"$desired"
if [ "${#written[@]}" -gt 0 ]; then
  ignored="$(git check-ignore -- "${written[@]}" 2>/dev/null || true)"
  if [ -n "$ignored" ]; then
    echo "note: git ignores these files cortex wrote; commit them with git add -f, or every other checkout lacks them (C13):"
    printf '%s\n' "$ignored" | sed 's/^/  /'
  fi
fi
