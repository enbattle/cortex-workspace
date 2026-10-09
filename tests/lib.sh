#!/usr/bin/env bash
# Tiny assertion library for the cortex script test suites.
# Source it from a *.test.sh file:  . "$(dirname "$0")/lib.sh"
# Portable across Git Bash (Windows) and bash on Linux; git + POSIX tools only.

set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d)"
RESULTS="$TEST_TMP/.results"
: > "$RESULTS"
CURRENT_CASE="(setup)"

cleanup_test_tmp() { rm -rf "$TEST_TMP"; }
trap cleanup_test_tmp EXIT

# ---- recording --------------------------------------------------------------

pass() { echo "P" >> "$RESULTS"; }
fail() {
  echo "F" >> "$RESULTS"
  printf '  FAIL [%s] %s\n' "$CURRENT_CASE" "$1" >&2
}

# ---- running commands ---------------------------------------------------------

# run CMD...  -> sets OUT (stdout), ERR (stderr), ALL (both), CODE (exit status)
run() {
  local errf="$TEST_TMP/.stderr.$$"
  set +e
  OUT="$("$@" 2>"$errf")"
  CODE=$?
  set -e
  ERR="$(cat "$errf" 2>/dev/null || true)"
  rm -f "$errf"
  ALL="$OUT"$'\n'"$ERR"
}

# ---- assertions ----------------------------------------------------------------

assert_exit() { # expected actual msg
  if [ "$1" = "$2" ]; then pass; else fail "$3 (expected exit $1, got $2)"; show_output; fi
}

assert_contains() { # haystack needle msg
  if grep -qF -- "$2" <<<"$1"; then pass; else fail "$3 (missing: '$2')"; show_output; fi
}

assert_not_contains() { # haystack needle msg
  if grep -qF -- "$2" <<<"$1"; then fail "$3 (unexpected: '$2')"; show_output; else pass; fi
}

assert_line() { # haystack exact-line msg
  if grep -qxF -- "$2" <<<"$1"; then pass; else fail "$3 (missing line: '$2')"; show_output; fi
}

assert_file_exists() { # path msg
  if [ -f "$1" ]; then pass; else fail "$2 (no file: $1)"; fi
}

assert_file_absent() { # path msg
  if [ -e "$1" ]; then fail "$2 (should not exist: $1)"; else pass; fi
}

assert_file_contains() { # path needle msg
  if [ -f "$1" ] && grep -qF -- "$2" "$1"; then pass; else fail "$3 ($1 lacks '$2')"; fi
}

assert_file_not_contains() { # path needle msg
  if [ -f "$1" ] && grep -qF -- "$2" "$1"; then fail "$3 ($1 contains '$2')"; else pass; fi
}

