# shellcheck shell=bash
# The footprint record and marked blocks (spec 2026-10-05-v3-removable-layout:
# "The footprint record", "Marked blocks", D11, Amendment 1 A6 and A7).
# Sourced, never run, by the scripts next to it and by bin/install.sh, so
# every script reads and writes them one way. Paths are relative to the
# repository root, which the sourcing script has made the working directory.
#
# cortex/footprint: the format line, then one tab-separated record per line,
# sorted with LC_ALL=C sort:
#   created <path> <sha>                 a file cortex wrote where none was
#   block   <path> <id> <sha> <sep>      a marked block cortex inserted
#   entry   <path> <line>                a line to merge into a file by hand
# A sha is what `git hash-object` gives with the repository's own filters, so
# it is the blob git would store and doesn't change with a checkout's line
# endings. sep is what inserting the block added before it: 0 nothing, 1 a
# blank line, 2 a final newline and a blank line.

FP_FORMAT="# cortex footprint 1"
FP_FILE=cortex/footprint
FP_RECORDS=""      # the loaded records, one per line
FP_BAD_FORMAT=""   # the first line of a footprint in an unknown format
FP_REMOVED=0       # counts kept by fp_remove_block and fp_remove_created
FP_KEPT=0
TAB="$(printf '\t')"
CR="$(printf '\r')"

# fp_load : read cortex/footprint into FP_RECORDS; returns 1 (FP_BAD_FORMAT
# set) when its first line is not FP_FORMAT. An absent footprint is empty.
fp_load() {
  local first=""
  FP_RECORDS=""
  FP_BAD_FORMAT=""
  [ -f "$FP_FILE" ] || return 0
  IFS= read -r first < "$FP_FILE" || true
  first="${first%"$CR"}"
  if [ "$first" != "$FP_FORMAT" ]; then
    FP_BAD_FORMAT="$first"
    return 1
  fi
  FP_RECORDS="$(tr -d '\r' < "$FP_FILE" | grep -v -e '^#' -e '^$' || true)"
}

# fp_save : write FP_RECORDS to cortex/footprint, sorted (A7)
fp_save() {
  {
    printf '%s\n' "$FP_FORMAT"
    [ -z "$FP_RECORDS" ] || printf '%s\n' "$FP_RECORDS" | LC_ALL=C sort -u
  } > "$FP_FILE.tmp"
  mv "$FP_FILE.tmp" "$FP_FILE"
}

# fp_match KIND [PATH [FIELD3]] -> the matching records
fp_match() {
  [ -n "$FP_RECORDS" ] || return 0
  printf '%s\n' "$FP_RECORDS" | FM_K="$1" FM_P="${2-}" FM_HP="${2+x}" FM_F="${3-}" FM_HF="${3+x}" awk -F'\t' '
    $1 == ENVIRON["FM_K"] && (ENVIRON["FM_HP"] == "" || $2 == ENVIRON["FM_P"]) &&
      (ENVIRON["FM_HF"] == "" || $3 == ENVIRON["FM_F"])'
}

# fp_drop KIND PATH [FIELD3] : forget the matching records
fp_drop() {
  [ -n "$FP_RECORDS" ] || return 0
  FP_RECORDS="$(printf '%s\n' "$FP_RECORDS" | FM_K="$1" FM_P="$2" FM_F="${3-}" FM_HF="${3+x}" awk -F'\t' '
    !($1 == ENVIRON["FM_K"] && $2 == ENVIRON["FM_P"] && (ENVIRON["FM_HF"] == "" || $3 == ENVIRON["FM_F"]))')"
}

# fp_add FIELD... : add a record (one per path and kind, block id or entry line)
fp_add() {
  local rec="$1"
  shift
  while [ "$#" -gt 0 ]; do rec="$rec$TAB$1"; shift; done
  FP_RECORDS="${FP_RECORDS:+$FP_RECORDS
}$rec"
}

# fp_field RECORD N -> field N of a record
fp_field() { printf '%s\n' "$1" | cut -f "$2"; }

# file_sha PATH -> the blob git would store for PATH (its filters applied)
file_sha() { git hash-object -- "$1"; }

# ---- marked blocks ------------------------------------------------------------

