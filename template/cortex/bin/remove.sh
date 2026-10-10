#!/usr/bin/env bash
# Removes cortex from this repository (spec docs/specs/2026-10-05-v3-removable-layout.md,
# "cortex/bin/remove.sh"): everything under cortex/, and everything outside it
# that cortex/footprint records, so the repository is as it was before the
# install, plus the records you keep.
#
#   1. Hosting first: the steps to take in the repository's settings, because
#      deleting the workflow while its check is required blocks every pull
#      request. Stops until they're confirmed (or --hosting-done).
#   2. References: project lines that name a path under cortex/, which would
#      break. Stops until they're confirmed (or --references-ok).
#   3. Records (the change folders, knowledge, the constitution's project
#      rules, the conventions): kept by default in docs/cortex-records/, or
#      --keep-records <dir>, or --delete-records.
#   4. The footprint, record by record: a block is removed with exactly what
#      inserting it added (an edited block is shown first); a created file is
#      deleted if it is as cortex left it (--force deletes it anyway); entry
#      lines are listed for you to remove from their file by hand.
#   5. The records moved or deleted, then cortex/ deleted.
#
# It starts only from a clean work tree, so its changes are one diff to review
# and commit, or undo with git restore and git clean (D14). It never runs a
# git command that writes. Interactive (standard input a terminal), it asks
# at steps 1 to 3; otherwise it asks nothing and takes the flags or defaults.
#
# Usage: cortex/bin/remove.sh [--hosting-done] [--references-ok]
#          [--keep-records <dir> | --delete-records] [--force]
# Exit:  0 removed, or stopped for confirmation with nothing changed;
#        2 usage error or a refusal, with nothing changed.
set -euo pipefail

# Run from a copy, so deleting cortex/ doesn't delete the running script
# (Windows won't delete an open file; elsewhere bash may read it lazily).
if [ -z "${CORTEX_REMOVE_HOME:-}" ]; then
  home="$(cd "$(dirname "$0")" && pwd)"
  copy="$(mktemp)"
  cp "$0" "$copy"
  CORTEX_REMOVE_HOME="$home" exec bash "$copy" "$@"
fi
here="$CORTEX_REMOVE_HOME"
trap 'rm -f "$0"' EXIT
# shellcheck source=_config.sh
. "$here/_config.sh"
# shellcheck source=_footprint.sh
. "$here/_footprint.sh"
cd "$here/../.."

usage() {
  echo "usage: cortex/bin/remove.sh [--hosting-done] [--references-ok] [--keep-records <dir> | --delete-records] [--force]" >&2
  exit 2
}
refuse() { echo "refused $1: $2"; exit 2; }

hosting_done=0
references_ok=0
records=""   # a directory, "delete", or "" (ask, or the default)
force=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --hosting-done) hosting_done=1 ;;
    --references-ok) references_ok=1 ;;
    --keep-records) [ "$#" -ge 2 ] && [ -n "$2" ] || usage; records="$2"; shift ;;
    --delete-records) records=delete ;;
    --force) force=1 ;;
    *) usage ;;
  esac
  shift
done

interactive=0
[ -t 0 ] && interactive=1
# ask PROMPT -> 0 if the answer is yes
ask() {
  local a=""
  [ "$interactive" = 1 ] || return 1
  printf '%s [y/N] ' "$1"
  IFS= read -r a || true
  case "$a" in y | Y | yes | YES) return 0 ;; esac
  return 1
}

[ -f cortex/version ] || refuse cortex/ "no cortex/version: this is not a cortex install"
fp_load || refuse cortex/footprint "unknown format '$FP_BAD_FORMAT' (this cortex reads '$FP_FORMAT')"
if [ -n "$(git status --porcelain)" ]; then
  refuse "$(pwd)" "the work tree has uncommitted changes; commit or stash them first, so the removal is one diff you can review or undo (D14)"
fi

# ---- 1. hosting ------------------------------------------------------------------------

echo "Before cortex's files go, in the repository's hosting settings:"
echo "  1. Remove \"cortex\" from the default branch's required status checks (branch protection or rulesets); deleting its workflow first blocks every pull request."
echo "  2. Then remove or adjust the required review from Code Owners, if cortex is why it is on."
if [ "$hosting_done" = 0 ]; then
  if ! ask "Are both done?"; then
    echo "stopped: nothing changed; once both are done, run again with --hosting-done"
    exit 0
  fi
fi

# ---- 2. references ---------------------------------------------------------------------

