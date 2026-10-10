#!/usr/bin/env bash
# Tests for upgrade by bin/install.sh (spec docs/specs/2026-10-05-v3-removable-layout.md:
# install step 3, D2, D3, D12, D14; acceptance criteria 20-31 and 33;
# Amendment 1: A1 output lines and the upgrade summary, A2 exit codes, A7).
#
# Template versions are built by the suite in a fixture cortex clone
# (cortex_clone, lib.sh): version 3.0.0 adds test-owned template files under
# cortex/knowledge/zz-up/ and a CHANGELOG, then each later version edits
# them, the config, the root block's source and the design rules, bumps
# VERSION, adds a CHANGELOG entry and is tagged v<VERSION>.
#
# Consumer-action notes: a CHANGELOG entry's "**For installed
# repositories:**" paragraph, the form 2.2.0 and 2.3.0 used (a spec question:
# the spec doesn't name the form; see the report).
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

FX=cortex/knowledge/zz-up

# fx C NAME TEXT : write template/$FX/NAME in clone C as TEXT (printf %b)
fx() {
  mkdir -p "$1/template/$FX"
  printf '%b' "$3" > "$1/template/$FX/$2"
}

# clog C VERSION : prepend a CHANGELOG entry for VERSION with its note
clog() {
  local c="$1" v="$2"
  {
    printf '# Changelog\n\n## %s — 2026-10-08\n\n**For installed repositories:** zz-note-%s.\n\n' "$v" "$v"
    tail -n +2 "$c/CHANGELOG.md" | sed '/./,$!d'
  } > "$c/CHANGELOG.tmp"
  mv "$c/CHANGELOG.tmp" "$c/CHANGELOG.md"
}

# release C VERSION : set VERSION, add its CHANGELOG entry, commit, tag
release() {
  printf '%s\n' "$2" > "$1/VERSION"
  clog "$1" "$2"
  commit_all "$1" "cortex $2"
  git -C "$1" tag "v$2"
}

# clone_v1 -> a fixture clone at 3.0.0 with the zz-up files
clone_v1() {
  local c
  c="$(cortex_clone 3.0.0)" || return 1
  printf '# Changelog\n' > "$c/CHANGELOG.md"
  fx "$c" unedited.md 'a1\n'
  fx "$c" user-edited.md 'u1\nu2\nu3\n'
  fx "$c" both.md 'b1\nb2\nb3\nb4\nb5\nb6\nb7\nb8\nb9\n'
  fx "$c" conflict.md 'c1\nc2\nc3\n'
  fx "$c" removed-unedited.md 'r1\n'
  fx "$c" removed-edited.md 'e1\n'
  fx "$c" deleted-changed.md 'd1\n'
  fx "$c" deleted-same.md 's1\n'
  release "$c" 3.0.0
  printf '%s\n' "$c"
}

# installed_from C -> a repository with C installed and filled, committed
# (D14: an upgrade starts from a clean work tree); AGENTS.md has project text
installed_from() {
  local c="$1" d
  d="$(new_git_repo)"
  printf '# Mine\n\nProject text before the block.\n' > "$d/AGENTS.md"
  "$c/bin/install.sh" "$d" >/dev/null 2>&1 || { fail "installed_from: install.sh failed"; return 1; }
  fill_install "$d" || return 1
  commit_all "$d" "install cortex 3.0.0"
  printf '%s\n' "$d"
}

upgrade_from() { # C D : run C's install.sh on D
  run "$1/bin/install.sh" "$2"
}

last_line() { printf '%s\n' "$1" | sed -n '$p'; }

# ---- the shared scenario (criteria 21-26, 28, 30) ---------------------------------
#
# 3.0.0 installed, the user's edits committed, then upgraded to 3.2.0 across
# 3.1.0. Built once, by the first case that needs it; the cases read it.

SCN="$TEST_TMP/scenario"

user_edits() { # D : the user's side of the scenario
  local d="$1"
  printf 'u1\nu2-user\nu3\n' > "$d/$FX/user-edited.md"
  printf 'b1\nb2-user\nb3\nb4\nb5\nb6\nb7\nb8\nb9\n' > "$d/$FX/both.md"
  printf 'c1\nc2-user\nc3\n' > "$d/$FX/conflict.md"
  printf 'e1-user\n' > "$d/$FX/removed-edited.md"
  rm "$d/$FX/deleted-changed.md" "$d/$FX/deleted-same.md"
  printf "user's own\n" > "$d/$FX/new-clash.md"
  mkdir -p "$d/cortex/changes/my-change"
  printf '# my change\n' > "$d/cortex/changes/my-change/proposal.md"
  printf '# mine\n' > "$d/cortex/knowledge/mine.md"
  # the block's first non-blank line (Amendment 3, F1: the first line inside
  # the markers is the blank framing; was: NR == 1)
  set_block "$d/AGENTS.md" agents "$(block_content "$d/AGENTS.md" agents | awk '!done && $0 != "" { print $0 " (ours)"; done = 1; next } { print }')"
  append "$d/cortex/design-rules.md" "zz-user-design-note"
  commit_all "$d" "the user's edits"
}

