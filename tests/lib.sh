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

# fresh_install -> prints path of a fresh git repo with the template installed
fresh_install() {
  local d
  d="$(new_git_repo)"
  if ! "$ROOT/scripts/install.sh" "$d" >/dev/null 2>"$TEST_TMP/.install.err"; then
    echo "install.sh failed for $d:" >&2
    sed 's/^/    /' "$TEST_TMP/.install.err" >&2
    return 1
  fi
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
  if grep -q "^[[:space:]]*$k[[:space:]]*=" "$f"; then
    filter_file "$f" awk -v k="$k" -v v="$v" '
      $0 ~ "^[[:space:]]*" k "[[:space:]]*=" { print k "=" v; next } { print }'
  else
    # make sure the file ends in a newline before appending
    if [ -s "$f" ] && [ -n "$(tail -c 1 "$f")" ]; then echo >> "$f"; fi
    printf '%s=%s\n' "$k" "$v" >> "$f"
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
