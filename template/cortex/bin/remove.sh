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

# existing_ancestor PATH -> the deepest part of PATH that exists (PATH
# itself, if it does), or .
existing_ancestor() {
  local d="$1"
  while [ ! -e "$d" ]; do
    case "$d" in */*) d="${d%/*}"; [ -n "$d" ] || d=/ ;; *) d=. ;; esac
  done
  printf '%s' "$d"
}

# inside_cortex PATH : PATH is cortex/ or inside it, however it is spelled:
# its deepest existing directory (above a file, its parent), resolved
# physically (links followed), or one above that, is cortex/ (-ef: the same
# file, so case and links don't matter; 2026-10-12 spec V3, Amendment 1 A2)
inside_cortex() {
  local d p
  d="$(existing_ancestor "$1")"
  if [ ! -d "$d" ]; then
    case "$d" in */*) d="${d%/*}"; [ -n "$d" ] || d=/ ;; *) d=. ;; esac
  fi
  p="$(cd "$d" 2>/dev/null && pwd -P)" || return 1
  while :; do
    [ "$p" -ef cortex ] && return 0
    [ "$p" != / ] || return 1
    p="${p%/*}"
    [ -n "$p" ] || p=/
  done
}

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
# 2026-10-12 spec V1: a block with no end marker can't be taken out cleanly
fp_unclosed_refusals || exit 2

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
# The loop below starts no process per line: the footprint is read once
# into lists, and a file's block lines once per file (2026-10-12 spec,
# Amendment 2 W1).
created_paths=$'\n'   # newline-framed lists, matched with case
block_paths=$'\n'
entry_recs=""
while IFS= read -r rec; do
  [ -n "$rec" ] || continue
  fp_split "$rec"
  case "$FP_1" in
    created) created_paths="$created_paths$FP_2"$'\n' ;;
    block) block_paths="$block_paths$FP_2"$'\n' ;;
    entry) entry_recs="$entry_recs$rec"$'\n' ;;
  esac
done <<<"$FP_RECORDS"
inside_lines=$'\n'    # "<path>:<line>" for each line inside one of cortex's blocks
inside_read=$'\n'     # the files read for it
kept_dir="${records:-docs/cortex-records}"   # step 3's directory, as far as known
kept_dir="${kept_dir%/}"
# a path under cortex/ in a line, after a character that can't be part of a
# longer name (as `git grep` below finds them)
path_re='(^|[^A-Za-z0-9_./-])cortex/[^][:space:]()<>`"'\''#?]*'
refs=""
while IFS= read -r m; do
  [ -n "$m" ] || continue
  path="${m%%:*}"
  rest="${m#*:}"
  line="${rest%%:*}"
  text="${rest#*:}"
  text="${text%"$CR"}"
  case "$created_paths" in *$'\n'"$path"$'\n'*) continue ;; esac
  # inside one of cortex's blocks in that file? (a marker line counts as inside)
  case "$block_paths" in
    *$'\n'"$path"$'\n'*)
      case "$inside_read" in
        *$'\n'"$path"$'\n'*) ;;
        *)
          inside_lines="$inside_lines$(awk -v p="$path" '
            { l = $0; sub(/\r$/, "", l) }
            l ~ /^(<!-- |# )cortex:begin / { inb = 1 }
            inb { print p ":" NR }
            l ~ /^(<!-- |# )cortex:end / { inb = 0 }' "$path")"$'\n'
          inside_read="$inside_read$path"$'\n' ;;
      esac
      case "$inside_lines" in *$'\n'"$path:$line"$'\n'*) continue ;; esac ;;
  esac
  # a recorded entry line? (entry_present: the rule C13 uses)
  skip=0
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    fp_split "$rec"
    [ "$FP_2" = "$path" ] || continue
    if entry_present "$path" "$FP_3" "$text"; then skip=1; break; fi
  done <<<"$entry_recs"
  [ "$skip" = 1 ] && continue
  refs="${refs}reference $path:$line: $text"$'\n'
  # where a path the records step keeps will be (G7): not one under another
  # directory (docs/cortex/...), and without a #fragment or ?query
  if [ "$kept_dir" != delete ]; then
    rest="$text"
    while [[ $rest =~ $path_re ]]; do
      p="${BASH_REMATCH[0]}"
      rest="${rest#*"$p"}"
      case "$p" in c*) ;; *) p="${p#?}" ;; esac
      while :; do case "$p" in *[.,\;:]) p="${p%?}" ;; *) break ;; esac; done
      case "$p" in
        cortex/changes/* | cortex/knowledge/* | cortex/constitution.md)
          refs="${refs}  kept as $kept_dir/${p#cortex/}"$'\n' ;;
      esac
    done
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
  # ".." first: the walk below can't see through a part that doesn't exist yet
  case "/$records/" in
    */../*) refuse "$records" 'name the directory without ".."' ;;
  esac
  if inside_cortex "$records"; then
    refuse "$records" "is inside cortex/, which is deleted; name another directory"
  fi
  ancestor="$(existing_ancestor "$records")"
  if [ ! -d "$ancestor" ]; then
    refuse "$records" "$ancestor is not a directory; name another directory"
  fi
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
    rec="${rec#*"$TAB"}"   # the fields from the third on, as cut -f3-
    case "$rec" in *"$TAB"*) rec="${rec#*"$TAB"}" ;; *) rec="" ;; esac
    entries="${entries}entry $path $rec"$'\n'
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
    stop { next }
    $0 == h { inside = 1; print; next }
    inside && /^## / { stop = 1; next }
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