upstream_310() { # C : 3.1.0's side
  local c="$1"
  fx "$c" unedited.md 'a2\n'
  fx "$c" both.md 'b1\nb2\nb3\nb4\nb5\nb6\nb7\nb8-up\nb9\n'
  fx "$c" conflict.md 'c1\nc2-up\nc3\n'
  rm "$c/template/$FX/removed-unedited.md" "$c/template/$FX/removed-edited.md"
  fx "$c" deleted-changed.md 'd1-up\n'
  fx "$c" new.md 'n1\n'
  fx "$c" new-clash.md 'upstream\n'
  append "$c/template/cortex/config" "# A key 3.1.0 added (fixture)."
  append "$c/template/cortex/config" "ZZ_NEW_KEY=zz-default"
  append "$c/template/blocks/AGENTS.md" "- zz-upstream-rule"
  filter_file "$c/docs/01-design-rules.md" awk '{ print } NR == 1 { print ""; print "zz-upstream-design-note" }'
  release "$c" 3.1.0
}

scenario() { # -> the upgraded repository; OUT and CODE of the upgrade in $SCN
  if [ ! -f "$SCN/repo" ]; then
    local c d
    mkdir -p "$SCN"
    c="$(clone_v1)" || return 1
    d="$(installed_from "$c")" || return 1
    user_edits "$d"
    cp "$d/cortex/config" "$SCN/config.before"
    cp "$d/cortex/changes/my-change/proposal.md" "$SCN/proposal.before"
    cp "$d/cortex/knowledge/mine.md" "$SCN/mine.before"
    outside_blocks "$d/AGENTS.md" > "$SCN/agents-outside.before"
    upstream_310 "$c"
    release "$c" 3.2.0
    upgrade_from "$c" "$d"
    printf '%s\n' "$OUT" > "$SCN/out"
    printf '%s\n' "$CODE" > "$SCN/code"
    git -C "$c" rev-parse HEAD > "$SCN/commit"
    printf '%s\n' "$c" > "$SCN/clone"
    printf '%s\n' "$d" > "$SCN/repo"
  fi
  OUT="$(cat "$SCN/out")"; CODE="$(cat "$SCN/code")"
  cat "$SCN/repo"
}

case_unedited_replaced() {
  # criterion 21; D3; A1 "replaced"
  local d; d="$(scenario)" || return 0; OUT="$(cat "$SCN/out")"
  assert_true "an unedited file is the new version" test "$(cat "$d/$FX/unedited.md")" = "a2"
  assert_line "$OUT" "replaced $FX/unedited.md" "A1: replaced"
  assert_true "cortex/version line 1 is the new version" test "$(sed -n 1p "$d/cortex/version")" = "3.2.0"
  assert_true "cortex/version line 2 is the new commit" test "$(sed -n 2p "$d/cortex/version")" = "$(cat "$SCN/commit")"
}

case_edited_kept() {
  # criterion 22; A1 "kept <path> (edited)"
  local d; d="$(scenario)" || return 0; OUT="$(cat "$SCN/out")"
  assert_true "the user's edit is kept" test "$(cat "$d/$FX/user-edited.md")" = "$(printf 'u1\nu2-user\nu3')"
  assert_line "$OUT" "kept $FX/user-edited.md (edited)" "A1: kept (edited)"
}

case_both_merged() {
  # criterion 23; D2; A1 "merged"
  local d; d="$(scenario)" || return 0; OUT="$(cat "$SCN/out")"
  assert_file_contains "$d/$FX/both.md" "b2-user" "the user's edit is present"
  assert_file_contains "$d/$FX/both.md" "b8-up" "the upstream edit is present"
  assert_file_not_contains "$d/$FX/both.md" "<<<<<<<" "no conflict markers"
  assert_line "$OUT" "merged $FX/both.md" "A1: merged"
}

