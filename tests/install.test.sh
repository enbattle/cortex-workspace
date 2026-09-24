#!/usr/bin/env bash
# Tests for scripts/install.sh (spec: docs/specs/2026-09-23-v2-scripts.md,
# acceptance criteria 1-3, 13 and 19).
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

INSTALL="$ROOT/scripts/install.sh"

# every file under template/, relative, sorted (includes dotfiles, .gitkeep)
template_files() {
  [ -d "$ROOT/template" ] || { echo "template/ missing" >&2; return 1; }
  (cd "$ROOT/template" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
}

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
    assert_same_file "$ROOT/template/$f" "$d/$f" "installed copy of $f is identical"
    assert_line "$OUT" "created $f" "reports created $f"
  done <<<"$files"
  assert_file_exists "$d/changes/archive/.gitkeep" ".gitkeep is installed"
  assert_file_exists "$d/.cortex/config" ".cortex/config is installed"
  for f in check.sh tests-locked.sh adapt.sh gates.sh; do
    assert_true "scripts/cortex/$f is executable" test -x "$d/scripts/cortex/$f"
  done
  assert_same_file "$ROOT/VERSION" "$d/.cortex/version" ".cortex/version matches VERSION"
  assert_line "$OUT" "created .cortex/version" "reports created .cortex/version"
  assert_same_file "$ROOT/docs/01-design-rules.md" "$d/.cortex/design-rules.md" ".cortex/design-rules.md matches docs/01-design-rules.md (A5)"
  assert_line "$OUT" "created .cortex/design-rules.md" "reports created .cortex/design-rules.md (A5)"
  assert_line "$OUT" "install: $((n + 2)) created, 0 unchanged, 0 skipped" "summary counts template files + design rules + version"
  # never runs git commands that write
  assert_true "no commit created" test -z "$(git -C "$d" rev-list --all 2>/dev/null)"
  assert_true "nothing staged" test -z "$(git -C "$d" ls-files)"
}

case_second_run_idempotent() {
  local d n
  d="$(fresh_install)"
  n=$(template_files | grep -c . || true)
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "second run exits 0"
  assert_true "second run prints no created lines" test -z "$(grep '^created ' <<<"$OUT" || true)"
  assert_contains "$OUT" "0 created" "second run reports 0 created"
  assert_line "$OUT" "unchanged .cortex/version" "version reported unchanged"
  assert_line "$OUT" "unchanged AGENTS.md" "AGENTS.md reported unchanged"
  assert_line "$OUT" "unchanged .cortex/design-rules.md" "design rules reported unchanged (A5)"
  assert_line "$OUT" "install: 0 created, $((n + 2)) unchanged, 0 skipped" "second-run summary"
}

case_existing_differing_file_skipped() {
  local d
  d="$(new_git_repo)"
  printf '# my own agents file\n' > "$d/AGENTS.md"
  cp "$d/AGENTS.md" "$TEST_TMP/agents.orig"
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "install with a skipped file exits 0"
  assert_line "$OUT" "skipped AGENTS.md (exists, differs)" "differing AGENTS.md reported skipped"
  assert_not_contains "$OUT" "created AGENTS.md" "AGENTS.md not reported created"
  assert_same_file "$TEST_TMP/agents.orig" "$d/AGENTS.md" "existing AGENTS.md untouched"
  assert_contains "$OUT" "1 skipped" "summary counts the skip"
  assert_file_exists "$d/scripts/cortex/check.sh" "other files still installed"
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
  assert_file_absent "$ROOT/template/.cortex/design-rules.md" "template has no separate design-rules copy"
}

case_existing_differing_design_rules_skipped() {
  local d
  d="$(new_git_repo)"
  mkdir -p "$d/.cortex"
  printf '# my local rules\n' > "$d/.cortex/design-rules.md"
  cp "$d/.cortex/design-rules.md" "$TEST_TMP/rules.orig"
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "install exits 0"
  assert_line "$OUT" "skipped .cortex/design-rules.md (exists, differs)" "differing design rules skipped (A5)"
  assert_same_file "$TEST_TMP/rules.orig" "$d/.cortex/design-rules.md" "existing design rules untouched"
  assert_contains "$OUT" "1 skipped" "summary counts the skip"
}

case_design_rules_idempotent() {
  local d
  d="$(fresh_install)"
  assert_same_file "$ROOT/docs/01-design-rules.md" "$d/.cortex/design-rules.md" "installed by the first run"
  run "$INSTALL" "$d"
  assert_not_contains "$OUT" "created .cortex/design-rules.md" "second run does not recreate it"
  assert_line "$OUT" "unchanged .cortex/design-rules.md" "second run reports it unchanged"
  assert_same_file "$ROOT/docs/01-design-rules.md" "$d/.cortex/design-rules.md" "still identical after second run"
}

