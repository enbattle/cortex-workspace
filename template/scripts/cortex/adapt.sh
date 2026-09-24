#!/usr/bin/env bash
# Generates agent-tool adapters from TOOLS in .cortex/config (design rule R8).
#
# Canonical content lives in AGENTS.md and harness/; every file written here
# either points at it or enforces it with a tool-specific mechanism, and
# carries the marker "cortex:generated". A file is (re)written only if it is
# absent or already carries the marker; a hand-written file is left alone and
# reported. .claude/settings.json is copied only when absent (JSON can't carry
# the marker), and otherwise never touched.
#
# Tool config formats change. When an adapter stops working, fix its source in
# .cortex/adapters/ (or the pointer text below) and re-run; canonical files are
# never touched by this script.
#
# Usage: scripts/cortex/adapt.sh [repo-root]
# Exit:  0 done, 2 .cortex/config missing.
set -euo pipefail

cd "${1:-.}"
MARKER="cortex:generated"
POINTER="Read \`AGENTS.md\` in the repository root and follow it; it is the canonical agent context."

if [ ! -f .cortex/config ]; then
  echo "error: .cortex/config not found (run cortex's scripts/install.sh first)" >&2
  exit 2
fi

tools="$(tr -d '\r' < .cortex/config | awk '
  /^[[:space:]]*#/ { next }
  { eq = index($0, "="); if (eq == 0) next
    key = substr($0, 1, eq - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
    if (key != "TOOLS") next
    val = substr($0, eq + 1); gsub(/[[:space:]]/, "", val); print val; exit }')"
case "$tools" in "<"*">") tools="" ;; esac
if [ -z "$tools" ]; then
  echo "warning: TOOLS is not set in .cortex/config; no adapters written"
  exit 0
fi

# emit PATH : writes stdin to PATH under the marker rule.
emit() {
  local path="$1" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [ -e "$path" ] && ! grep -qF "$MARKER" "$path"; then
    echo "skipped $path (hand-written; merge manually)"
  elif [ -e "$path" ] && cmp -s "$tmp" "$path"; then
    echo "unchanged $path"
  else
    mkdir -p "$(dirname "$path")"
    cp "$tmp" "$path"
    echo "wrote $path"
  fi
  rm -f "$tmp"
}

adapt_claude() {
  printf '<!-- %s -->\n@AGENTS.md\n' "$MARKER" | emit CLAUDE.md
  local src=.cortex/adapters/claude-code rel
  [ -d "$src" ] || return 0
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ "$rel" = .claude/settings.json ]; then
      if [ -e .claude/settings.json ]; then
        echo "skipped .claude/settings.json (exists; merge the permissions block from $src/.claude/settings.json)"
      else
        mkdir -p .claude
        cp "$src/$rel" .claude/settings.json
        echo "wrote .claude/settings.json"
      fi
    else
      emit "$rel" < "$src/$rel"
    fi
  done <<<"$(cd "$src" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)"
}

IFS=',' read -r -a tool_list <<<"$tools"
for tool in "${tool_list[@]}"; do
  case "$tool" in
    "") ;;
    claude) adapt_claude ;;
    cursor)
      printf -- '---\ndescription: Canonical agent context for this repository\nalwaysApply: true\n---\n<!-- %s -->\n%s\n' "$MARKER" "$POINTER" |
        emit .cursor/rules/cortex.mdc ;;
    copilot) printf '<!-- %s -->\n%s\n' "$MARKER" "$POINTER" | emit .github/copilot-instructions.md ;;
    gemini) printf '<!-- %s -->\n%s\n' "$MARKER" "$POINTER" | emit GEMINI.md ;;
    codex) echo "codex: reads AGENTS.md natively" ;;
    *) echo "warning: unknown tool $tool" ;;
  esac
done