case_conflict() {
  # criterion 24; A1 "conflict" and the summary; A2: conflicts exit 1
  local d; d="$(scenario)" || return 0; OUT="$(cat "$SCN/out")"; CODE="$(cat "$SCN/code")"
  assert_exit 1 "$CODE" "an upgrade that leaves conflicts exits 1 (A2)"
  assert_file_contains "$d/$FX/conflict.md" "<<<<<<<" "conflict markers left"
  assert_file_contains "$d/$FX/conflict.md" "c2-user" "the user's side is in the markers"
  assert_file_contains "$d/$FX/conflict.md" "c2-up" "upstream's side is in the markers"
  assert_line "$OUT" "conflict $FX/conflict.md" "A1: conflict <path>"
  assert_true "A1: the upgrade summary is the last line, counting both conflicts" \
    grep -qE '^upgrade 3\.0\.0 -> 3\.2\.0: [0-9]+ replaced, [0-9]+ merged, 2 conflicts$' <<<"$(last_line "$OUT")"
  # C14 fails until resolved (criterion 24)
  run bash -c 'cd "$1" && bash cortex/bin/check.sh' _ "$d"
  assert_contains "$OUT" "FAIL [C14] $FX/conflict.md" "C14 fails while markers remain"
  printf 'c1\nc2-both\nc3\n' > "$d/$FX/conflict.md"
  printf "user's own\n" > "$d/$FX/new-clash.md"
  run bash -c 'cd "$1" && bash cortex/bin/check.sh' _ "$d"
  assert_not_contains "$OUT" "[C14]" "C14 passes once resolved"
}

case_added_removed_deleted() {
  # criterion 25; A1 "created", "conflict", "removed", "kept (removed
  # upstream, edited)", "deleted (changed upstream)"
  local d; d="$(scenario)" || return 0; OUT="$(cat "$SCN/out")"
  assert_true "a file added upstream is created" test "$(cat "$d/$FX/new.md" 2>/dev/null)" = "n1"
  assert_line "$OUT" "created $FX/new.md" "A1: created"
  assert_line "$OUT" "conflict $FX/new-clash.md" "a user file where upstream added one is a conflict"
  assert_file_contains "$d/$FX/new-clash.md" "user's own" "the user's file is not lost"
  assert_file_absent "$d/$FX/removed-unedited.md" "removed upstream, unedited: deleted"
  assert_line "$OUT" "removed $FX/removed-unedited.md" "A1: removed"
  assert_true "removed upstream, edited: kept" test "$(cat "$d/$FX/removed-edited.md" 2>/dev/null)" = "e1-user"
  assert_line "$OUT" "kept $FX/removed-edited.md (removed upstream, edited)" "A1: kept (removed upstream, edited)"
  assert_file_absent "$d/$FX/deleted-changed.md" "deleted by the user, changed upstream: stays deleted"
  assert_line "$OUT" "deleted $FX/deleted-changed.md (changed upstream)" "A1: deleted (changed upstream)"
  assert_file_absent "$d/$FX/deleted-same.md" "deleted by the user, unchanged upstream: stays deleted"
  assert_not_contains "$OUT" "$FX/deleted-same.md" "an unchanged file the user deleted is not reported"
}

case_project_files_and_config() {
  # criterion 26, D12; A1 "config <KEY>=<default>"
  local d; d="$(scenario)" || return 0; OUT="$(cat "$SCN/out")"
  assert_same_file "$SCN/config.before" "$d/cortex/config" "cortex/config byte-identical (D12)"
  assert_same_file "$SCN/proposal.before" "$d/cortex/changes/my-change/proposal.md" "a change folder untouched"
  assert_same_file "$SCN/mine.before" "$d/cortex/knowledge/mine.md" "added knowledge untouched"
  assert_line "$OUT" "config ZZ_NEW_KEY=zz-default" "A1: the added key printed with its default"
}

case_block_and_design_rules_merged() {
  # criterion 28: the agents block merges like a file; text outside it is
  # unchanged; cortex/design-rules.md keeps the user's edit
  local d blk; d="$(scenario)" || return 0
  blk="$(block_content "$d/AGENTS.md" agents)"
  assert_true "the user's block edit is kept" grep -qF "(ours)" <<<"$blk"
  assert_true "upstream's block edit is merged in" grep -qxF -- "- zz-upstream-rule" <<<"$blk"
  assert_true "text outside the block unchanged" test "$(outside_blocks "$d/AGENTS.md")" = "$(cat "$SCN/agents-outside.before")"
  assert_true "one agents block" test "$(block_count "$d/AGENTS.md" agents)" = 1
  assert_file_contains "$d/cortex/design-rules.md" "zz-user-design-note" "design rules: the user's edit kept"
  assert_file_contains "$d/cortex/design-rules.md" "zz-upstream-design-note" "design rules: upstream's edit merged"
}

