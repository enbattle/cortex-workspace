#!/usr/bin/env bash
# Installs the cortex harness into a git repository.
#
# Copies every file under template/ to the same path in the target, only where
# the target has no file yet. It never overwrites, never deletes, and never
# runs a git command that writes, so it is safe to re-run and safe on an
# existing repository: a file that already exists and differs is reported as
# skipped for a human (or the INSTALL.md walkthrough) to merge.
#
# Usage: scripts/install.sh <target-dir>
# Exit:  0 installed (even with skipped files), 2 usage or target error,
#        including a target that isn't a repository root or has a different
#        cortex version installed (upgrades aren't supported yet).
set -euo pipefail

CORTEX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$CORTEX_ROOT/template"

if [ "$#" -ne 1 ]; then
  echo "usage: scripts/install.sh <target-dir>" >&2
  exit 2
fi
target="$1"
if [ ! -d "$target" ]; then
  echo "error: $target is not a directory" >&2
  exit 2
fi
if ! git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: $target is not inside a git work tree (run git init first)" >&2
  exit 2
fi
target="$(cd "$target" && pwd)"
if [ -n "$(git -C "$target" rev-parse --show-prefix)" ]; then
  echo "error: $target is not the root of its git repository; install at the root (the scripts resolve paths from it)" >&2
  exit 2
fi

version="$(tr -d '\r\n' < "$CORTEX_ROOT/VERSION")"
if [ -e "$target/.cortex/version" ]; then
  installed="$(tr -d '\r\n' < "$target/.cortex/version")"
  if [ "$installed" != "$version" ]; then
    echo "error: this repository has cortex $installed installed; upgrading to $version is not supported yet (see docs/02-extensions.md §4)" >&2
    exit 2
  fi
fi

created=0
unchanged=0
skipped=0

# The work is done in bulk, so the number of processes doesn't grow with the
# template (spec Amendment 5): starting a process costs 10-50 ms on Windows,
# and one cp/cmp/mkdir per file made a 45-file install take 20 s there.
# Plain indexed arrays only: macOS still ships bash 3.2.
rels=()
while IFS= read -r rel; do
  [ -n "$rel" ] && rels+=("$rel")
done < <(cd "$TEMPLATE" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)

# Classify with shell builtins only: status[i] is new, same or differs.
status=()
present=()
present_at=()
for i in "${!rels[@]}"; do
  if [ -e "$target/${rels[$i]}" ]; then
    status[$i]=differs
    present+=("${rels[$i]}")
    present_at+=("$i")
  else
    status[$i]=new
  fi
done

# Present files: one hash call per side, byte for byte, in the same order.
if [ "${#present[@]}" -gt 0 ]; then
  src_hashes=()
  while IFS= read -r h; do src_hashes+=("$h"); done \
    < <(cd "$TEMPLATE" && git hash-object --no-filters -- "${present[@]}")
  dest_hashes=()
  while IFS= read -r h; do dest_hashes+=("$h"); done \
    < <(cd "$target" && git hash-object --no-filters -- "${present[@]}")
  for j in "${!present[@]}"; do
    [ "${src_hashes[$j]}" = "${dest_hashes[$j]}" ] && status[${present_at[$j]}]=same
  done
fi

# Absent files: one tar pass creates them with their directories, then one
# chmod makes the scripts executable (a template checked out on Windows may
# not carry the bit).
to_create=()
scripts=()
for i in "${!rels[@]}"; do
  if [ "${status[$i]}" = new ]; then
    to_create+=("${rels[$i]}")
    case "${rels[$i]}" in *.sh) scripts+=("$target/${rels[$i]}") ;; esac
  fi
done
if [ "${#to_create[@]}" -gt 0 ]; then
  (cd "$TEMPLATE" && tar -cf - "${to_create[@]}") | (cd "$target" && tar -xf -)
  [ "${#scripts[@]}" -eq 0 ] || chmod +x "${scripts[@]}"
fi

# Report every file in the template's sorted order, as before.
for i in "${!rels[@]}"; do
  case "${status[$i]}" in
    new)
      echo "created ${rels[$i]}"
      created=$((created + 1)) ;;
    same)
      echo "unchanged ${rels[$i]}"
      unchanged=$((unchanged + 1)) ;;
    *)
      echo "skipped ${rels[$i]} (exists, differs)"
      skipped=$((skipped + 1)) ;;
  esac
done

# The design rules the installed commands cite by ID (R1-R12), copied from
# their one source in this repository, under the same never-overwrite rule.
rules_rel=.cortex/design-rules.md
if [ ! -e "$target/$rules_rel" ]; then
  mkdir -p "$target/.cortex"
  cp "$CORTEX_ROOT/docs/01-design-rules.md" "$target/$rules_rel"
  echo "created $rules_rel"
  created=$((created + 1))
elif cmp -s "$CORTEX_ROOT/docs/01-design-rules.md" "$target/$rules_rel"; then
  echo "unchanged $rules_rel"
  unchanged=$((unchanged + 1))
else
  echo "skipped $rules_rel (exists, differs)"
  skipped=$((skipped + 1))
fi

version_file="$target/.cortex/version"
if [ ! -e "$version_file" ]; then
  mkdir -p "$target/.cortex"
  cp "$CORTEX_ROOT/VERSION" "$version_file"
  echo "created .cortex/version"
  created=$((created + 1))
else
  echo "unchanged .cortex/version"
  unchanged=$((unchanged + 1))
fi

if [ "$(git -C "$target" config --get core.filemode || true)" = "false" ]; then
  echo "note: this repository ignores file modes; after committing, run git update-index --chmod=+x scripts/cortex/*.sh"
fi

echo "install: $created created, $unchanged unchanged, $skipped skipped"
