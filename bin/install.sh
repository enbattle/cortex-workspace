#!/usr/bin/env bash
# Installs cortex into a git repository, or upgrades the cortex installed
# there (spec docs/specs/2026-10-05-v3-removable-layout.md, install steps 0-4).
#
# Everything cortex brings goes under cortex/ at the repository root. Outside
# it, install writes one marked block into AGENTS.md (creating the file if
# there is none) and records it in cortex/footprint; adapt.sh, run at the end,
# writes the agent-tool files the same way. An upgrade merges three versions
# of each file (the one installed, the new one, the user's) with
# `git merge-file`, reading the installed version from this clone's history
# by the commit cortex/version records, so a user's edits are kept.
#
# It never runs a git command that writes: the person or agent commits.
#
# Usage: bin/install.sh <repository-root>
# Exit:  0 done; 1 an upgrade left conflicts to resolve (every other file is
#        done); 2 usage error or a refusal, with nothing written.
set -euo pipefail

CORTEX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$CORTEX_ROOT/template/cortex"
BLOCK_SRC="$CORTEX_ROOT/template/blocks/AGENTS.md"
RULES_SRC="$CORTEX_ROOT/docs/01-design-rules.md"
# shellcheck source=../template/cortex/bin/_footprint.sh
. "$TEMPLATE/bin/_footprint.sh"
# shellcheck source=../template/cortex/bin/_config.sh
. "$TEMPLATE/bin/_config.sh"

usage() { echo "usage: bin/install.sh <repository-root>" >&2; exit 2; }
# refuse CAUSE REASON : A1's refusal line, then exit 2 (A2)
refuse() { echo "refused $1: $2"; exit 2; }

[ "$#" -eq 1 ] || usage
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
if ! commit="$(git -C "$CORTEX_ROOT" rev-parse --verify --quiet HEAD 2>/dev/null)" || [ -z "$commit" ]; then
  refuse "$CORTEX_ROOT" "not a git clone with a commit; cortex records the commit it installs from and upgrades read its history (D3), so install from a git clone"
fi
version="$(tr -d '\r\n' < "$CORTEX_ROOT/VERSION")"
cd "$target"

# ---- versions ------------------------------------------------------------------

# vercmp A B -> -1, 0 or 1: semantic versions, a pre-release (3.0.0-rc.1) below
# its release, numeric identifiers compared as numbers
VERCMP_AWK='
function idcmp(x, y) {
  if (x ~ /^[0-9]+$/ && y ~ /^[0-9]+$/) return (x + 0 < y + 0) ? -1 : (x + 0 > y + 0)
  if (x ~ /^[0-9]+$/) return -1
  if (y ~ /^[0-9]+$/) return 1
  return (x < y) ? -1 : (x > y)
}
function vcmp(a, b,   ap, bp, an, bn, i, c, n) {
  ap = a; bp = b; sub(/-.*/, "", ap); sub(/-.*/, "", bp)
  an = split(ap, A, "."); bn = split(bp, B, ".")
  n = an > bn ? an : bn
  for (i = 1; i <= n; i++) { c = idcmp((i <= an ? A[i] : 0), (i <= bn ? B[i] : 0)); if (c) return c }
  ap = (index(a, "-") ? substr(a, index(a, "-") + 1) : ""); bp = (index(b, "-") ? substr(b, index(b, "-") + 1) : "")
  if (ap == bp) return 0
  if (ap == "") return 1
  if (bp == "") return -1
  an = split(ap, A, "."); bn = split(bp, B, ".")
  n = an > bn ? an : bn
  for (i = 1; i <= n; i++) {
    if (i > an) return -1
    if (i > bn) return 1
    c = idcmp(A[i], B[i]); if (c) return c
  }
  return 0
}'
vercmp() { awk -v a="$1" -v b="$2" "$VERCMP_AWK"' BEGIN { print vcmp(a, b) }'; }
major() { printf '%s\n' "${1%%.*}"; }

echo "cortex $version from $commit"
if ! git -C "$CORTEX_ROOT" tag --points-at HEAD 2>/dev/null | grep -qxF "v$version"; then
  echo "unreleased: $commit"
fi

