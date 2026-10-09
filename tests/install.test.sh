#!/usr/bin/env bash
# Tests for bin/install.sh (spec: docs/specs/2026-09-23-v2-scripts.md,
# acceptance criteria 1-3, 13, 19, 30 and 31; layout, refusals and install
# steps 0-4 per docs/specs/2026-10-05-v3-removable-layout.md, whose criteria
# 1-3, 5, 7 and 32 and Amendment 1 (A1-A7) the "criterion" cases cover).
# Removal and upgrade live in remove.test.sh and upgrade.test.sh.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

INSTALL="$CORTEX_INSTALL"

# every file under template/cortex/, relative, sorted (includes dotfiles,
# .gitkeep); each is installed at cortex/<file> (3.0.0 "Layouts")
template_files() {
  [ -d "$ROOT/template/cortex" ] || { echo "template/cortex/ missing" >&2; return 1; }
  (cd "$ROOT/template/cortex" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
}

# has_line_re TEXT ERE : TEXT has a line matching ERE exactly
has_line_re() { grep -qxE -- "$2" <<<"$1"; }

# install step 1 prints "install: <n> files in cortex/, <c> created, <b>
# blocks" (Amendment 3, F4; was "install: <c> created, <b> blocks"); on an
# empty repository the one block is the root AGENTS.md's agents block
SUMMARY_RE='install: [0-9]+ files in cortex/, [0-9]+ created, 1 blocks'

this_version() { tr -d '\r\n' < "$ROOT/VERSION"; }
this_commit() { git -C "$ROOT" rev-parse HEAD; }

case_no_argument() {
  run "$INSTALL"
  assert_exit 2 "$CODE" "no argument exits 2"
  assert_true "usage goes to stderr" test -n "$ERR"
}

case_missing_dir() {
  run "$INSTALL" "$TEST_TMP/does-not-exist"
  assert_exit 2 "$CODE" "missing target exits 2"
  assert_true "error goes to stderr" test -n "$ERR"
}

case_non_git_dir() {
  local d; d="$(mktemp -d "$TEST_TMP/plain.XXXXXX")"
  # guard: make sure the temp dir is not itself inside some git work tree
  if git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "  (skip: temp dir is inside a git work tree)"; return 0
  fi
  run "$INSTALL" "$d"
  assert_exit 2 "$CODE" "non-git directory exits 2"
  assert_true "error goes to stderr" test -n "$ERR"
  assert_true "nothing written to non-git dir" test -z "$(ls -A "$d")"
}

case_fresh_install() {
  local d files n f
  d="$(new_git_repo)"
  files="$(template_files)"
  n=$(printf '%s\n' "$files" | grep -c . || true)
  assert_true "template has files" test "$n" -gt 0
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "fresh install exits 0"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    assert_same_file "$ROOT/template/cortex/$f" "$d/cortex/$f" "installed copy of cortex/$f is identical"
    assert_line "$OUT" "created cortex/$f" "reports created cortex/$f"
  done <<<"$files"
  assert_file_exists "$d/cortex/changes/archive/.gitkeep" ".gitkeep is installed"
  assert_file_exists "$d/cortex/config" "cortex/config is installed"
  # layout (spec "Layouts"): remove.sh joins the installed scripts
  for f in check.sh tests-locked.sh adapt.sh gates.sh ci-gates.sh remove.sh; do
    assert_true "cortex/bin/$f is executable" test -x "$d/cortex/bin/$f"
  done
  # Amendment 3 (C2): template CI workflow and ownership files
  for f in cortex/ci/github/cortex.yml cortex/ci/github/CODEOWNERS; do
    assert_file_exists "$ROOT/template/$f" "template ships $f (C2)"
    assert_same_file "$ROOT/template/$f" "$d/$f" "$f installed (C2)"
    assert_line "$OUT" "created $f" "reports created $f (C2)"
  done
  # D3: cortex/version holds two lines, the version and the commit installed
  # from (was: a byte copy of VERSION)
  assert_true "cortex/version line 1 is VERSION (D3)" \
    test "$(sed -n 1p "$d/cortex/version" 2>/dev/null)" = "$(this_version)"
  assert_true "cortex/version line 2 is the clone's full commit (D3)" \
    test "$(sed -n 2p "$d/cortex/version" 2>/dev/null)" = "$(this_commit)"
  assert_line "$OUT" "created cortex/version" "reports created cortex/version"
  assert_same_file "$ROOT/docs/01-design-rules.md" "$d/cortex/design-rules.md" "cortex/design-rules.md matches docs/01-design-rules.md (A5)"
  assert_line "$OUT" "created cortex/design-rules.md" "reports created cortex/design-rules.md (A5)"
  # install step 1: the summary is "install: <c> created, <b> blocks" (was:
  # "install: N created, 0 unchanged, 0 skipped")
  assert_true "summary line per install step 1" has_line_re "$OUT" "$SUMMARY_RE"
  # never runs git commands that write
  assert_true "no commit created" test -z "$(git -C "$d" rev-list --all 2>/dev/null)"
  assert_true "nothing staged" test -z "$(git -C "$d" ls-files)"
}

case_second_run_idempotent() {
  local d f before
  d="$(fresh_install)"
  before="$(tree_snapshot "$d")"
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "second run exits 0"
  assert_true "second run prints no created lines" test -z "$(grep '^created ' <<<"$OUT" || true)"
  # install step 2: same version and commit prints "unchanged" for everything
  # (was: assert_contains "0 created", the 2.x summary)
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    assert_line "$OUT" "unchanged cortex/$f" "cortex/$f reported unchanged (install step 2)"
  done <<<"$(template_files)"
  assert_line "$OUT" "unchanged cortex/version" "version reported unchanged"
  assert_line "$OUT" "unchanged AGENTS.md" "AGENTS.md reported unchanged"
  assert_line "$OUT" "unchanged cortex/design-rules.md" "design rules reported unchanged (A5)"
  # install step 2: no writes (was: the 2.x second-run summary line)
  assert_true "second run writes nothing (install step 2, criterion 4)" \
    test "$(tree_snapshot "$d")" = "$before"
}

case_existing_agents_gets_block() {
  # was "differing existing file is skipped": in 3.0.0 an existing AGENTS.md
  # gets the agents block appended (install step 1, D11, "Marked blocks")
  local d
  d="$(new_git_repo)"
  printf '# my own agents file\n' > "$d/AGENTS.md"
  cp "$d/AGENTS.md" "$TEST_TMP/agents.orig"
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "install over an existing AGENTS.md exits 0"
  # install step 1: block inserted (was: "skipped AGENTS.md (exists, differs)")
  assert_file_contains "$d/AGENTS.md" "<!-- cortex:begin agents -->" "existing AGENTS.md gets the agents block"
  assert_not_contains "$OUT" "created AGENTS.md" "AGENTS.md not reported created"
  # D11: the project's content stays (was: the whole file untouched)
  assert_true "existing AGENTS.md content kept ahead of the block (D11)" \
    file_starts_with "$d/AGENTS.md" "$TEST_TMP/agents.orig"
  # "Marked blocks": appended at the end after one blank line, content from
  # template/blocks/AGENTS.md (was: the summary counting one skip); Amendment
  # 3, F1: one blank line after the begin marker and one before the end
  # marker (was: the content right between the markers)
  {
    cat "$TEST_TMP/agents.orig"
    printf '\n'
    block_begin AGENTS.md agents
    printf '\n'
    cat "$ROOT/template/blocks/AGENTS.md"
    printf '\n'
    block_end AGENTS.md agents
  } > "$TEST_TMP/agents.expected"
  assert_same_file "$TEST_TMP/agents.expected" "$d/AGENTS.md" "block appended after one blank line, nothing else changed"
  assert_file_exists "$d/cortex/bin/check.sh" "other files still installed"
}

case_never_deletes() {
  local d
  d="$(new_git_repo)"
  mkdir -p "$d/harness/commands"
  printf 'mine\n' > "$d/harness/commands/zz-local.md"
  printf 'keep\n' > "$d/unrelated.txt"
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "install exits 0"
  assert_file_contains "$d/harness/commands/zz-local.md" "mine" "user file in harness/ kept"
  assert_file_contains "$d/unrelated.txt" "keep" "unrelated file kept"
  run "$INSTALL" "$d"
  assert_file_exists "$d/harness/commands/zz-local.md" "user file survives second run"
}

case_design_rules_not_in_template() {
  # A5 copies from docs/, so the template must not ship its own copy (that
  # would double-count and could drift from the canonical rules)
  assert_file_exists "$ROOT/docs/01-design-rules.md" "cortex ships docs/01-design-rules.md"
  assert_file_absent "$ROOT/template/cortex/design-rules.md" "template has no separate design-rules copy"
}

case_existing_cortex_dir_refused() {
  # was "differing design rules skipped": a cortex/ directory without
  # cortex/version is not a cortex install, so install refuses (step 0, D1)
  local d before
  d="$(new_git_repo)"
  mkdir -p "$d/cortex"
  printf '# my local rules\n' > "$d/cortex/design-rules.md"
  cp "$d/cortex/design-rules.md" "$TEST_TMP/rules.orig"
  before="$(tree_files "$d")"
  run "$INSTALL" "$d"
  # install step 0 (D1): exit 2 (was: exit 0 with the file skipped)
  assert_exit 2 "$CODE" "cortex/ without cortex/version exits 2 (D1)"
  # install step 0 (D1): names the directory (was: the skipped line)
  # A1: a refusal is the output line "refused <cause>: <reason>", on either
  # stream (was: assert_contains "$ERR", stderr only)
  assert_contains "$OUT$ERR" "cortex/" "the refusal names cortex/ (D1)"
  assert_true "A1: a refused cortex/ line" has_line_starting "$OUT$ERR" "refused "
  assert_same_file "$TEST_TMP/rules.orig" "$d/cortex/design-rules.md" "existing file untouched"
  # install step 0: nothing written (was: the summary counting one skip)
  assert_true "nothing written on the refusal" test "$(tree_files "$d")" = "$before"
}

case_design_rules_idempotent() {
  local d
  d="$(fresh_install)"
  assert_same_file "$ROOT/docs/01-design-rules.md" "$d/cortex/design-rules.md" "installed by the first run"
  run "$INSTALL" "$d"
  assert_not_contains "$OUT" "created cortex/design-rules.md" "second run does not recreate it"
  assert_line "$OUT" "unchanged cortex/design-rules.md" "second run reports it unchanged"
  assert_same_file "$ROOT/docs/01-design-rules.md" "$d/cortex/design-rules.md" "still identical after second run"
}

# ---- AC19 (B3, B6) ---------------------------------------------------------------

# Amendment 3, F4: the note names the time and the exact files (was: "note:
# this repository ignores file modes; after committing, run git update-index
# --chmod=+x cortex/bin/*.sh")
FILEMODE_NOTE_AT="after git add, run git update-index --chmod=+x "

# executable_template_files -> cortex/<path> for each file the template marks
# executable (mode 100755 in this checkout's index), sorted
executable_template_files() {
  git -C "$ROOT" ls-files -s -- template/cortex | awk '$1 == "100755" { sub(/^[^\t]*\t/, ""); sub(/^template\//, ""); print }' | LC_ALL=C sort
}

# tree_files DIR -> every file under DIR outside .git/, relative, sorted
tree_files() {
  (cd "$1" && find . -path ./.git -prune -o -type f -print | sed 's|^\./||' | LC_ALL=C sort)
}

case_2x_install_refused() {
  # was "AC19 version mismatch": a 2.x install (.cortex/version) is refused
  # (install step 0; no migration from 2.x, Non-goals)
  local d before
  d="$(new_git_repo)"
  mkdir -p "$d/.cortex"
  printf '0.0.1\n' > "$d/.cortex/version"
  printf 'mine\n' > "$d/README.md"
  before="$(tree_files "$d")"
  run "$INSTALL" "$d"
  assert_exit 2 "$CODE" "a 2.x install exits 2"
  # install step 0: names .cortex/version (was: the 2.x "upgrading ... is not
  # supported yet" message)
  # A1: a refusal is the output line "refused <cause>: <reason>", on either
  # stream (was: assert_contains "$ERR", stderr only)
  assert_contains "$OUT$ERR" ".cortex/version" "the refusal names .cortex/version"
  assert_true "A1: a refused .cortex/version line" has_line_starting "$OUT$ERR" "refused "
  assert_true "nothing copied on a 2.x install" test "$(tree_files "$d")" = "$before"
  assert_file_absent "$d/AGENTS.md" "no AGENTS.md created"
  assert_true ".cortex/version left as-is" test "$(cat "$d/.cortex/version")" = "0.0.1"
  assert_not_contains "$OUT" "created " "no created lines"
}

case_newer_installed_refused() {
  # was "AC19 version mismatch over an old install" (an older version, then
  # refused): install step 4, an installed version newer than the clone, is
  # the refusal that remains; the missing file is still not restored
  local d before
  d="$(fresh_install)"
  printf '99.0.0\n%s\n' "$(this_commit)" > "$d/cortex/version"
  rm "$d/cortex/AGENTS.md"
  before="$(tree_files "$d")"
  run "$INSTALL" "$d"
  assert_exit 2 "$CODE" "a newer installed version exits 2 (install step 4)"
  # install step 4 (criterion 5: naming the cause; was the 2.x message)
  # A1: a refusal is the output line "refused <cause>: <reason>", on either
  # stream (was: assert_contains "$ERR", stderr only)
  assert_contains "$OUT$ERR" "99.0.0" "names the installed version"
  assert_true "A1: a refused cortex/version line" has_line_starting "$OUT$ERR" "refused "
  # A1: a version refusal names both versions
  assert_contains "$OUT$ERR" "$(this_version)" "names the clone's version too (A1)"
  assert_true "nothing copied" test "$(tree_files "$d")" = "$before"
  assert_file_absent "$d/cortex/AGENTS.md" "removed file not restored"
}

case_2x_same_version_refused() {
  # was "matching version accepted": a 2.x .cortex/version is refused even
  # when it names this version (install step 0, no migration from 2.x)
  local d
  d="$(new_git_repo)"
  mkdir -p "$d/.cortex"
  cp "$ROOT/VERSION" "$d/.cortex/version"
  run "$INSTALL" "$d"
  # install step 0: exit 2 (was: exit 0)
  assert_exit 2 "$CODE" "a 2.x install at this version is refused"
  # install step 0: names .cortex/version (was: "unchanged .cortex/version")
  # A1: a refusal is the output line "refused <cause>: <reason>", on either
  # stream (was: assert_contains "$ERR", stderr only)
  assert_contains "$OUT$ERR" ".cortex/version" "the refusal names .cortex/version"
  assert_true "A1: a refused .cortex/version line" has_line_starting "$OUT$ERR" "refused "
  # install step 0: nothing installed (was: the template installed)
  assert_file_absent "$d/cortex" "nothing installed"
}

case_non_root_target_refused() {
  local d before
  d="$(new_git_repo)"
  mkdir -p "$d/sub"
  printf 'keep\n' > "$d/sub/file.txt"
  before="$(tree_files "$d")"
  run "$INSTALL" "$d/sub"
  assert_exit 2 "$CODE" "a subdirectory of a work tree exits 2"
  assert_true "error goes to stderr" test -n "$ERR"
  assert_true "nothing copied anywhere in the repo" test "$(tree_files "$d")" = "$before"
  assert_file_absent "$d/sub/AGENTS.md" "no AGENTS.md in the subdirectory"
  assert_file_absent "$d/AGENTS.md" "no AGENTS.md at the root"
}

case_filemode_false_note() {
  local d note files want
  d="$(new_git_repo)"
  git -C "$d" config core.filemode false
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "install exits 0 with core.filemode=false"
  # Amendment 3, F4: "after git add, run git update-index --chmod=+x" and the
  # exact files (was: assert_contains the 2.x note ending in cortex/bin/*.sh)
  note="$(printf '%s\n' "$OUT$ERR" | grep -F -- "$FILEMODE_NOTE_AT" | sed -n 1p || true)"
  assert_true "prints the filemode note naming the time: after git add (F4)" test -n "$note"
  assert_true "the note is a note: line (F4)" has_line_starting "$note" "note: "
  files="$(printf '%s\n' "${note#*"$FILEMODE_NOTE_AT"}" | tr ' ' '\n' | grep . | LC_ALL=C sort || true)"
  want="$(executable_template_files)"
  assert_true "fixture: the template marks scripts executable" test -n "$want"
  assert_true "the note names exactly the scripts the template marks executable (F4)" test "$files" = "$want"
  assert_not_contains "$note" "*" "no glob in the note (F4)"
  assert_not_contains "$note" "_config.sh" "the sourced _config.sh is not named (F4)"
  assert_not_contains "$note" "_footprint.sh" "the sourced _footprint.sh is not named (F4)"
}

case_filemode_true_no_note() {
  local d
  d="$(new_git_repo)"
  git -C "$d" config core.filemode true
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "install exits 0 with core.filemode=true"
  assert_not_contains "$OUT$ERR" "ignores file modes" "no filemode note when modes are tracked"
  # Amendment 3, F4: the note's new wording isn't printed either
  assert_not_contains "$OUT$ERR" "update-index --chmod=+x" "no update-index note when modes are tracked (F4)"
}

case_gitattributes() {
  # layout: the template's .gitattributes is cortex/.gitattributes and
  # applies inside cortex/ only (spec "Layouts")
  local d
  assert_file_exists "$ROOT/template/cortex/.gitattributes" "template ships cortex/.gitattributes"
  if grep -qxF '*.sh text eol=lf' "$ROOT/template/cortex/.gitattributes" 2>/dev/null; then pass
  else fail "template cortex/.gitattributes has the line '*.sh text eol=lf'"; fi
  d="$(new_git_repo)"
  run "$INSTALL" "$d"
  assert_line "$OUT" "created cortex/.gitattributes" "reports created cortex/.gitattributes"
  assert_same_file "$ROOT/template/cortex/.gitattributes" "$d/cortex/.gitattributes" "installed cortex/.gitattributes identical"
}

# ---- AC30 (E2): bounded cp/cmp/mkdir/chmod calls ----------------------------------

SHIMMED_CMDS="cp cmp mkdir chmod"

# make_shims and count_calls live in lib.sh (check.test.sh uses them too)

# assert_bounded_calls LOG LABEL : each shimmed command ran at most 3 times
assert_bounded_calls() {
  local log="$1" label="$2" c n
  for c in $SHIMMED_CMDS; do
    n="$(count_calls "$log" "$c")"
    if [ "$n" -le 3 ]; then pass
    else fail "$label: $c called $n times (at most 3 allowed, E2)"; fi
  done
}

case_bounded_processes() {
  local d shims log1 log2
  d="$(new_git_repo)"
  shims="$TEST_TMP/shims"
  log1="$TEST_TMP/calls.fresh.log"
  log2="$TEST_TMP/calls.rerun.log"
  : > "$log1"
  make_shims "$shims/fresh" "$log1" $SHIMMED_CMDS
  # sanity: the shims count and still work
  PATH="$shims/fresh:$PATH" cp "$ROOT/VERSION" "$TEST_TMP/shim-probe"
  assert_same_file "$ROOT/VERSION" "$TEST_TMP/shim-probe" "shimmed cp still copies"
  assert_true "shim logs its call" test "$(count_calls "$log1" cp)" = 1
  : > "$log1"

  run env PATH="$shims/fresh:$PATH" "$INSTALL" "$d"
  assert_exit 0 "$CODE" "shimmed fresh install exits 0"
  # install step 1 summary (was: "install: N created, 0 unchanged, 0 skipped")
  assert_true "shimmed fresh install summary" has_line_re "$OUT" "$SUMMARY_RE"
  assert_line "$OUT" "created cortex/AGENTS.md" "shimmed fresh install reports created cortex/AGENTS.md"
  assert_same_file "$ROOT/template/cortex/AGENTS.md" "$d/cortex/AGENTS.md" "shimmed fresh install copies cortex/AGENTS.md"
  assert_true "shimmed fresh install: check.sh executable" test -x "$d/cortex/bin/check.sh"
  assert_bounded_calls "$log1" "fresh install"

  : > "$log2"
  make_shims "$shims/rerun" "$log2" $SHIMMED_CMDS
  run env PATH="$shims/rerun:$PATH" "$INSTALL" "$d"
  assert_exit 0 "$CODE" "shimmed re-run exits 0"
  # install step 2: nothing created (was: the 2.x re-run summary line)
  assert_true "shimmed re-run prints no created lines" test -z "$(grep '^created ' <<<"$OUT" || true)"
  assert_line "$OUT" "unchanged cortex/AGENTS.md" "shimmed re-run reports unchanged cortex/AGENTS.md"
  assert_bounded_calls "$log2" "full re-run"
}

# ---- AC31: a template file name with a space -------------------------------------

# cortex_clone (lib.sh) gives a throwaway, committed cortex source whose
# template can be modified freely; install.sh records its commit (D3)

SPACED="cortex/knowledge/has space.md"

case_space_in_name() {
  local c d
  c="$(cortex_clone)"
  mkdir -p "$c/template/cortex/knowledge"
  printf '# a file with a space\n' > "$c/template/$SPACED"
  commit_all "$c" "add a file with a space"

  d="$(new_git_repo)"
  run "$c/bin/install.sh" "$d"
  assert_exit 0 "$CODE" "install with a spaced name exits 0"
  assert_line "$OUT" "created $SPACED" "reports created $SPACED unquoted"
  assert_same_file "$c/template/$SPACED" "$d/$SPACED" "spaced file installed identically"
  # install step 1 summary (was: the exact 2.x count)
  assert_true "summary line per install step 1" has_line_re "$OUT" "$SUMMARY_RE"

  run "$c/bin/install.sh" "$d"
  assert_exit 0 "$CODE" "re-run with a spaced name exits 0"
  assert_line "$OUT" "unchanged $SPACED" "re-run reports $SPACED unchanged"
  # install step 2: nothing created (was: the 2.x re-run summary)
  assert_true "re-run prints no created lines" test -z "$(grep '^created ' <<<"$OUT" || true)"

  d="$(new_git_repo)"
  mkdir -p "$d/cortex/knowledge"
  printf 'mine\n' > "$d/$SPACED"
  run "$c/bin/install.sh" "$d"
  # install step 0 (D1): cortex/ without cortex/version is refused (was:
  # exit 0 with the differing file skipped)
  assert_exit 2 "$CODE" "install over a cortex/ that is not an install exits 2 (D1)"
  # A1: a refusal is the output line "refused <cause>: <reason>", on either
  # stream (was: assert_contains "$ERR", stderr only)
  assert_contains "$OUT$ERR" "cortex/" "the refusal names cortex/ (D1)"
  assert_true "A1: a refused cortex/ line" has_line_starting "$OUT$ERR" "refused "
  assert_not_contains "$OUT" "created $SPACED" "differing $SPACED not reported created"
  assert_true "differing $SPACED left untouched" test "$(cat "$d/$SPACED")" = "mine"
  # install step 0: nothing installed (was: the summary counting the skip)
  assert_file_absent "$d/cortex/version" "nothing installed on the refusal"
}

# ---- 3.0.0 footprint, ownership and refusals (spec 2026-10-05-v3-removable-layout) ----

# snapshot_new_files BEFORE AFTER -> "f <path> <sha>" lines of AFTER not in
# BEFORE (new or changed files), from two tree_snapshot outputs
snapshot_new_files() {
  printf '%s\n' "$1" > "$TEST_TMP/.snap.a"; printf '%s\n' "$2" > "$TEST_TMP/.snap.b"
  LC_ALL=C comm -13 "$TEST_TMP/.snap.a" "$TEST_TMP/.snap.b" | grep '^f ' || true
}

# block_field DIR PATH ID N -> field N of PATH's block record for ID
block_field() {
  footprint_records "$1" | BF_P="$2" BF_I="$3" awk -F'\t' -v n="$4" '
    $1 == "block" && $2 == ENVIRON["BF_P"] && $3 == ENVIRON["BF_I"] { print $n; exit }'
}

# block_sha FILE ID -> git hash-object of the lines between ID's markers (A7),
# without the blank lines directly inside them (Amendment 3, F1: framing, not
# part of the sha; was: every line between the markers)
block_sha() {
  block_body "$1" "$2" > "$TEST_TMP/.blk.$$"
  git hash-object --no-filters "$TEST_TMP/.blk.$$"
  rm -f "$TEST_TMP/.blk.$$"
}

case_v3_empty_repo() {
  # criterion 1; A1 (output lines, the summary last); A5 (block source);
  # A6 (sep 0 in a created file); A7 (sorted records, the two shas)
  local d top sha recs last n printed onfile
  d="$(new_git_repo)"
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "install on an empty repository exits 0"
  top="$(cd "$d" && find . -mindepth 1 -maxdepth 1 ! -name .git | sed 's|^\./||' | LC_ALL=C sort)"
  assert_true "only cortex/ and AGENTS.md are created at the root (criterion 1)" \
    test "$top" = "$(printf 'AGENTS.md\ncortex')"
  assert_true "AGENTS.md holds one agents block" test "$(block_count "$d/AGENTS.md" agents)" = 1
  # Amendment 3, F1: the content sits inside one blank line each side (was:
  # the lines between the markers compared with the template as they are)
  assert_true "the block's content is template/blocks/AGENTS.md, markers added (A5)" \
    test "$(block_body "$d/AGENTS.md" agents)" = "$(cat "$ROOT/template/blocks/AGENTS.md" 2>/dev/null)"
  assert_true "cortex/footprint's first line is the format line" \
    test "$(sed -n 1p "$d/cortex/footprint" 2>/dev/null)" = "$FOOTPRINT_HEADER"
  assert_true "AGENTS.md recorded created" has_record "$d" created AGENTS.md
  assert_true "the agents block recorded" has_record "$d" block AGENTS.md agents
  recs="$(footprint_records "$d")"
  assert_true "exactly those two records" test "$(grep -c . <<<"$recs" || true)" = 2
  assert_true "records sorted with LC_ALL=C sort (A7)" test "$recs" = "$(LC_ALL=C sort <<<"$recs")"
  sha="$(git -C "$d" hash-object --no-filters AGENTS.md 2>/dev/null || true)"
  assert_true "the created sha is git hash-object of AGENTS.md (A7)" has_record "$d" created AGENTS.md "$sha"
  assert_true "the block sha is git hash-object of the lines between the markers (A7)" \
    test "$(block_field "$d" AGENTS.md agents 4)" = "$(block_sha "$d/AGENTS.md" agents)"
  assert_true "sep 0: nothing added before the block in a created file (A6)" \
    test "$(block_field "$d" AGENTS.md agents 5)" = 0
  assert_line "$OUT" "created AGENTS.md" "A1: created AGENTS.md"
  assert_line "$OUT" "block AGENTS.md agents" "A1: block AGENTS.md agents"
  # Amendment 3, F4: "install: <n> files in cortex/, <c> created, <b> blocks"
  # (was: exactly "install: 1 created, 1 blocks"). <n> counts the files this
  # run wrote in cortex/: either the "created cortex/..." lines it printed or
  # every file now under cortex/ (the footprint included) is accepted
  last="$(printf '%s\n' "$OUT" | sed -n '$p')"
  assert_true "A1, F4: the summary is the last line" \
    grep -qxE 'install: [0-9]+ files in cortex/, 1 created, 1 blocks' <<<"$last"
  n="$(printf '%s\n' "$last" | sed -n 's/^install: \([0-9]*\) files in cortex\/.*/\1/p')"
  printed="$(grep -c '^created cortex/' <<<"$OUT" || true)"
  onfile="$(find "$d/cortex" -type f | grep -c '' || true)"
  assert_true "F4: <n> counts the files in cortex/ ($printed printed, $onfile on disk; got '$n')" \
    test "$n" = "$printed" -o "$n" = "$onfile"
  # Amendment 3, F1: one blank line inside each marker, outside the sha
  assert_true "F1: one blank line after the begin marker and one before the end marker" \
    block_framed "$d/AGENTS.md" agents
  assert_true "F1: the block sha is the template's blob sha (framing excluded)" \
    test "$(block_field "$d" AGENTS.md agents 4)" = "$(git hash-object --no-filters "$ROOT/template/blocks/AGENTS.md")"
}

case_v3_template_block_normal_form() {
  # Amendment 3, F1: template/blocks/AGENTS.md is in CommonMark's normal
  # form: a blank line after each heading, a blank line before the list,
  # "-" bullets; the framing blank lines are install's, not the source's
  local f="$ROOT/template/blocks/AGENTS.md" bad
  assert_file_exists "$f" "template ships the root block source"
  assert_true "the source starts with a non-blank line (install adds the framing)" \
    test -n "$(sed -n 1p "$f")"
  assert_true "the source ends with a non-blank line (install adds the framing)" \
    test -n "$(sed -n '$p' "$f")"
  bad="$(awk 'prev ~ /^#+ / && $0 != "" { print NR ": " $0 } { prev = $0 }' "$f")"
  assert_true "a blank line follows every heading (F1)${bad:+: $bad}" test -z "$bad"
  bad="$(awk '/^- / && prev != "" && prev !~ /^- / && prev !~ /^  / { print NR ": " $0 } { prev = $0 }' "$f")"
  assert_true "a blank line precedes the list (F1)${bad:+: $bad}" test -z "$bad"
  assert_true "the source has a list" grep -q '^- ' "$f"
  bad="$(grep -nE '^[*+] ' "$f" || true)"
  assert_true "bullets are '-' (F1)${bad:+: $bad}" test -z "$bad"
}

case_v3_router_stricter_rule() {
  # Amendment 3, F3: cortex/AGENTS.md no longer calls the root AGENTS.md the
  # project's; the project's own agent instructions apply too, the stricter
  # rule applies, a conflict with neither stricter is asked about
  local f="$ROOT/template/cortex/AGENTS.md" text
  text="$(tr '\n' ' ' < "$f" | tr -s ' ')"
  assert_not_contains "$text" "is the project's; read it too" "the old sentence is gone (F3)"
  assert_contains "$text" "stricter rule applies" "the stricter rule applies (F3)"
}

case_v3_codeowners_unframed() {
  # Amendment 3, F1: CODEOWNERS blocks are excepted from the framing (no
  # markdown): the first and last lines inside the markers are not blank
  local d c
  d="$(seeded_repo)"
  install_adapt_github "$d" || return 0
  c="$(block_content "$d/.github/CODEOWNERS" codeowners)"
  assert_true "fixture: the codeowners block has content" test -n "$c"
  assert_true "no blank line after # cortex:begin codeowners (F1)" test -n "$(printf '%s\n' "$c" | sed -n 1p)"
  assert_true "no blank line before # cortex:end codeowners (F1)" test -n "$(printf '%s\n' "$c" | sed -n '$p')"
  assert_true "the AGENTS.md block in the same install is framed (F1)" block_framed "$d/AGENTS.md" agents
  assert_true "the CLAUDE.md block in the same install is framed (F1)" block_framed "$d/CLAUDE.md" claude
}

case_v3_block_sep() {
  # A6: sep records what the insertion added: 1 after a final newline, 2
  # when the file lacked one (a newline and a blank line added)
  local d
  d="$(new_git_repo)"
  printf '# mine\n' > "$d/AGENTS.md"
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "install over AGENTS.md ending in a newline exits 0"
  assert_true "sep 1 for a file ending in a newline (A6)" test "$(block_field "$d" AGENTS.md agents 5)" = 1
  assert_true "no created record for an existing AGENTS.md (D11)" eval '! has_record "$d" created AGENTS.md'
  d="$(new_git_repo)"
  printf '# mine' > "$d/AGENTS.md"
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "install over AGENTS.md without a final newline exits 0"
  assert_true "sep 2 for a file without a final newline (A6)" test "$(block_field "$d" AGENTS.md agents 5)" = 2
  assert_true "the project's line stays, ended by the added newline (A6)" \
    test "$(sed -n 1p "$d/AGENTS.md")" = "# mine"
  assert_true "then one blank line, then the block (A6)" \
    test "$(sed -n 2p "$d/AGENTS.md")" = "" -a "$(sed -n 3p "$d/AGENTS.md")" = "$(block_begin AGENTS.md agents)"
}

case_v3_seeded_project() {
  # criteria 2 and 3: a project's own files keep every byte outside the
  # blocks; every path that changed outside cortex/ is recorded; C13 passes
  local d pre post f p new gone
  d="$(seeded_repo)"
  for f in AGENTS.md CLAUDE.md .gitattributes .github/CODEOWNERS .claude/settings.json; do
    mkdir -p "$(dirname "$TEST_TMP/seed/$f")"; cp "$d/$f" "$TEST_TMP/seed/$f"
  done
  pre="$(tree_snapshot "$d")"
  install_adapt_github "$d" || return 0
  for f in AGENTS.md CLAUDE.md .github/CODEOWNERS; do
    assert_true "$f: the project's bytes stay first (criterion 2)" file_starts_with "$d/$f" "$TEST_TMP/seed/$f"
    assert_true "$f: nothing outside cortex's blocks changed (criterion 2)" \
      test "$(outside_blocks "$d/$f")" = "$(cat "$TEST_TMP/seed/$f")"
  done
  assert_same_file "$TEST_TMP/seed/.gitattributes" "$d/.gitattributes" ".gitattributes byte-identical (criterion 2)"
  assert_same_file "$TEST_TMP/seed/.claude/settings.json" "$d/.claude/settings.json" "settings.json byte-identical (criterion 2, Q1)"
  assert_true "AGENTS.md holds the agents block" test "$(block_count "$d/AGENTS.md" agents)" = 1
  assert_true "CLAUDE.md holds the claude block" test "$(block_count "$d/CLAUDE.md" claude)" = 1
  assert_true "CODEOWNERS holds a #-style codeowners block (criterion 2)" \
    test "$(block_count "$d/.github/CODEOWNERS" codeowners)" = 1
  assert_file_not_contains "$d/.github/CODEOWNERS" "<!--" "no HTML comment markers in CODEOWNERS"
  assert_true "the codeowners block names CODE_OWNERS (D8)" grep -qF "@t" <<<"$(block_content "$d/.github/CODEOWNERS" codeowners)"
  assert_file_exists "$d/.github/workflows/cortex.yml" "CI=github generates the workflow (D8)"
  assert_true "the workflow is recorded created (D8)" has_record "$d" created .github/workflows/cortex.yml
  # criterion 3: every new or changed file outside cortex/ has a record
  post="$(tree_snapshot "$d")"
  new="$(snapshot_new_files "$pre" "$post" | awk '{ print $2 }' | grep -v '^cortex/' || true)"
  assert_true "the install changed paths outside cortex/" test -n "$new"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if footprint_records "$d" | P="$p" awk -F'\t' '$2 == ENVIRON["P"] { f = 1 } END { exit f ? 0 : 1 }'; then pass
    else fail "criterion 3: $p changed outside cortex/ but has no footprint record"; fi
  done <<<"$new"
  # a changed file shows up both ways; a deleted one only in this direction
  gone="$(snapshot_new_files "$post" "$pre" | awk '{ print $2 }' | grep -v '^cortex/' || true)"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    assert_file_exists "$d/$p" "criterion 2: $p is never deleted"
  done <<<"$gone"
  merge_entries "$d"
  assert_true "settings.json's missing rules recorded as entries (Q1)" test "$(entry_count "$d")" -gt 0
  run bash -c 'cd "$1" && bash cortex/bin/check.sh' _ "$d"
  assert_not_contains "$OUT" "[C13]" "every footprint record matches the tree: no C13 (criterion 3)"
}

case_v3_unrecorded_cortex_named() {
  # criterion 5, D11, install step 0: an unrecorded cortex-named path is
  # refused (exit 2, A2), named, and nothing is written
  local d p before name
  for p in .github/workflows/cortex.yml .claude/agents/cortex-zz.md .claude/skills/cortex-zz/SKILL.md; do
    d="$(new_git_repo)"
    mkdir -p "$(dirname "$d/$p")"
    printf 'mine\n' > "$d/$p"
    before="$(tree_snapshot "$d")"
    run "$INSTALL" "$d"
    assert_exit 2 "$CODE" "unrecorded $p: exit 2 (A2)"
    case "$p" in .claude/skills/*) name=".claude/skills/cortex-zz" ;; *) name="$p" ;; esac
    assert_contains "$OUT$ERR" "$name" "the refusal names $name"
    assert_true "A1: a refused line" has_line_starting "$OUT$ERR" "refused "
    assert_true "nothing written for an unrecorded $p" test "$(tree_snapshot "$d")" = "$before"
  done
}

case_v3_unreleased_commit() {
  # criterion 7, D3: the commit is printed; a commit without a v<VERSION>
  # tag also prints "unreleased: <commit>" (A1)
  local c d sha v
  c="$(cortex_clone)"
  sha="$(git -C "$c" rev-parse HEAD)"
  v="$(tr -d '\r\n' < "$c/VERSION")"
  d="$(new_git_repo)"
  run "$c/bin/install.sh" "$d"
  assert_exit 0 "$CODE" "install from an untagged commit exits 0"
  assert_line "$OUT$ERR" "unreleased: $sha" "an untagged commit prints unreleased: <commit> (A1)"
  assert_true "cortex/version line 2 is the clone's commit" test "$(sed -n 2p "$d/cortex/version" 2>/dev/null)" = "$sha"
  git -C "$c" tag "v$v"
  d="$(new_git_repo)"
  run "$c/bin/install.sh" "$d"
  assert_exit 0 "$CODE" "install from a release tag exits 0"
  assert_contains "$OUT" "$sha" "the commit installed from is printed (D3)"
  assert_contains "$OUT" "$v" "the version installed is printed (D3)"
  assert_not_contains "$OUT$ERR" "unreleased" "a v<VERSION> tag is not unreleased"
}

case_v3_footprint_unknown_format() {
  # criterion 32, install step 0: an unknown footprint format exits 2, named
  local d before
  d="$(fresh_install)"
  filter_file "$d/cortex/footprint" awk 'NR == 1 { print "# cortex footprint 99"; next } { print }'
  before="$(tree_snapshot "$d")"
  run "$INSTALL" "$d"
  assert_exit 2 "$CODE" "an unknown footprint format exits 2 (A2)"
  assert_contains "$OUT$ERR" "footprint 99" "the refusal names the format"
  assert_true "A1: a refused line" has_line_starting "$OUT$ERR" "refused "
  assert_true "nothing written" test "$(tree_snapshot "$d")" = "$before"
}

run_case "no argument -> exit 2" case_no_argument
run_case "missing target dir -> exit 2" case_missing_dir
run_case "non-git dir -> exit 2" case_non_git_dir
run_case "fresh install creates every template file under cortex/ (AC1)" case_fresh_install
run_case "second run is idempotent (AC1, install step 2)" case_second_run_idempotent
run_case "existing AGENTS.md gets the agents block (install step 1, D11)" case_existing_agents_gets_block
run_case "never deletes or modifies user files" case_never_deletes
run_case "design rules come from docs/, not template/ (A5)" case_design_rules_not_in_template
run_case "cortex/ that is not an install is refused (D1)" case_existing_cortex_dir_refused
run_case "design rules idempotent (AC13)" case_design_rules_idempotent
run_case "2.x install refused: exit 2, nothing copied (install step 0)" case_2x_install_refused
run_case "newer installed version refused (install step 4)" case_newer_installed_refused
run_case "2.x install at this version still refused (install step 0)" case_2x_same_version_refused
run_case "AC19 non-root target: exit 2, nothing copied" case_non_root_target_refused
run_case "AC19 filemode note when core.filemode=false" case_filemode_false_note
run_case "no filemode note when core.filemode=true" case_filemode_true_no_note
run_case "AC19 cortex/.gitattributes installed" case_gitattributes
run_case "AC30 cp/cmp/mkdir/chmod called at most 3 times (E2)" case_bounded_processes
run_case "AC31 template file name with a space" case_space_in_name
run_case "criterion 1: an empty repository gets cortex/, AGENTS.md and the footprint" case_v3_empty_repo
run_case "A6: a block record's sep field" case_v3_block_sep
run_case "criteria 2-3: a project's files keep their bytes; every change recorded" case_v3_seeded_project
run_case "criterion 5: unrecorded cortex-named paths refused (D11)" case_v3_unrecorded_cortex_named
run_case "criterion 7: an untagged commit prints unreleased (D3)" case_v3_unreleased_commit
run_case "criterion 32: unknown footprint format refused by install" case_v3_footprint_unknown_format
run_case "F1: template/blocks/AGENTS.md in CommonMark normal form" case_v3_template_block_normal_form
run_case "F1: CODEOWNERS blocks are not framed; markdown blocks are" case_v3_codeowners_unframed
run_case "F3: cortex/AGENTS.md: the stricter rule applies" case_v3_router_stricter_rule
summary