case_changelog_notes() {
  # criterion 30: the notes of every version passed, and only those
  OUT="$(scenario >/dev/null && cat "$SCN/out")" || return 0
  assert_contains "$OUT" "zz-note-3.1.0" "3.1.0's note printed"
  assert_contains "$OUT" "zz-note-3.2.0" "3.2.0's note printed"
  assert_not_contains "$OUT" "zz-note-3.0.0" "the installed version's own note is not"
}

# ---- separate fixtures ----------------------------------------------------------------

case_dirty_refused() {
  # criterion 20, D14: a dirty work tree: exit 2 (A2), nothing changed
  local c d before
  c="$(clone_v1)" || return 0; d="$(installed_from "$c")" || return 0
  fx "$c" unedited.md 'a2\n'; release "$c" 3.1.0
  append "$d/$FX/user-edited.md" "uncommitted"
  before="$(tree_snapshot "$d")"
  upgrade_from "$c" "$d"
  assert_exit 2 "$CODE" "a dirty work tree exits 2"
  assert_true "A1: a refused line" has_line_starting "$OUT$ERR" "refused "
  assert_true "nothing changed" test "$(tree_snapshot "$d")" = "$before"
}

case_missing_commit() {
  # criterion 27, D3: a clone without the installed commit: exit 2, the fetch command
  local c d s before
  c="$(clone_v1)" || return 0; d="$(installed_from "$c")" || return 0
  fx "$c" unedited.md 'a2\n'; release "$c" 3.1.0
  s="$(mktemp -d "$TEST_TMP/shallow.XXXXXX")"
  git -C "$s" init -q
  git -C "$s" fetch -q --depth 1 "$c" HEAD
  git -C "$s" -c advice.detachedHead=false checkout -q FETCH_HEAD
  if git -C "$s" cat-file -e "$(sed -n 2p "$d/cortex/version")^{commit}" 2>/dev/null; then
    fail "fixture: the shallow clone has the installed commit"; return 0
  fi
  before="$(tree_snapshot "$d")"
  upgrade_from "$s" "$d"
  assert_exit 2 "$CODE" "a clone missing the installed commit exits 2"
  assert_contains "$OUT$ERR" "git fetch" "prints the fetch command to run"
  assert_true "nothing changed" test "$(tree_snapshot "$d")" = "$before"
}

case_same_version_other_commit() {
  # criterion 29, install step 3: the same version from another commit upgrades
  local c d sha
  c="$(clone_v1)" || return 0; d="$(installed_from "$c")" || return 0
  fx "$c" unedited.md 'a2\n'; commit_all "$c" "a fix, same VERSION"
  sha="$(git -C "$c" rev-parse HEAD)"
  upgrade_from "$c" "$d"
  assert_exit 0 "$CODE" "the upgrade exits 0"
  assert_line "$OUT" "replaced $FX/unedited.md" "the changed file is replaced, not left unchanged"
  assert_true "cortex/version names the new commit" test "$(sed -n 2p "$d/cortex/version")" = "$sha"
  assert_true "A1: an upgrade summary, 3.0.0 -> 3.0.0" has_line_starting "$OUT" "upgrade 3.0.0 -> 3.0.0: "
}

# lock_base D : D's install committed as origin/main with tests, then branch
# "feature" with cortex/changes/x locked (lock_tests, lib.sh). The change
# folder has a tasks.md with every task ticked: spec 3.1.0 G3's tasks gate
# fails one without it (was: no tasks.md written)
lock_base() {
  local d="$1"
  mkdir -p "$d/tests"
  printf 'echo a\n' > "$d/tests/a.test.sh"
  commit_all "$d" "base"
  git -C "$d" update-ref refs/remotes/origin/main HEAD
  git -C "$d" checkout -q -b feature
  printf 'echo b\n' > "$d/tests/b.test.sh"
  mkdir -p "$d/cortex/changes/x"
  printf '# Tasks: x\n\n- [x] the change -- done when: its test passes\n' > "$d/cortex/changes/x/tasks.md"
  lock_tests "$d" cortex/changes/x tests/b.test.sh
}