assert_same_file() { # a b msg
  if [ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2"; then pass; else fail "$3 ($1 vs $2 differ)"; fi
}

assert_true() { # msg cmd...
  local msg="$1"; shift
  if "$@"; then pass; else fail "$msg"; fi
}

show_output() {
  {
    echo "    --- stdout ---"; printf '%s\n' "${OUT:-}" | sed 's/^/    /'
    echo "    --- stderr ---"; printf '%s\n' "${ERR:-}" | sed 's/^/    /'
  } >&2
}

# ---- cases and summary --------------------------------------------------------

# run_case NAME FUNC : runs FUNC in a subshell (cwd and set -e isolated); an
# aborted case (unexpected error) counts as a failure.
run_case() {
  local name="$1" fn="$2" rc
  CURRENT_CASE="$name"
  echo "- $name"
  set +e
  ( set -e; CURRENT_CASE="$name"; "$fn" )
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then fail "case aborted with status $rc"; fi
}

summary() {
  local p f
  p=$(grep -c '^P$' "$RESULTS" || true)
  f=$(grep -c '^F$' "$RESULTS" || true)
  echo "$(basename "$0"): $p passed, $f failed"
  [ "$f" -eq 0 ]
}

# ---- fixtures -------------------------------------------------------------------

# new_git_repo -> prints path of a fresh git repo with a local identity
new_git_repo() {
  local d
  d="$(mktemp -d "$TEST_TMP/repo.XXXXXX")"
  git -C "$d" init -q
  git -C "$d" config user.name t
  git -C "$d" config user.email t@t
  git -C "$d" config core.autocrlf false
  git -C "$d" config commit.gpgsign false
  printf '%s\n' "$d"
}

# The installer, run from this cortex checkout (3.0.0 spec, "Layouts").
CORTEX_INSTALL="$ROOT/bin/install.sh"

# fresh_install -> prints path of a fresh git repo with the template installed
#
# install.sh runs once per suite, into a cached repository; every call then
# gets its own copy of that cache. A copy is byte-for-byte what a fresh
# install produces (files, modes, .git), and one `cp` replaces the dozens of
# processes an install spawns per file, which dominated the suite's run time
# on Windows. install.test.sh still calls install.sh directly where install
# behavior is what's under test.
fresh_install() {
  local cache="$TEST_TMP/.installed-cache" d
  if [ ! -d "$cache/.git" ]; then
    d="$(new_git_repo)"
    if ! "$CORTEX_INSTALL" "$d" >/dev/null 2>"$TEST_TMP/.install.err"; then
      echo "install.sh failed for $d:" >&2
      sed 's/^/    /' "$TEST_TMP/.install.err" >&2
      return 1
    fi
    mv "$d" "$cache"
  fi
  d="$(mktemp -d "$TEST_TMP/repo.XXXXXX")"
  cp -Rp "$cache/." "$d/"
  printf '%s\n' "$d"
}

# filter_file FILE CMD... : replace FILE with CMD's output on FILE (no sed -i)
filter_file() {
  local f="$1"; shift
  "$@" < "$f" > "$f.tmp.$$"
  mv "$f.tmp.$$" "$f"
}

# set_config FILE KEY VALUE : replace the KEY= line, or append it
set_config() {
  local f="$1" k="$2" v="$3"
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || : > "$f"
  if grep -q "^[[:space:]]*${k}[[:space:]]*=" "$f"; then
    filter_file "$f" awk -v k="$k" -v v="$v" '
      $0 ~ "^[[:space:]]*" k "[[:space:]]*=" { print k "=" v; next } { print }'
  else
    append "$f" "$k=$v"
  fi
}

# first_file DIR NAME-GLOB -> first matching regular file (sorted), or nothing
first_file() {
  [ -d "$1" ] || return 0
  find "$1" -type f -name "$2" | LC_ALL=C sort | sed -n 1p
}

# rel ROOTDIR PATH -> PATH relative to ROOTDIR
rel() { printf '%s\n' "${2#"$1"/}"; }

# append FILE TEXT : append a line, ensuring the file ends with a newline first
append() {
  if [ -s "$1" ] && [ -n "$(tail -c 1 "$1")" ]; then echo >> "$1"; fi
  printf '%s\n' "$2" >> "$1"
}

line_count() { wc -l < "$1" | tr -d ' '; }

commit_all() { # dir msg
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}

# lock_tests DIR FOLDER PATH... : the Amendment 2 lock layout. Commits
# everything as T, then FOLDER/lock.md naming T and listing each PATH, as
# its own commit L.
lock_tests() {
  local d="$1" f="$2" sha p; shift 2
  commit_all "$d" "add tests for $f"
  sha="$(git -C "$d" rev-parse HEAD)"
  mkdir -p "$d/$f"
  {
    printf 'Tests-locked-at: %s\n\n## Locked tests\n\n' "$sha"
    for p in "$@"; do printf -- '- %s\n' "$p"; done
  } > "$d/$f/lock.md"
  commit_all "$d" "lock tests for $f"
}

# ---- counting process starts (spec Amendments 5 and 7) ----------------------------

# make_shims DIR LOG CMD... : one counting shim per CMD in DIR; each appends
# its own name to LOG, then execs the real command (resolved now, before DIR
# is on PATH, so a shim never calls itself)
make_shims() {
  local dir="$1" log="$2" c real; shift 2
  mkdir -p "$dir"
  for c in "$@"; do
    real="$(command -v "$c")" || { echo "no real $c" >&2; return 1; }
    case "$real" in /*) ;; *) echo "$c is not an external command: $real" >&2; return 1 ;; esac
    {
      printf '#!/usr/bin/env bash\n'
      printf 'echo %q >> %q\n' "$c" "$log"
      printf 'exec %q "$@"\n' "$real"
    } > "$dir/$c"
    chmod +x "$dir/$c"
  done
}

# count_calls LOG CMD -> number of times CMD was logged
count_calls() {
  if [ -f "$1" ]; then grep -cxF -- "$2" "$1" || true; else echo 0; fi
}

# ---- config variations (spec Amendment 6) ----------------------------------------

# config_lines FILE KEY LINE... : drop every KEY= line, then append LINEs
config_lines() {
  local f="$1" k="$2" l; shift 2
  filter_file "$f" awk -v k="$k" '!($0 ~ "^[[:space:]]*" k "[[:space:]]*=")'
  for l in "$@"; do
    append "$f" "$l"
    grep -qxF -- "$l" "$f" || { fail "fixture: line not planted: $l"; return 1; }
  done
}

# config_variant FILE KIND KEY REAL OTHER : write KEY per one AC32 variation;
# a correct parser reads REAL, never OTHER
config_variant() {
  local f="$1" kind="$2" k="$3" real="$4" other="$5"
  case "$kind" in
    spaced) config_lines "$f" "$k" "$k = $real" ;;
    comment) config_lines "$f" "$k" "# $k=$other" "$k=$real" ;;
    no-equals) config_lines "$f" "$k" "$k $other" "$k=$real" ;;
    twice) config_lines "$f" "$k" "$k=$real" "$k=$other" ;;
    *) fail "unknown variant $kind"; return 1 ;;
  esac
}

# write_stub_parser DIR : an installed _config.sh whose config_value prints nothing
write_stub_parser() {
  mkdir -p "$1/cortex/bin"
  printf '%s\n' '# stub: config_value reads its input and prints nothing' \
    'config_value() { cat > /dev/null; }' > "$1/cortex/bin/_config.sh"
}

# ---- filled baseline (spec Amendment 1, A2; 3.0.0 D16) ----------------------------

# fill_install DIR : make an install a "filled" baseline that check.sh accepts
# under A2: the five required cortex/config keys set to harmless
# non-placeholder values (D16: PROJECT_NAME is gone), CI=none (D16's default,
# written out so the baseline does not depend on the template's line), and no
# TODO left in cortex/AGENTS.md (C12). Verifies the fill took effect; returns
# 1 (and records a failure) if it did not.
FILL_KEYS="BUILD_CMD TEST_CMD LINT_CMD TEST_GLOBS TOOLS"
fill_install() {
  local d="$1" k
  local cfg="$d/cortex/config" router="$d/cortex/AGENTS.md"
  set_config "$cfg" BUILD_CMD "true"
  set_config "$cfg" TEST_CMD "true"
  set_config "$cfg" LINT_CMD "true"
  set_config "$cfg" TEST_GLOBS "*.test.sh"
  set_config "$cfg" TOOLS "claude"
  set_config "$cfg" CI "none"
  for k in $FILL_KEYS CI; do
    if ! grep -q "^${k}=[^<[:space:]]" "$cfg"; then
      fail "fill_install: $k not filled in $cfg"; return 1
    fi
  done
  if [ -f "$router" ]; then
    filter_file "$router" awk '!/TODO/'
    if grep -q 'TODO' "$router"; then
      fail "fill_install: TODO still in cortex/AGENTS.md"; return 1
    fi
    if [ ! -s "$router" ]; then
      fail "fill_install: cortex/AGENTS.md empty after removing TODO lines"; return 1
    fi
  fi
}

# filled_install -> path of a fresh install, filled as above
filled_install() {
  local d
  d="$(fresh_install)" || return 1
  fill_install "$d" || return 1
  printf '%s\n' "$d"
}

# ---- 3.0.0 layout helpers (spec 2026-10-05-v3-removable-layout) --------------------

# in_repo DIR CMD... : run CMD (via `run`) with cwd = DIR
in_repo() {
  local d="$1"; shift
  run bash -c 'd="$1"; shift; cd "$d" && "$@"' _ "$d" "$@"
}

# cortex_script DIR NAME [ARGS...] : run `bash cortex/bin/NAME.sh ARGS` in DIR
cortex_script() {
  local d="$1" n="$2"; shift 2
  in_repo "$d" bash "cortex/bin/$n.sh" "$@"
}

# adapt_quiet DIR : run DIR's adapt.sh, output discarded; returns its status
adapt_quiet() {
  (cd "$1" && bash cortex/bin/adapt.sh) >/dev/null 2>&1
}

# adapted_install -> a filled install (TOOLS=claude, CI=none) after adapt.sh ran
adapted_install() {
  local d
  d="$(filled_install)" || return 1
  adapt_quiet "$d" || { fail "adapted_install: adapt.sh failed in $d"; return 1; }
  printf '%s\n' "$d"
}

# cortex_clone [VERSION] -> path of a throwaway cortex source repository: a
# copy of this checkout's bin/, template/, docs/01-design-rules.md, VERSION
# (replaced by VERSION if given) and CHANGELOG.md, committed, so install.sh
# can record a commit (D3) and read earlier template versions from history.
# Edit it, then commit_all, to build a later version.
cortex_clone() {
  local c
  c="$(new_git_repo)"
  cp -Rp "$ROOT/bin" "$c/bin"
  cp -Rp "$ROOT/template" "$c/template"
  mkdir -p "$c/docs"
  cp -p "$ROOT/docs/01-design-rules.md" "$c/docs/01-design-rules.md"
  if [ -n "${1:-}" ]; then printf '%s\n' "$1" > "$c/VERSION"; else cp -p "$ROOT/VERSION" "$c/VERSION"; fi
  [ ! -f "$ROOT/CHANGELOG.md" ] || cp -p "$ROOT/CHANGELOG.md" "$c/CHANGELOG.md"
  commit_all "$c" "cortex $(tr -d '\r\n' < "$c/VERSION")"
  printf '%s\n' "$c"
}

# The footprint's first line (spec "The footprint record").
FOOTPRINT_HEADER="# cortex footprint 1"

# footprint_records DIR -> DIR's cortex/footprint without comment lines
footprint_records() {
  [ -f "$1/cortex/footprint" ] || return 0
  grep -v '^#' "$1/cortex/footprint" || true
}

# has_record DIR KIND PATH [FIELD3] : a KIND record for PATH exists (and, if
# given, its third field equals FIELD3: a block id or an entry's line)
has_record() {
  local d="$1"
  # ENVIRON, not -v: awk -v would expand backslashes in an entry's line
  footprint_records "$d" | HR_K="$2" HR_P="$3" HR_F="${4-}" HR_HF="${4+x}" awk -F'\t' '
    $1 == ENVIRON["HR_K"] && $2 == ENVIRON["HR_P"] &&
      (ENVIRON["HR_HF"] == "" || $3 == ENVIRON["HR_F"]) { found = 1 }
    END { exit found ? 0 : 1 }'
}

# block_begin FILE ID / block_end FILE ID -> the marker lines for FILE (#-style
# for CODEOWNERS, HTML comments otherwise; spec "Marked blocks")
block_begin() {
  case "${1##*/}" in CODEOWNERS) printf '# cortex:begin %s\n' "$2" ;; *) printf '<!-- cortex:begin %s -->\n' "$2" ;; esac
}
block_end() {
  case "${1##*/}" in CODEOWNERS) printf '# cortex:end %s\n' "$2" ;; *) printf '<!-- cortex:end %s -->\n' "$2" ;; esac
}