# marker_begin PATH ID / marker_end PATH ID -> the marker lines: # comments in
# CODEOWNERS, which has no HTML comments; HTML comments everywhere else
marker_begin() {
  case "${1##*/}" in CODEOWNERS) printf '# cortex:begin %s' "$2" ;; *) printf '<!-- cortex:begin %s -->' "$2" ;; esac
}
marker_end() {
  case "${1##*/}" in CODEOWNERS) printf '# cortex:end %s' "$2" ;; *) printf '<!-- cortex:end %s -->' "$2" ;; esac
}

# block_content PATH ID -> the lines between the first ID block's markers
# (carriage returns kept, so a CRLF file's block hashes as written)
block_content() {
  [ -f "$1" ] || return 0
  awk -v BINMODE=3 -v b="$(marker_begin "$1" "$2")" -v e="$(marker_end "$1" "$2")" '
    { l = $0; sub(/\r$/, "", l) }
    inb && l == e { exit }
    inb { print }
    !inb && l == b { inb = 1 }' "$1"
}

# block_count PATH ID -> how many begin markers for ID the file holds
block_count() {
  if [ -f "$1" ]; then
    awk -v BINMODE=3 -v b="$(marker_begin "$1" "$2")" '{ l = $0; sub(/\r$/, "", l) } l == b { n++ } END { print n + 0 }' "$1"
  else
    echo 0
  fi
}

# block_sha PATH ID -> git hash-object of the block's lines (A7)
block_sha() { block_content "$1" "$2" | git hash-object --stdin --path="$1"; }

# file_cr PATH -> a carriage return if the file's first line ends in one
# (the file uses CRLF, and a block in it does too, D15), else nothing
file_cr() {
  [ -s "$1" ] || return 0
  if head -n 1 "$1" | grep -qU "$CR$"; then printf '%s' "$CR"; fi
}

# block_insert PATH ID SOURCE -> prints sep : append ID's block, holding
# SOURCE's lines, at the end of PATH (created if absent) after one blank line
block_insert() {
  local f="$1" id="$2" src="$3" sep cr
  cr="$(file_cr "$f")"
  if [ ! -s "$f" ]; then
    sep=0
  elif [ -z "$(tail -c 1 "$f")" ]; then
    sep=1
  else
    sep=2
  fi
  case "$f" in */*) [ -d "${f%/*}" ] || mkdir -p "${f%/*}" ;; esac
  {
    if [ "$sep" = 2 ]; then printf '%s\n' "$cr"; fi
    if [ "$sep" != 0 ]; then printf '%s\n' "$cr"; fi
    printf '%s%s\n' "$(marker_begin "$f" "$id")" "$cr"
    awk -v BINMODE=3 -v cr="$cr" '{ sub(/\r$/, ""); print $0 cr }' "$src"
    printf '%s%s\n' "$(marker_end "$f" "$id")" "$cr"
  } >> "$f"
  printf '%s' "$sep"
}

# block_set PATH ID SOURCE : replace the first ID block's lines with SOURCE's,
# in the file's line endings; the markers and everything outside stay
block_set() {
  local f="$1" id="$2" src="$3" nl=1
  [ -z "$(tail -c 1 "$f")" ] || nl=0
  awk -v BINMODE=3 -v b="$(marker_begin "$f" "$id")" -v e="$(marker_end "$f" "$id")" -v t="$src" -v nl="$nl" '
    { l = $0; cr = ""; if (sub(/\r$/, "", l)) cr = "\r" }
    !done && !skip && l == b {
      out[++n] = $0
      while ((getline x < t) > 0) { sub(/\r$/, "", x); out[++n] = x cr }
      skip = 1; next }
    skip && l == e { skip = 0; done = 1 }
    !skip { out[++n] = $0 }
    END { for (i = 1; i <= n; i++) printf "%s%s", out[i], (i < n || nl ? "\n" : "") }' "$f" > "$f.cortex-tmp"
  mv "$f.cortex-tmp" "$f"
}

# block_strip PATH ID SEP : remove the first ID block, its markers, and what
# inserting it added before it (A6), so the file is as it was before
block_strip() {
  local f="$1" id="$2" sep="$3" nl=1
  [ -z "$(tail -c 1 "$f")" ] || nl=0
  awk -v BINMODE=3 -v b="$(marker_begin "$f" "$id")" -v e="$(marker_end "$f" "$id")" -v sep="$sep" -v nl="$nl" '
    { line[NR] = $0 }
    END {
      n = NR; bi = 0; ei = 0
      for (i = 1; i <= n; i++) {
        l = line[i]; sub(/\r$/, "", l)
        if (!bi && l == b) bi = i
        else if (bi && !ei && l == e) ei = i
      }
      if (!bi || !ei) { for (i = 1; i <= n; i++) printf "%s%s", line[i], (i < n || nl ? "\n" : ""); exit }
      start = bi
      if (sep >= 1 && bi > 1) { l = line[bi - 1]; sub(/\r$/, "", l); if (l == "") start = bi - 1 }
      m = 0
      for (i = 1; i < start; i++) out[++m] = line[i]
      for (i = ei + 1; i <= n; i++) out[++m] = line[i]
      # A block at the end: the line before it ended in a newline, unless
      # inserting it added that newline (sep 2), which goes with the block.
      final = nl
      if (ei == n) {
        final = 1
        if (start == bi - 1 && sep == 2) { final = 0; if (m > 0) sub(/\r$/, "", out[m]) }
      }
      for (i = 1; i <= m; i++) printf "%s%s", out[i], (i < m || final ? "\n" : "")
    }' "$f" > "$f.cortex-tmp"
  mv "$f.cortex-tmp" "$f"
}

# rmdir_up PATH : remove the directories above PATH that are now empty
rmdir_up() {
  local d="$1"
  while :; do
    case "$d" in */*) d="${d%/*}" ;; *) return 0 ;; esac
    rmdir "$d" 2>/dev/null || return 0
  done
}