# ---- install step 0: refusals ------------------------------------------------------

if [ -e .cortex/version ]; then
  refuse .cortex/version "cortex $(tr -d '\r\n' < .cortex/version) (2.x) is installed here; 3.x does not migrate from 2.x (remove the 2.x files, then install)"
fi
if [ -e cortex ] && [ ! -f cortex/version ]; then
  refuse cortex/ "exists and is not a cortex install (no cortex/version); rename the project's directory, then install"
fi
if ! fp_load; then
  refuse cortex/footprint "unknown format '$FP_BAD_FORMAT' (this cortex reads '$FP_FORMAT')"
fi
if [ ! -e cortex ]; then
  # D11: a cortex-named path cortex didn't record is the project's
  for p in .github/workflows/cortex.yml .cursor/rules/cortex.mdc .claude/agents/cortex-* .claude/skills/cortex-*; do
    [ -e "$p" ] || continue
    refuse "$p" "exists and is not recorded as cortex's (D11); rename or remove it, then install"
  done
  if [ -f AGENTS.md ] && [ "$(block_count AGENTS.md agents)" -gt 0 ]; then
    refuse AGENTS.md "holds a cortex agents block that no footprint records (D11); remove the block, then install"
  fi
fi

filemode_note() {
  if [ "$(git config --get core.filemode || true)" = "false" ]; then
    echo "note: this repository ignores file modes; after committing, run git update-index --chmod=+x cortex/bin/*.sh"
  fi
}

# template_files -> every file under template/cortex/, relative, sorted
template_files() { (cd "$TEMPLATE" && find . -type f | sed 's|^\./||' | LC_ALL=C sort); }

# summary_counts BEFORE -> "<c> created, <b> blocks": the created and block
# records in cortex/footprint now that BEFORE (the records before) lacked (A1)
summary_counts() {
  local before="$1" c=0 b=0 rec
  fp_load || true
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    grep -qxF -- "$rec" <<<"$before" && continue
    case "$rec" in created"$TAB"*) c=$((c + 1)) ;; block"$TAB"*) b=$((b + 1)) ;; esac
  done <<<"$FP_RECORDS"
  printf '%s created, %s blocks' "$c" "$b"
}

# run_adapt : the installed adapt.sh; its refusal is reported, not fatal here
adapt_status=0
run_adapt() {
  set +e
  bash cortex/bin/adapt.sh .
  adapt_status=$?
  set -e
  if [ "$adapt_status" -ne 0 ]; then
    echo "note: adapt.sh exited $adapt_status; fix what it names, then run: bash cortex/bin/adapt.sh"
  fi
}

# ---- install step 1: fresh -----------------------------------------------------------