case_minor_keeps_locks() {
  # criterion 31, D12: a lock written under 3.0.0 passes 3.1.0's
  # tests-locked.sh and ci-gates.sh
  local c d
  c="$(clone_v1)" || return 0; d="$(installed_from "$c")" || return 0
  lock_base "$d"
  append "$c/template/cortex/bin/tests-locked.sh" "# zz 3.1.0"
  append "$c/template/cortex/bin/ci-gates.sh" "# zz 3.1.0"
  release "$c" 3.1.0
  upgrade_from "$c" "$d"
  assert_exit 0 "$CODE" "a minor upgrade with an open lock exits 0"
  commit_all "$d" "upgrade to 3.1.0"
  assert_file_contains "$d/cortex/bin/tests-locked.sh" "# zz 3.1.0" "fixture: 3.1.0's tests-locked.sh installed"
  run bash -c 'cd "$1" && bash cortex/bin/tests-locked.sh cortex/changes/x' _ "$d"
  assert_exit 0 "$CODE" "3.1.0's tests-locked.sh accepts the 3.0.0 lock"
  # the base moves to 3.1.0 too, so ci-gates.sh takes 3.1.0's scripts from it
  git -C "$d" -c advice.detachedHead=false checkout -q refs/remotes/origin/main
  upgrade_from "$c" "$d"
  commit_all "$d" "base: upgrade to 3.1.0"
  git -C "$d" update-ref refs/remotes/origin/main HEAD
  git -C "$d" checkout -q feature
  assert_true "fixture: the base has 3.1.0's ci-gates.sh" \
    grep -qF "# zz 3.1.0" <<<"$(git -C "$d" show origin/main:cortex/bin/ci-gates.sh)"
  run bash -c 'cd "$1" && bash cortex/bin/ci-gates.sh origin/main' _ "$d"
  assert_exit 0 "$CODE" "3.1.0's ci-gates.sh accepts the 3.0.0 lock"
}

case_major_refuses_open_lock() {
  # criterion 31, D12: a new major with an open lock refuses, naming it
  local c d before
  c="$(clone_v1)" || return 0; d="$(installed_from "$c")" || return 0
  lock_base "$d"
  release "$c" 4.0.0
  before="$(tree_snapshot "$d")"
  upgrade_from "$c" "$d"
  assert_exit 2 "$CODE" "a major upgrade with an open lock exits 2"
  assert_contains "$OUT$ERR" "cortex/changes/x" "the open lock is named"
  assert_true "A1: a refused line" has_line_starting "$OUT$ERR" "refused "
  assert_true "nothing changed" test "$(tree_snapshot "$d")" = "$before"
}

case_revert_consistent() {
  # criterion 33: reverting an upgrade's commit leaves the previous version
  # consistent: version, footprint and blocks agree; C13 passes; A7 shas
  local c d v1 rec
  c="$(clone_v1)" || return 0; d="$(installed_from "$c")" || return 0
  v1="$(git -C "$c" rev-parse HEAD)"
  fx "$c" unedited.md 'a2\n'
  append "$c/template/blocks/AGENTS.md" "- zz-upstream-rule"
  release "$c" 3.1.0
  upgrade_from "$c" "$d"
  assert_exit 0 "$CODE" "a clean upgrade exits 0"
  commit_all "$d" "upgrade to 3.1.0"
  git -C "$d" revert --no-edit HEAD >/dev/null
  assert_true "cortex/version is 3.0.0 again" test "$(sed -n 1p "$d/cortex/version")" = "3.0.0"
  assert_true "cortex/version names 3.0.0's commit" test "$(sed -n 2p "$d/cortex/version")" = "$v1"
  # Amendment 3, F1: the block's content and sha leave out the blank framing
  # lines inside the markers (was: block_content, every line between them)
  assert_true "the block is 3.0.0's" test "$(block_body "$d/AGENTS.md" agents)" = "$(git -C "$c" show v3.0.0:template/blocks/AGENTS.md)"
  block_body "$d/AGENTS.md" agents > "$TEST_TMP/blk"
  rec="$(footprint_records "$d" | awk -F'\t' '$1 == "block" && $2 == "AGENTS.md" { print $4 }')"
  assert_true "the footprint's block sha matches the block (A7)" test "$rec" = "$(git hash-object --no-filters "$TEST_TMP/blk")"
  run bash -c 'cd "$1" && bash cortex/bin/check.sh' _ "$d"
  assert_not_contains "$OUT" "[C13]" "C13 passes after the revert"
}

