#!/usr/bin/env bash
# Tests for scripts/install.sh (spec: docs/specs/2026-09-23-v2-scripts.md,
# acceptance criteria 1-3).
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
  for f in check.sh tests-locked.sh adapt.sh; do
    assert_true "scripts/cortex/$f is executable" test -x "$d/scripts/cortex/$f"
  done
  assert_same_file "$ROOT/VERSION" "$d/.cortex/version" ".cortex/version matches VERSION"
  assert_line "$OUT" "created .cortex/version" "reports created .cortex/version"
  assert_line "$OUT" "install: $((n + 1)) created, 0 unchanged, 0 skipped" "summary line counts every file"
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
  assert_line "$OUT" "install: 0 created, $((n + 1)) unchanged, 0 skipped" "second-run summary"
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

case_version_mismatch_warns() {
  local d new
  d="$(fresh_install)"
  printf '0.0.1\n' > "$d/.cortex/version"
  new="$(cat "$ROOT/VERSION" | tr -d '\r\n')"
  run "$INSTALL" "$d"
  assert_exit 0 "$CODE" "version mismatch still exits 0"
  assert_contains "$OUT$ERR" "warning: installed version 0.0.1, template version $new" "warns about version mismatch"
  assert_true ".cortex/version left as-is" test "$(cat "$d/.cortex/version")" = "0.0.1"
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

case_subdir_of_git_repo() {
  local d
  d="$(new_git_repo)"
  mkdir -p "$d/sub"
  run "$INSTALL" "$d/sub"
  assert_exit 0 "$CODE" "a directory inside a git work tree is accepted"
  assert_file_exists "$d/sub/AGENTS.md" "installed at the given path"
}

run_case "no argument -> exit 2" case_no_argument
run_case "missing target dir -> exit 2" case_missing_dir
run_case "non-git dir -> exit 2" case_non_git_dir
run_case "fresh install creates every template file (AC1)" case_fresh_install
run_case "second run is idempotent (AC1)" case_second_run_idempotent
run_case "differing existing file is skipped (AC2)" case_existing_differing_file_skipped
run_case "version mismatch warns, keeps file" case_version_mismatch_warns
run_case "never deletes or modifies user files" case_never_deletes
run_case "target inside a git work tree" case_subdir_of_git_repo
summary