# block_count FILE ID -> how many begin markers for ID are in FILE
block_count() {
  if [ -f "$1" ]; then grep -cxF -- "$(block_begin "$1" "$2")" "$1" || true; else echo 0; fi
}

# block_content FILE ID -> the lines between ID's markers (CRs kept)
block_content() {
  [ -f "$1" ] || return 0
  awk -v b="$(block_begin "$1" "$2")" -v e="$(block_end "$1" "$2")" '
    { l = $0; sub(/\r$/, "", l) }
    l == e { inb = 0 }
    inb { print }
    l == b { inb = 1 }' "$1"
}

# block_body FILE ID -> block_content without the blank lines directly inside
# the markers (Amendment 3, F1: they are the block's framing, not its
# content); CRs kept
block_body() {
  block_content "$1" "$2" | awk '
    { a[NR] = $0; l = $0; sub(/\r$/, "", l); blank[NR] = (l == "") }
    END {
      s = 1; while (s <= NR && blank[s]) s++
      e = NR; while (e >= s && blank[e]) e--
      for (i = s; i <= e; i++) print a[i]
    }'
}

# block_framed FILE ID : ID's block has exactly one blank line after its
# begin marker and one before its end marker, around non-blank content (F1)
block_framed() {
  block_content "$1" "$2" | awk '
    { l = $0; sub(/\r$/, "", l); b[NR] = (l == "") }
    END { exit (NR >= 3 && b[1] && !b[2] && !b[NR - 1] && b[NR]) ? 0 : 1 }'
}