case_F1_blank_lines_unedited() {
  # Amendment 3, F1: a root block differing from 3.0.0's only in blank lines
  # is unedited: the upgrade replaces it with 3.1.0's, merging nothing
  local c d new rec
  c="$(clone_v1)" || return 0; d="$(installed_from "$c")" || return 0
  space_block "$d/AGENTS.md" agents
  if [ "$(block_body "$d/AGENTS.md" agents | grep -v '^$' || true)" != "$(grep -v '^$' "$c/template/blocks/AGENTS.md")" ] ||
    [ "$(block_body "$d/AGENTS.md" agents)" = "$(cat "$c/template/blocks/AGENTS.md")" ]; then
    fail "fixture: the block should differ from 3.0.0's in blank lines only"; return 0
  fi
  commit_all "$d" "a formatter's blank lines inside the block"
  append "$c/template/blocks/AGENTS.md" "- zz-upstream-rule"
  release "$c" 3.1.0
  upgrade_from "$c" "$d"
  assert_exit 0 "$CODE" "the upgrade exits 0"
  assert_not_contains "$OUT" "merged AGENTS.md" "the block is not merged as edited (F1)"
  assert_not_contains "$OUT" "conflict AGENTS.md" "no conflict (F1)"
  new="$(cat "$c/template/blocks/AGENTS.md")"
  assert_true "the block is 3.1.0's, the blank lines replaced with it (F1)" test "$(block_body "$d/AGENTS.md" agents)" = "$new"
  assert_true "the block is framed as install writes it (F1)" block_framed "$d/AGENTS.md" agents
  rec="$(footprint_records "$d" | awk -F'\t' '$1 == "block" && $2 == "AGENTS.md" { print $4 }')"
  assert_true "the record's sha is 3.1.0's block (F1, A7)" \
    test "$rec" = "$(git hash-object --no-filters "$c/template/blocks/AGENTS.md")"
}

# ---- spec 3.1.0 G2 (criteria 4-7): a reworded placeholder -----------------------------
#
# docs/specs/2026-10-09-v3.1-pilot-followups.md, G2: a conflicting hunk where
# both the installed version's text and the new version's are only HTML
# comments and blank lines is a placeholder hunk. When every conflicting hunk
# is one, the file takes the user's side of each and the upgrade prints
# "merged <path> (kept your text where cortex changed a placeholder)";
# otherwise the output is 3.0.0's: every hunk with git merge-file's markers.

PH_NOTE="(kept your text where cortex changed a placeholder)"
PH_OLD="<!-- List the project's conventions here, one line each. -->"
PH_NEW="<!-- Write the project's conventions here:\n     one line each, the style guide first. -->"
PH_USER="- zz-user-convention: tabs, not spaces\n- zz-user-convention: one change per pull request"

# ph_doc CONVENTIONS N4 N8 -> a document with a Conventions section holding
# CONVENTIONS (printf %b), and Notes lines n1-n8 with n4 and n8 as given
ph_doc() {
  printf '# Guide\n\n## Conventions\n\n%b\n\n## Notes\n\nn1\nn2\nn3\n%s\nn5\nn6\nn7\n%s\n' "$1" "$2" "$3"
}

# g2_run NAME... -> the upgraded repository. For each NAME, $G2/NAME.base is
# 3.0.0's template/$FX/NAME, the user commits $G2/NAME.user over the
# install, and 3.1.0's is $G2/NAME.new. A $G2/block.base, .user and .new
# (when present) do the same for the root agents block. The upgrade's output
# and exit status are saved in $G2/out and $G2/code.
g2_run() {
  local c d n
  c="$(cortex_clone 3.0.0)" || return 1
  printf '# Changelog\n' > "$c/CHANGELOG.md"
  mkdir -p "$c/template/$FX"
  for n in "$@"; do cp "$G2/$n.base" "$c/template/$FX/$n"; done
  [ ! -f "$G2/block.base" ] || cp "$G2/block.base" "$c/template/blocks/AGENTS.md"
  release "$c" 3.0.0
  d="$(installed_from "$c")" || return 1
  for n in "$@"; do cp "$G2/$n.user" "$d/$FX/$n"; done
  [ ! -f "$G2/block.user" ] || set_block "$d/AGENTS.md" agents "$(cat "$G2/block.user")"
  commit_all "$d" "the user's text"
  for n in "$@"; do cp "$G2/$n.new" "$c/template/$FX/$n"; done
  [ ! -f "$G2/block.new" ] || cp "$G2/block.new" "$c/template/blocks/AGENTS.md"
  release "$c" 3.1.0
  upgrade_from "$c" "$d"
  printf '%s\n' "$OUT" > "$G2/out"
  printf '%s\n' "$CODE" > "$G2/code"
  printf '%s\n' "$d"
}

g2_result() { OUT="$(cat "$G2/out")"; CODE="$(cat "$G2/code")"; }

# merge_expected D LABEL USER BASE NEW -> 3.0.0's result: git merge-file's
# output with the upgrade's labels (3.0.0 -> 3.1.0), run in D
merge_expected() {
  git -C "$1" merge-file -p -L "$2 (yours)" -L "$2 (cortex 3.0.0)" -L "$2 (cortex 3.1.0)" "$3" "$4" "$5" || true
}

# g2_summary_re MERGED CONFLICTS -> the upgrade summary's pattern
g2_summary_re() { printf '^upgrade 3\\.0\\.0 -> 3\\.1\\.0: [0-9]+ replaced, %s merged, %s conflicts$' "$1" "$2"; }