if [ ! -e cortex ]; then
  # One tar pass and one cp, chmod: the process count doesn't grow with the
  # template (2.x spec Amendment 5; process starts are slow on Windows).
  (cd "$CORTEX_ROOT/template" && tar -cf - cortex) | tar -xf -
  cp "$RULES_SRC" cortex/design-rules.md
  printf '%s\n%s\n' "$version" "$commit" > cortex/version
  chmod +x cortex/bin/*.sh
  while IFS= read -r rel; do
    [ -n "$rel" ] && echo "created cortex/$rel"
  done <<<"$(template_files)"
  echo "created cortex/design-rules.md"
  echo "created cortex/version"

  FP_RECORDS=""
  agents_created=0
  [ -e AGENTS.md ] || agents_created=1
  sep="$(block_insert AGENTS.md agents "$BLOCK_SRC")"
  [ "$agents_created" = 0 ] || { fp_add created AGENTS.md "$(file_sha AGENTS.md)"; echo "created AGENTS.md"; }
  fp_add block AGENTS.md agents "$(block_sha AGENTS.md agents)" "$sep"
  echo "block AGENTS.md agents"
  fp_save
  filemode_note
  run_adapt
  echo "install: $(summary_counts "")"
  exit 0
fi

# ---- an existing 3.x install -------------------------------------------------------------

installed="$(sed -n 1p cortex/version | tr -d '\r')"
installed_commit="$(sed -n 2p cortex/version | tr -d '\r')"
order="$(vercmp "$installed" "$version")"

# install step 4: no downgrades
if [ "$order" = 1 ]; then
  refuse cortex/version "cortex $installed is installed, newer than this clone's $version (no downgrades)"
fi

# install step 2: the same version and commit
if [ "$order" = 0 ] && [ "$installed_commit" = "$commit" ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] && echo "unchanged cortex/$rel"
  done <<<"$(template_files)"
  echo "unchanged cortex/design-rules.md"
  echo "unchanged cortex/version"
  echo "unchanged AGENTS.md"
  echo "install: 0 created, 0 blocks"
  exit 0
fi

# ---- install step 3: upgrade ------------------------------------------------------------------

# D14: one reviewable diff, undone with git restore and git clean
if [ -n "$(git status --porcelain)" ]; then
  refuse "$target" "the work tree has uncommitted changes; commit or stash them first, so the upgrade is one diff you can review or undo (D14)"
fi
# D3: the merge base is the installed commit, read from this clone
if [ -z "$installed_commit" ] || ! git -C "$CORTEX_ROOT" cat-file -e "$installed_commit^{commit}" 2>/dev/null; then
  refuse cortex/version "this clone lacks commit ${installed_commit:-(none recorded)}, which cortex $installed was installed from; fetch it in $CORTEX_ROOT (git fetch --unshallow --tags, or git fetch origin $installed_commit), then run again"
fi
# D12: a new major version may change the lock format or paths
if [ "$(major "$version")" != "$(major "$installed")" ]; then
  open_locks="$(find cortex/changes -mindepth 2 -maxdepth 2 -name lock.md 2>/dev/null | grep -v '^cortex/changes/archive/' | LC_ALL=C sort || true)"
  if [ -n "$open_locks" ]; then
    refuse "${open_locks//$'\n'/, }" "a change is in progress, and cortex $version is a new major version; finish or archive it first (locks on other branches too: see the CHANGELOG)"
  fi
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
replaced=0
merged=0
conflicts=0
scripts=()

# The three versions of each template file: B from the installed commit's
# tree (blob shas), N from this clone's template/, U the user's. Hashes are
# taken in bulk and joined in one pass; contents are read only for the files
# that need a merge. cortex/config is the project's (D12) and never merged.
git -C "$CORTEX_ROOT" ls-tree -r "$installed_commit" -- template/cortex/ |
  awk -F'\t' '{ split($1, m, " "); p = $2; sub(/^template\/cortex\//, "", p); print p "\t" m[3] }' > "$work/base"
paths=()
while IFS= read -r p; do [ -n "$p" ] && paths+=("$p"); done <<<"$(template_files)"
: > "$work/new"
if [ "${#paths[@]}" -gt 0 ]; then
  printf '%s\n' "${paths[@]}" > "$work/new.paths"
  (cd "$TEMPLATE" && git hash-object --no-filters -- "${paths[@]}") > "$work/new.shas"
  paste "$work/new.paths" "$work/new.shas" > "$work/new"
fi
user_paths=()
while IFS= read -r p; do
  [ -n "$p" ] && [ -f "cortex/$p" ] && user_paths+=("cortex/$p")
done <<<"$(cut -f1 "$work/base" "$work/new" | LC_ALL=C sort -u)"
: > "$work/user"
if [ "${#user_paths[@]}" -gt 0 ]; then
  printf '%s\n' "${user_paths[@]#cortex/}" > "$work/user.paths"
  git hash-object -- "${user_paths[@]}" > "$work/user.shas"
  paste "$work/user.paths" "$work/user.shas" > "$work/user"
fi
# "<path> <base sha> <new sha> <user sha>", "-" for a missing side
table="$(awk -F'\t' '
  FILENAME == ARGV[1] { b[$1] = $2; all[$1] = 1; next }
  FILENAME == ARGV[2] { n[$1] = $2; all[$1] = 1; next }
  { u[$1] = $2 }
  END { for (p in all) if (p != "config")
          print p "\t" (p in b ? b[p] : "-") "\t" (p in n ? n[p] : "-") "\t" (p in u ? u[p] : "-") }' \
  "$work/base" "$work/new" "$work/user" | LC_ALL=C sort)"

# merge3 USER BASE NEW LABEL : git merge-file into USER; 0 clean, 1 conflicts.
# A CRLF user file (a checkout's line endings) is merged as LF and restored.
merge3() {
  local u="$1" b="$2" n="$3" label="$4" crlf=0 rc
  if grep -qU "$CR$" "$u" && ! grep -qU "$CR$" "$n"; then
    crlf=1
    tr -d '\r' < "$u" > "$work/u.lf"
    cp "$work/u.lf" "$u"
  fi
  set +e
  git merge-file -L "$label (yours)" -L "$label (cortex $installed)" -L "$label (cortex $version)" "$u" "$b" "$n" >/dev/null 2>&1
  rc=$?
  set -e
  if [ "$crlf" = 1 ]; then
    awk -v BINMODE=3 '{ print $0 "\r" }' "$u" > "$work/u.crlf"
    cp "$work/u.crlf" "$u"
  fi
  [ "$rc" -eq 0 ] && return 0
  return 1
}

# upgrade_one DEST BASE-SHA NEW-FILE USER-SHA NEW-SHA BASE-READER... : one
# file's three-way upgrade (install step 3; an empty sha is a missing side);
# BASE-READER prints the base when a merge needs it
upgrade_one() {
  local dest="$1" bsha="$2" nfile="$3" usha="$4" nsha="$5"
  shift 5
  if [ -n "$bsha" ] && [ -n "$nsha" ]; then
    if [ -z "$usha" ]; then
      [ "$bsha" = "$nsha" ] || echo "deleted $dest (changed upstream)"
    elif [ "$usha" = "$nsha" ]; then
      echo "unchanged $dest"
    elif [ "$usha" = "$bsha" ]; then
      cp "$nfile" "$dest"; echo "replaced $dest"; replaced=$((replaced + 1))
    elif [ "$bsha" = "$nsha" ]; then
      echo "kept $dest (edited)"
    else
      "$@" > "$work/merge.base"
      if merge3 "$dest" "$work/merge.base" "$nfile" "$dest"; then
        echo "merged $dest"; merged=$((merged + 1))
      else
        echo "conflict $dest"; conflicts=$((conflicts + 1))
      fi
    fi
  elif [ -n "$nsha" ]; then
    if [ -z "$usha" ]; then
      case "$dest" in */*) mkdir -p "${dest%/*}" ;; esac
      cp "$nfile" "$dest"; echo "created $dest"
    elif [ "$usha" = "$nsha" ]; then
      echo "unchanged $dest"
    else
      : > "$work/merge.base"
      merge3 "$dest" "$work/merge.base" "$nfile" "$dest" || true
      echo "conflict $dest"; conflicts=$((conflicts + 1))
    fi
  elif [ -n "$usha" ]; then
    if [ "$usha" = "$bsha" ]; then
      rm -f "$dest"; rmdir_up "$dest"; echo "removed $dest"
    else
      echo "kept $dest (removed upstream, edited)"
    fi
  fi
  case "$dest" in cortex/bin/*.sh) [ ! -f "$dest" ] || scripts+=("$dest") ;; esac
}

while IFS="$TAB" read -r p bsha nsha usha; do
  [ -n "$p" ] || continue
  [ "$bsha" != - ] || bsha=""
  [ "$nsha" != - ] || nsha=""
  [ "$usha" != - ] || usha=""
  upgrade_one "cortex/$p" "$bsha" "$TEMPLATE/$p" "$usha" "$nsha" git -C "$CORTEX_ROOT" cat-file blob "$bsha"
done <<<"$table"

# The design rules: the same three-way merge, from docs/01-design-rules.md.
rules_base="$(git -C "$CORTEX_ROOT" rev-parse --verify --quiet "$installed_commit:docs/01-design-rules.md" || true)"
rules_new="$(git hash-object --no-filters -- "$RULES_SRC")"
rules_user=""
[ ! -f cortex/design-rules.md ] || rules_user="$(git hash-object -- cortex/design-rules.md)"
upgrade_one cortex/design-rules.md "$rules_base" "$RULES_SRC" "$rules_user" "$rules_new" git -C "$CORTEX_ROOT" cat-file blob "$rules_base"

# The root agents block: merged like a file, its content as the file (D2).
git -C "$CORTEX_ROOT" show "$installed_commit:template/blocks/AGENTS.md" > "$work/block.base" 2>/dev/null || : > "$work/block.base"
if [ "$(block_count AGENTS.md agents)" -eq 0 ]; then
  sep="$(block_insert AGENTS.md agents "$BLOCK_SRC")"
  fp_drop block AGENTS.md agents
  fp_add block AGENTS.md agents "$(block_sha AGENTS.md agents)" "$sep"
  echo "block AGENTS.md agents"
else
  block_content AGENTS.md agents | tr -d '\r' > "$work/block.user"
  if cmp -s "$work/block.user" "$BLOCK_SRC"; then
    echo "unchanged AGENTS.md"
  else
    if cmp -s "$work/block.user" "$work/block.base"; then
      cp "$BLOCK_SRC" "$work/block.result"
      block_ok=0
    elif cmp -s "$work/block.base" "$BLOCK_SRC"; then
      cp "$work/block.user" "$work/block.result"
      block_ok=0
    else
      cp "$work/block.user" "$work/block.result"
      if merge3 "$work/block.result" "$work/block.base" "$BLOCK_SRC" "AGENTS.md"; then block_ok=0; else block_ok=1; fi
    fi
    if cmp -s "$work/block.user" "$work/block.result"; then
      echo "kept AGENTS.md (edited)"
    else
      block_set AGENTS.md agents "$work/block.result"
      if [ "$block_ok" = 0 ]; then
        echo "block AGENTS.md agents"
      else
        echo "conflict AGENTS.md"; conflicts=$((conflicts + 1))
      fi
    fi
  fi
  rec="$(fp_match block AGENTS.md agents | sed -n 1p)"
  sep="$(fp_field "$rec" 5)"
  fp_drop block AGENTS.md agents
  fp_add block AGENTS.md agents "$(block_sha AGENTS.md agents)" "${sep:-1}"
fi
if [ -n "$(fp_match created AGENTS.md)" ]; then
  fp_drop created AGENTS.md
  fp_add created AGENTS.md "$(file_sha AGENTS.md)"
fi
fp_save
[ "${#scripts[@]}" -eq 0 ] || chmod +x "${scripts[@]}"

# The new version is in place: record it before adapt.sh, so the next
# upgrade's base matches the files even if adapt.sh stops on something.
printf '%s\n%s\n' "$version" "$commit" > cortex/version
filemode_note
run_adapt

# Keys the new version's config added: cortex/config is the project's (D12),
# so a new key is printed with its default instead of written.
while IFS= read -r key; do
  [ -n "$key" ] || continue
  grep -q "^[[:space:]]*$key[[:space:]]*=" cortex/config 2>/dev/null && continue
  echo "config $key=$(config_value "$key" < "$TEMPLATE/config")"
done <<<"$(tr -d '\r' < "$TEMPLATE/config" | awk -F'=' '/^[[:space:]]*#/ || index($0, "=") == 0 { next } { k = $1; gsub(/[[:space:]]/, "", k); if (k != "") print k }')"

# The CHANGELOG's notes for installed repositories, for every version passed:
# above the installed one, up to this one (A9).
if [ -f "$CORTEX_ROOT/CHANGELOG.md" ]; then
  tr -d '\r' < "$CORTEX_ROOT/CHANGELOG.md" | awk -v from="$installed" -v to="$version" "$VERCMP_AWK"'
    /^## / { v = $2; take = (vcmp(v, from) > 0 && vcmp(v, to) <= 0); inp = 0; next }
    take && /^\*\*For installed repositories:\*\*/ { inp = 1; print "notes for " v ":" }
    inp && /^[[:space:]]*$/ { inp = 0 }
    inp { print "  " $0 }'
fi

echo "upgrade $installed -> $version: $replaced replaced, $merged merged, $conflicts conflicts"
if [ "$conflicts" -gt 0 ]; then
  echo "resolve the conflict markers above, then run: bash cortex/bin/check.sh (C14 fails until they are gone)" >&2
  exit 1
fi
[ "$adapt_status" -eq 0 ] || exit 1
exit 0
