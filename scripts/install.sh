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
# Exit:  0 installed (even with skipped files), 2 usage or target error.
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

created=0
unchanged=0
skipped=0

while IFS= read -r rel; do
  src="$TEMPLATE/$rel"
  dest="$target/$rel"
  if [ ! -e "$dest" ]; then
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    case "$rel" in *.sh) chmod +x "$dest" ;; esac
    echo "created $rel"
    created=$((created + 1))
  elif cmp -s "$src" "$dest"; then
    echo "unchanged $rel"
    unchanged=$((unchanged + 1))
  else
    echo "skipped $rel (exists, differs)"
    skipped=$((skipped + 1))
  fi
done < <(cd "$TEMPLATE" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)

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

version="$(tr -d '\r\n' < "$CORTEX_ROOT/VERSION")"
version_file="$target/.cortex/version"
if [ ! -e "$version_file" ]; then
  mkdir -p "$target/.cortex"
  cp "$CORTEX_ROOT/VERSION" "$version_file"
  echo "created .cortex/version"
  created=$((created + 1))
else
  installed="$(tr -d '\r\n' < "$version_file")"
  if [ "$installed" = "$version" ]; then
    echo "unchanged .cortex/version"
    unchanged=$((unchanged + 1))
  else
    echo "warning: installed version $installed, template version $version"
  fi
fi

echo "install: $created created, $unchanged unchanged, $skipped skipped"