case_G2_placeholder_reworded() {
  # criterion 4: the user replaced the placeholder; 3.1.0 rewords it (a
  # multi-line comment) and changes n8, which merges cleanly
  local d p="$FX/ph.md"
  G2="$(mktemp -d "$TEST_TMP/g2.XXXXXX")"
  ph_doc "$PH_OLD" n4 n8 > "$G2/ph.md.base"
  ph_doc "$PH_USER" n4 n8 > "$G2/ph.md.user"
  ph_doc "$PH_NEW" n4 n8-up > "$G2/ph.md.new"
  assert_true "fixture: 3.0.0 merges these with a conflict" \
    bash -c '! git -C "$1" merge-file -p "$2" "$3" "$4" >/dev/null' _ "$TEST_TMP" "$G2/ph.md.user" "$G2/ph.md.base" "$G2/ph.md.new"
  d="$(g2_run ph.md)" || return 0; g2_result
  assert_exit 0 "$CODE" "a placeholder-only conflict exits 0"
  assert_line "$OUT" "merged $p $PH_NOTE" "the merged line says the user's text was kept"
  assert_not_contains "$OUT" "conflict $p" "not reported as a conflict"
  ph_doc "$PH_USER" n4 n8-up > "$G2/expected"
  assert_same_file "$G2/expected" "$d/$p" "the user's text, cortex's other change merged, no markers"
  assert_file_not_contains "$d/$p" "<<<<<<<" "no conflict markers"
  assert_true "counted as merged, not as a conflict" grep -qE "$(g2_summary_re 1 0)" <<<"$(last_line "$OUT")"
}

case_G2_placeholder_and_real_conflict() {
  # criterion 5: the same file with a second, real conflicting hunk (n4):
  # 3.0.0's output, both hunks with markers
  local d p="$FX/ph.md"
  G2="$(mktemp -d "$TEST_TMP/g2.XXXXXX")"
  ph_doc "$PH_OLD" n4 n8 > "$G2/ph.md.base"
  ph_doc "$PH_USER" n4-user n8 > "$G2/ph.md.user"
  ph_doc "$PH_NEW" n4-up n8 > "$G2/ph.md.new"
  d="$(g2_run ph.md)" || return 0; g2_result
  merge_expected "$d" "$p" "$G2/ph.md.user" "$G2/ph.md.base" "$G2/ph.md.new" > "$G2/expected"
  assert_true "fixture: git merge-file leaves two conflicts" test "$(grep -c '^<<<<<<< ' "$G2/expected" || true)" = 2
  assert_exit 1 "$CODE" "a real conflict exits 1"
  assert_line "$OUT" "conflict $p" "reported as a conflict"
  assert_not_contains "$OUT" "$PH_NOTE" "no kept-your-text line"
  assert_same_file "$G2/expected" "$d/$p" "the file is 3.0.0's merge: both hunks with markers, same format"
  assert_true "counted as a conflict" grep -qE "$(g2_summary_re 0 1)" <<<"$(last_line "$OUT")"
}

case_G2_one_side_placeholder() {
  # criterion 6: only one side of the conflicting hunk is a placeholder:
  # cortex replaced its comment with text (new.md), or turned its text into
  # a comment (old.md); either is a real conflict
  local d n
  G2="$(mktemp -d "$TEST_TMP/g2.XXXXXX")"
  ph_doc "$PH_OLD" n4 n8 > "$G2/new.md.base"
  ph_doc "$PH_USER" n4 n8 > "$G2/new.md.user"
  ph_doc "- zz-cortex-default-convention" n4 n8 > "$G2/new.md.new"
  ph_doc "- zz-cortex-old-convention" n4 n8 > "$G2/old.md.base"
  ph_doc "$PH_USER" n4 n8 > "$G2/old.md.user"
  ph_doc "$PH_NEW" n4 n8 > "$G2/old.md.new"
  d="$(g2_run new.md old.md)" || return 0; g2_result
  assert_exit 1 "$CODE" "real conflicts exit 1"
  for n in new.md old.md; do
    merge_expected "$d" "$FX/$n" "$G2/$n.user" "$G2/$n.base" "$G2/$n.new" > "$G2/$n.expected"
    assert_true "fixture: git merge-file leaves a conflict in $n" grep -q '^<<<<<<< ' "$G2/$n.expected"
    assert_line "$OUT" "conflict $FX/$n" "$n: reported as a conflict"
    assert_not_contains "$OUT" "merged $FX/$n" "$n: not reported merged"
    assert_same_file "$G2/$n.expected" "$d/$FX/$n" "$n: 3.0.0's merge, with markers"
  done
}