# ---- removal by the record (remove.sh step 4; adapt.sh for a dropped tool) ----

# fp_remove_block PATH ID : remove a recorded block and its record; an edited
# block is shown first. Prints A1's "removed block <path> <id>".
fp_remove_block() {
  local f="$1" id="$2" rec sha sep
  rec="$(fp_match block "$f" "$id" | sed -n 1p)"
  sha="$(fp_field "$rec" 4)"
  sep="$(fp_field "$rec" 5)"
  if [ -f "$f" ] && [ "$(block_count "$f" "$id")" -gt 0 ]; then
    if [ "$(block_sha "$f" "$id")" != "$sha" ]; then
      echo "note: the $id block in $f was edited after install; its content was:"
      block_content "$f" "$id" | tr -d '\r' | sed 's/^/  | /'
    fi
    block_strip "$f" "$id" "${sep:-1}"
    echo "removed block $f $id"
    FP_REMOVED=$((FP_REMOVED + 1))
  fi
  fp_drop block "$f" "$id"
}

# fp_remove_created PATH FORCE HELD : delete a file cortex created if it is as
# cortex left it, or FORCE is 1; otherwise keep it and say so. HELD is 1 for a
# file that held cortex's blocks (removed first): it is as cortex left it if
# only whitespace is left. Drops the record.
fp_remove_created() {
  local f="$1" force="$2" held="$3" rec sha
  rec="$(fp_match created "$f" | sed -n 1p)"
  sha="$(fp_field "$rec" 3)"
  fp_drop created "$f"
  [ -f "$f" ] || return 0
  if [ "$force" = 1 ] ||
    { [ "$held" = 1 ] && ! grep -q '[^[:space:]]' "$f"; } ||
    { [ "$held" != 1 ] && [ "$(file_sha "$f")" = "$sha" ]; }; then
    rm -f "$f"
    rmdir_up "$f"
    echo "removed $f"
    FP_REMOVED=$((FP_REMOVED + 1))
  else
    echo "kept $f (edited after install)"
    FP_KEPT=$((FP_KEPT + 1))
  fi
}

# fp_remove_path PATH FORCE : every record for PATH: its blocks, then the file
# if cortex created it; entries are listed for a person (D4)
fp_remove_path() {
  local f="$1" force="$2" blocks held=0 rec
  blocks="$(fp_match block "$f")"
  [ -z "$blocks" ] || held=1
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    fp_remove_block "$f" "$(fp_field "$rec" 3)"
  done <<<"$blocks"
  [ -z "$(fp_match created "$f")" ] || fp_remove_created "$f" "$force" "$held"
}