# space_block FILE ID : a blank line after ID's begin marker and after every
# line inside the block: a formatter's blank lines, nothing else changed (F1)
space_block() {
  filter_file "$1" awk -v b="$(block_begin "$1" "$2")" -v e="$(block_end "$1" "$2")" '
    { l = $0; sub(/\r$/, "", l) }
    l == e { inb = 0 }
    { print }
    inb || l == b { print "" }
    l == b { inb = 1 }'
}

# outside_blocks FILE -> FILE's lines outside every cortex block (markers dropped)
outside_blocks() {
  [ -f "$1" ] || return 0
  awk '
    { l = $0; sub(/\r$/, "", l) }
    l ~ /^(<!-- |# )cortex:begin / { inb = 1; next }
    l ~ /^(<!-- |# )cortex:end / { inb = 0; next }
    !inb { print }' "$1"
}

# set_block FILE ID TEXT : replace the content between ID's markers with TEXT
# (one or more lines); the markers and everything outside them are kept
set_block() {
  local f="$1" id="$2" t="$TEST_TMP/.block.$$"
  printf '%s\n' "$3" > "$t"
  filter_file "$f" awk -v b="$(block_begin "$f" "$id")" -v e="$(block_end "$f" "$id")" -v t="$t" '
    { l = $0; sub(/\r$/, "", l) }
    l == b { print; while ((getline x < t) > 0) print x; skip = 1; next }
    l == e { skip = 0 }
    !skip { print }'
  rm -f "$t"
}

# file_starts_with FILE PREFIX-FILE : FILE's first bytes are PREFIX-FILE's bytes
file_starts_with() {
  local n
  [ -f "$1" ] && [ -f "$2" ] || return 1
  n="$(wc -c < "$2" | tr -d ' ')"
  [ "$n" -eq 0 ] || head -c "$n" "$1" | cmp -s - "$2"
}

# tree_snapshot DIR -> one line per directory ("d <path>/") and file
# ("f <path> <blob sha>") outside .git/, sorted: equal snapshots mean equal
# trees, byte for byte, including empty directories
tree_snapshot() {
  (
    cd "$1" || exit 1
    find . -mindepth 1 -path ./.git -prune -o -type d -print | sed 's|^\./||; s|^|d |; s|$|/|'
    find . -path ./.git -prune -o -type f -print | sed 's|^\./||' | LC_ALL=C sort > "$TEST_TMP/.snap.$$"
    if [ -s "$TEST_TMP/.snap.$$" ]; then
      tr '\n' '\0' < "$TEST_TMP/.snap.$$" | xargs -0 git hash-object --no-filters -- |
        paste "$TEST_TMP/.snap.$$" - | sed 's|^|f |; s|\t| |'
    fi
    rm -f "$TEST_TMP/.snap.$$"
  ) | LC_ALL=C sort
}

# ---- seeded projects and settings entries (3.0.0 criteria 2, 3, 8, 12, 13, 40) ----

# seed_rule -> one of cortex's settings rules, byte for byte as the Claude
# Code adapter source holds it (D11: an entry is matched as an exact line)
seed_rule() {
  local src="$ROOT/template/cortex/adapters/claude-code/.claude/settings.json" l=""
  [ ! -f "$src" ] || l="$(grep -m1 -F 'Bash(git status' "$src" || true)"
  if [ -n "$l" ]; then printf '%s\n' "$l"; else printf '%s\n' '      "Bash(git status*)",'; fi
}

# seed_project DIR : write the project's own AGENTS.md, CLAUDE.md,
# .gitattributes, .github/CODEOWNERS, .claude/settings.json (holding
# seed_rule) and README.md into DIR (criterion 2's files); none names cortex/
seed_project() {
  local d="$1"
  mkdir -p "$d/.github" "$d/.claude"
  printf '# Project agents\n\nRun `make test` before pushing.\n' > "$d/AGENTS.md"
  printf '# Claude notes\n\nPrefer small diffs.\n' > "$d/CLAUDE.md"
  printf '*.png binary\ndocs/** linguist-documentation\n' > "$d/.gitattributes"
  printf '* @owner\n/docs/ @writers\n' > "$d/.github/CODEOWNERS"
  {
    printf '{\n  "permissions": {\n    "allow": [\n'
    seed_rule
    printf '      "Bash(make test)"\n    ]\n  }\n}\n'
  } > "$d/.claude/settings.json"
  printf '# Demo\n' > "$d/README.md"
}

# seeded_repo -> a git repo holding seed_project's files, committed
seeded_repo() {
  local d
  d="$(new_git_repo)" || return 1
  seed_project "$d"
  commit_all "$d" "the project"
  printf '%s\n' "$d"
}

# install_adapt_github DIR : install.sh into DIR, fill it (fill_install:
# TOOLS=claude), set CI=github and CODE_OWNERS=@t (criterion 2), run adapt.sh;
# output discarded. Returns 1 (recording a failure) if a step fails.
install_adapt_github() {
  local d="$1"
  "$CORTEX_INSTALL" "$d" >/dev/null 2>&1 || { fail "install_adapt_github: install.sh failed in $d"; return 1; }
  fill_install "$d" || return 1
  set_config "$d/cortex/config" CI github
  set_config "$d/cortex/config" CODE_OWNERS "@t"
  adapt_quiet "$d" || { fail "install_adapt_github: adapt.sh failed in $d"; return 1; }
}

# merge_entries DIR [PATH] : do the merge adapt.sh asks for (Q1): insert
# every entry line recorded for PATH (default .claude/settings.json) into it,
# after its first line holding "[" (at the end if none)
merge_entries() {
  local d="$1" p="${2:-.claude/settings.json}" t="$TEST_TMP/.entries.$$"
  footprint_records "$d" | ME_P="$p" awk -F'\t' '
    $1 == "entry" && $2 == ENVIRON["ME_P"] { sub(/^[^\t]*\t[^\t]*\t/, ""); print }' > "$t"
  if [ -s "$t" ]; then
    filter_file "$d/$p" awk -v t="$t" '
      { print }
      !done && /\[/ { while ((getline x < t) > 0) print x; done = 1 }
      END { if (!done) while ((getline x < t) > 0) print x }'
  fi
  rm -f "$t"
}

# entry_count DIR [PATH] -> number of entry records for PATH
entry_count() {
  footprint_records "$1" | EC_P="${2:-.claude/settings.json}" awk -F'\t' '
    $1 == "entry" && $2 == ENVIRON["EC_P"] { n++ } END { print n + 0 }'
}

# has_line_starting TEXT PREFIX : some line of TEXT starts with PREFIX
has_line_starting() {
  printf '%s\n' "$1" | HL_P="$2" awk 'index($0, ENVIRON["HL_P"]) == 1 { f = 1 } END { exit f ? 0 : 1 }'
}