# block_doc CONVENTIONS FIRST -> the root block's source: this checkout's
# block with its first line replaced by FIRST and a placeholder section
# holding CONVENTIONS (printf %b) appended
block_doc() {
  awk -v f="$2" 'NR == 1 { print f; next } { print }' "$ROOT/template/blocks/AGENTS.md"
  printf '\n%b\n' "$1"
}

case_G2_block_placeholder_reworded() {
  # criterion 7, as criterion 4: the root agents block
  local d
  G2="$(mktemp -d "$TEST_TMP/g2.XXXXXX")"
  block_doc "<!-- zz project rules go here. -->" "## cortex" > "$G2/block.base"
  block_doc "- zz-user-rule: run make test" "## cortex" > "$G2/block.user"
  block_doc "<!-- zz project rules go here:\n     one line each. -->" "## cortex" > "$G2/block.new"
  d="$(g2_run)" || return 0; g2_result
  assert_exit 0 "$CODE" "a placeholder-only conflict in the block exits 0"
  assert_line "$OUT" "merged AGENTS.md $PH_NOTE" "the merged line says the user's text was kept"
  assert_not_contains "$OUT" "conflict AGENTS.md" "not reported as a conflict"
  block_body "$d/AGENTS.md" agents > "$G2/block.result"
  assert_same_file "$G2/block.user" "$G2/block.result" "the block is the user's text, no markers"
  assert_true "one agents block" test "$(block_count "$d/AGENTS.md" agents)" = 1
}

case_G2_block_placeholder_and_real_conflict() {
  # criterion 7, as criterion 5: the block with a second, real conflicting
  # hunk (its first line)
  local d
  G2="$(mktemp -d "$TEST_TMP/g2.XXXXXX")"
  block_doc "<!-- zz project rules go here. -->" "## cortex" > "$G2/block.base"
  block_doc "- zz-user-rule: run make test" "## cortex (ours)" > "$G2/block.user"
  block_doc "<!-- zz project rules go here:\n     one line each. -->" "## cortex (upstream)" > "$G2/block.new"
  d="$(g2_run)" || return 0; g2_result
  merge_expected "$d" AGENTS.md "$G2/block.user" "$G2/block.base" "$G2/block.new" > "$G2/expected"
  assert_true "fixture: git merge-file leaves two conflicts" test "$(grep -c '^<<<<<<< ' "$G2/expected" || true)" = 2
  assert_exit 1 "$CODE" "a real conflict in the block exits 1"
  assert_line "$OUT" "conflict AGENTS.md" "reported as a conflict"
  assert_not_contains "$OUT" "$PH_NOTE" "no kept-your-text line"
  block_body "$d/AGENTS.md" agents > "$G2/block.result"
  assert_same_file "$G2/expected" "$G2/block.result" "the block is 3.0.0's merge: both hunks with markers"
}

run_case "criterion 21: an unedited file is replaced; cortex/version updated" case_unedited_replaced
run_case "criterion 22: a user-edited file is kept" case_edited_kept
run_case "criterion 23: non-overlapping edits merge" case_both_merged
run_case "criterion 24: overlapping edits conflict; C14 until resolved" case_conflict
run_case "criterion 25: added, removed and user-deleted files" case_added_removed_deleted
run_case "criterion 26: project files and cortex/config untouched; new key printed" case_project_files_and_config
run_case "criterion 28: the agents block and design rules merge" case_block_and_design_rules_merged
run_case "criterion 30: CHANGELOG notes for every version passed" case_changelog_notes
run_case "criterion 20: a dirty work tree refused" case_dirty_refused
run_case "criterion 27: a clone missing the installed commit" case_missing_commit
run_case "criterion 29: same version, another commit, upgrades" case_same_version_other_commit
run_case "criterion 31: a minor upgrade keeps a 3.0.0 lock valid" case_minor_keeps_locks
run_case "criterion 31: a major upgrade refuses an open lock" case_major_refuses_open_lock
run_case "criterion 33: reverting an upgrade leaves a consistent install" case_revert_consistent
run_case "F1: a root block differing only in blank lines upgrades as unedited" case_F1_blank_lines_unedited
run_case "G2 criterion 4: a reworded placeholder keeps the user's text" case_G2_placeholder_reworded
run_case "G2 criterion 5: plus a real conflicting hunk: 3.0.0's output" case_G2_placeholder_and_real_conflict
run_case "G2 criterion 6: only one side a placeholder is a real conflict" case_G2_one_side_placeholder
run_case "G2 criterion 7: the root block, as criterion 4" case_G2_block_placeholder_reworded
run_case "G2 criterion 7: the root block, as criterion 5" case_G2_block_placeholder_and_real_conflict
summary