# ---- AC19 (B3, B6) ---------------------------------------------------------------

FILEMODE_NOTE="note: this repository ignores file modes; after committing, run git update-index --chmod=+x scripts/cortex/*.sh"

# tree_files DIR -> every file under DIR outside .git/, relative, sorted
tree_files() {
  (cd "$1" && find . -path ./.git -prune -o -type f -print | sed 's|^\./||' | LC_ALL=C sort)
}

case_version_mismatch_refused() {
  local d new before
  d="$(new_git_repo)"
  mkdir -p "$d/.cortex"
  printf '0.0.1\n' > "$d/.cortex/version"
  printf 'mine\n' > "$d/README.md"
  before="$(tree_files "$d")"
  new="$(tr -d '\r\n' < "$ROOT/VERSION")"
  run "$INSTALL" "$d"
  assert_exit 2 "$CODE" "version mismatch exits 2"
  assert_contains "$ERR" "error: this repository has cortex 0.0.1 installed; upgrading to $new is not supported yet (see docs/02-extensions.md §4)" "mismatch error on stderr"
  assert_true "nothing copied on a version mismatch" test "$(tree_files "$d")" = "$before"
  assert_file_absent "$d/AGENTS.md" "no template file created"
  assert_true ".cortex/version left as-is" test "$(cat "$d/.cortex/version")" = "0.0.1"
  assert_not_contains "$OUT" "created " "no created lines"
}

case_version_mismatch_partial_install() {
  # an existing older install with a template file removed: still refused,
  # the missing file is not restored
  local d before
  d="$(fresh_install)"
  printf '1.9.9\n' > "$d/.cortex/version"
  rm "$d/AGENTS.md"
  before="$(tree_files "$d")"
  run "$INSTALL" "$d"
  assert_exit 2 "$CODE" "mismatch over an existing install exits 2"
  assert_contains "$ERR" "error: this repository has cortex 1.9.9 installed" "names the installed version"
  assert_true "nothing copied" test "$(tree_files "$d")" = "$before"
  assert_file_absent "$d/AGENTS.md" "removed file not restored"
}

case_version_equal_accepted() {
  local d
  d="$(new_git_repo)"
  mkdir -p "$d/.cortex"
  cp "$ROOT/VERSION" "$d/.cortex/version"
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "matching version is accepted"
  assert_line "$OUT" "unchanged .cortex/version" "version reported unchanged"
  assert_file_exists "$d/AGENTS.md" "template installed"
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
  local d
  d="$(new_git_repo)"
  git -C "$d" config core.filemode false
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "install exits 0 with core.filemode=false"
  assert_contains "$OUT$ERR" "$FILEMODE_NOTE" "prints the filemode note"
}

case_filemode_true_no_note() {
  local d
  d="$(new_git_repo)"
  git -C "$d" config core.filemode true
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "install exits 0 with core.filemode=true"
  assert_not_contains "$OUT$ERR" "ignores file modes" "no filemode note when modes are tracked"
}

case_gitattributes() {
  local d
  assert_file_exists "$ROOT/template/.gitattributes" "template ships .gitattributes"
  if grep -qxF '*.sh text eol=lf' "$ROOT/template/.gitattributes" 2>/dev/null; then pass
  else fail "template .gitattributes has the line '*.sh text eol=lf'"; fi
  d="$(new_git_repo)"
  run "$INSTALL" "$d"
  assert_line "$OUT" "created .gitattributes" "reports created .gitattributes"
  assert_same_file "$ROOT/template/.gitattributes" "$d/.gitattributes" "installed .gitattributes identical"
}

run_case "no argument -> exit 2" case_no_argument
run_case "missing target dir -> exit 2" case_missing_dir
run_case "non-git dir -> exit 2" case_non_git_dir
run_case "fresh install creates every template file (AC1)" case_fresh_install
run_case "second run is idempotent (AC1)" case_second_run_idempotent
run_case "differing existing file is skipped (AC2)" case_existing_differing_file_skipped
run_case "never deletes or modifies user files" case_never_deletes
run_case "design rules come from docs/, not template/ (A5)" case_design_rules_not_in_template
run_case "differing design rules skipped (A5)" case_existing_differing_design_rules_skipped
run_case "design rules idempotent (AC13)" case_design_rules_idempotent
run_case "AC19 version mismatch: exit 2, nothing copied" case_version_mismatch_refused
run_case "AC19 version mismatch over an old install" case_version_mismatch_partial_install
run_case "matching version accepted" case_version_equal_accepted
run_case "AC19 non-root target: exit 2, nothing copied" case_non_root_target_refused
run_case "AC19 filemode note when core.filemode=false" case_filemode_false_note
run_case "no filemode note when core.filemode=true" case_filemode_true_no_note
run_case "AC19 .gitattributes installed" case_gitattributes
summary