# Project lines naming a path under cortex/ ("mycortex/" doesn't count):
# cortex's own blocks, the files it created and its entry lines are left out.
created_paths="$(fp_match created | cut -f2)"
kept_dir="${records:-docs/cortex-records}"   # step 3's directory, as far as known
kept_dir="${kept_dir%/}"
refs=""
while IFS= read -r m; do
  [ -n "$m" ] || continue
  path="${m%%:*}"
  rest="${m#*:}"
  line="${rest%%:*}"
  text="${rest#*:}"
  text="${text%"$CR"}"
  grep -qxF -- "$path" <<<"$created_paths" && continue
  # inside one of cortex's blocks in that file?
  if [ -n "$(fp_match block "$path")" ]; then
    inside="$(awk -v n="$line" '
      { l = $0; sub(/\r$/, "", l) }
      l ~ /^(<!-- |# )cortex:begin / { inb = 1 }
      NR == n { print (inb ? 1 : 0); exit }
      l ~ /^(<!-- |# )cortex:end / { inb = 0 }' "$path")"
    [ "$inside" = 1 ] && continue
  fi
  # a recorded entry line? (entry_present: the rule C13 uses)
  skip=0
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    if entry_present "$path" "$(printf '%s\n' "$rec" | cut -f3)" "$text"; then skip=1; break; fi
  done <<<"$(fp_match entry "$path")"
  [ "$skip" = 1 ] && continue
  refs="${refs}reference $path:$line: $text"$'\n'
  # where a path the records step keeps will be (G7): not one under another
  # directory (docs/cortex/...), and without a #fragment or ?query
  if [ "$kept_dir" != delete ]; then
    while IFS= read -r p; do
      case "$p" in
        cortex/changes/* | cortex/knowledge/* | cortex/constitution.md)
          refs="${refs}  kept as $kept_dir/${p#cortex/}"$'\n' ;;
      esac
    done <<<"$(printf '%s\n' "$text" | grep -oE '(^|[^A-Za-z0-9_./-])cortex/[^][:space:]()<>`"'\''#?]*' | sed -e 's|^[^c]||' -e 's/[.,;:]*$//' || true)"
  fi
done <<<"$(git -c core.quotepath=off grep -I -n --no-color -E '(^|[^A-Za-z0-9_.-])cortex/' -- . ':(exclude)cortex' 2>/dev/null || true)"
if [ -n "$refs" ]; then
  echo "These project lines name paths under cortex/, which will be gone:"
  printf '%s' "$refs"
  if [ "$references_ok" = 0 ] && ! ask "Remove cortex anyway?"; then
    echo "stopped: nothing changed; fix them (and commit), or run again with --references-ok"
    exit 0
  fi
fi

# ---- 3. records ------------------------------------------------------------------------

if [ -z "$records" ]; then
  records=docs/cortex-records
  if [ "$interactive" = 1 ]; then
    printf 'Keep the records (change folders, knowledge, project rules, conventions)? Directory [docs/cortex-records], or "delete": '
    IFS= read -r a || true
    [ -z "$a" ] || records="$a"
  fi
fi
if [ "$records" != delete ]; then
  records="${records%/}"
  case "$records" in
    cortex | cortex/*) refuse "$records" "is inside cortex/, which is deleted; name another directory" ;;
  esac
  if [ -e "$records" ] && [ -n "$(ls -A "$records" 2>/dev/null)" ]; then
    refuse "$records" "exists and isn't empty; name another directory with --keep-records <dir>"
  fi
fi

# ---- 4. the footprint ---------------------------------------------------------------------

entries=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  fp_remove_path "$path" "$force"
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    entries="${entries}entry $path $(printf '%s\n' "$rec" | cut -f3-)"$'\n'
  done <<<"$(fp_match entry "$path")"
  fp_drop entry "$path"
done <<<"$(printf '%s\n' "$FP_RECORDS" | cut -f2 | LC_ALL=C sort -u)"
n_entries=0
if [ -n "$entries" ]; then
  echo "Remove these lines by hand; cortex asked for them to be merged:"
  printf '%s' "$entries"
  n_entries="$(printf '%s' "$entries" | grep -c '')"
fi

# ---- 5. records, then cortex/ ------------------------------------------------------------

# section FILE HEADING -> the "## HEADING" section of FILE, heading included
section() {
  [ -f "$1" ] || return 0
  tr -d '\r' < "$1" | awk -v h="## $2" '
    $0 == h { inside = 1; print; next }
    inside && /^## / { exit }
    inside { print }'
}
if [ "$records" = delete ]; then
  echo "records deleted"
else
  mkdir -p "$records"
  [ ! -d cortex/changes ] || mv cortex/changes "$records/changes"
  [ ! -d cortex/knowledge ] || mv cortex/knowledge "$records/knowledge"
  section cortex/constitution.md Project > "$records/constitution.md"
  section cortex/AGENTS.md Conventions > "$records/conventions.md"
  echo "records $records"
fi
rm -rf cortex
echo "removed cortex/"

echo "remove: $FP_REMOVED removed, $FP_KEPT kept, $n_entries entries to remove by hand"
