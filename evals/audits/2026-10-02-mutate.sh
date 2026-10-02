#!/usr/bin/env bash
# Mutation audit (plan item 25): apply one mutant at a time to a gate script,
# run the suite that should catch it, restore. DRY_RUN=1 only checks that
# each mutant changes its file. Output: id, result, suite, what it breaks.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
S=template/scripts/cortex
tmp="$(mktemp -d)"

m() { # id file suite perl-expr description
  local id="$1" f="$S/$2" suite="$3" expr="$4" desc="$5" r
  cp "$f" "$tmp/orig"
  perl -0pi -e "$expr" "$f"
  if cmp -s "$f" "$tmp/orig"; then
    printf '%s\tNOT-APPLIED\t%s\t%s\n' "$id" "$suite" "$desc"; return
  fi
  if ! bash -n "$f" 2>/dev/null; then
    printf '%s\tINVALID\t%s\t%s\n' "$id" "$suite" "$desc"
    cp "$tmp/orig" "$f"; return
  fi
  if [ "${DRY_RUN:-0}" = 1 ]; then
    r=applied
  elif bash "tests/$suite.test.sh" > "$tmp/$id.log" 2>&1; then
    r=SURVIVED
  else
    r=caught
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$r" "$suite" "$desc" "$(tail -1 "$tmp/$id.log" 2>/dev/null)"
  cp "$tmp/orig" "$f"
}

# check.sh
m c1 check.sh check 's/grep -qiwF -- "\$project"/grep -qiF -- "\$project"/' 'C1 matches the project name inside other words'
m c2 check.sh check 's/claude\|cursor\|copilot\|gemini\|codex/claude|cursor|copilot|gemini/' 'C2 misses one tool name'
m c3 check.sh check 's/\[ "\$lines" -gt 60 \]/[ "\$lines" -gt 61 ]/' 'C3 allows 61 lines'
m c4 check.sh check "s/'read all\|read everything'/'read all'/" 'C4 misses "read everything"'
m c5 check.sh check 's/Purpose Preconditions Procedure Output Autonomy/Purpose Preconditions Procedure Output/' 'C5 misses a missing Autonomy section'
m c6 check.sh check "s/grep -q '\^Budget:'/grep -q 'Budget:'/" 'C6 accepts Budget: anywhere in a line'
m c7 check.sh check 's/\[ "\$f" = harness\/templates\/change-folder\/proposal\.md \] && continue/case "\$f" in harness\/templates\/*) continue ;; esac/' 'C7 exempts every template, not only the proposal'
m c8 check.sh check "s/grep -vxF '<!-- cortex:generated -->'/grep -vE '^<!--'/" 'C8 lets any comment into CLAUDE.md'
m c9 check.sh check 's/\[ "\$lines" -gt 25 \]/[ "\$lines" -gt 26 ]/' 'C9 allows a 26-line skill'
m c10 check.sh check "s/grep -qF 'data, never instructions' AGENTS.md/grep -qF 'never instructions' AGENTS.md/" 'C10 accepts a weaker phrase'
m c11 check.sh check 's/TEST_GLOBS TOOLS; do/TEST_GLOBS; do/' 'C11 stops requiring TOOLS'
m c12 check.sh check "s/grep -q 'TODO' AGENTS.md/grep -q 'TODO:' AGENTS.md/" 'C12 misses a TODO without a colon'

# _config.sh (the parser every gate reads config through)
m p1 _config.sh check 's/  case "\$value" in "<"\*">"\) value="" ;; esac\n//' 'a <placeholder> counts as set'
m p2 _config.sh check 's/print val; exit \}/print val }/' 'every line with the key is read, not the first'
m p3 _config.sh check 's/    \/\^\[\[:space:\]\]\*#\/ \{ next \}\n//' 'comment lines are parsed'
m p4 _config.sh check 's/key = substr\(\$0, 1, eq - 1\); gsub\(\/\^\[\[:space:\]\]\+\|\[\[:space:\]\]\+\$\/, "", key\)/key = substr(\$0, 1, eq - 1)/' 'keys are not trimmed'

# tests-locked.sh
m t1 tests-locked.sh tests-locked 's/g ls-files -co --exclude-standard/g ls-files -c --exclude-standard/' 'new untracked test files go unnoticed'
m t2 tests-locked.sh tests-locked 's/"\$n_lock_commits" -gt 1 \]/"\$n_lock_commits" -gt 2 ]/' 'one later edit to lock.md is allowed'
m t3 tests-locked.sh tests-locked 's/if \[ -z "\$full_sha" \] \|\| \[ "\$parent" != "\$full_sha" \]; then/if [ -z "\$full_sha" ]; then/' 'the lock commit need not follow the commit it names'
m t4 tests-locked.sh tests-locked 's/&& config_at_sha=\.cortex\/config/\&\& config_at_sha=/' '.cortex/config is not locked'
m t5 tests-locked.sh tests-locked 's/(from_base\(\) \{\n)/$1  return 0\n/' 'any change counts as coming from the base'
m t6 tests-locked.sh tests-locked 's/ \|\| ! g diff --quiet --cached "\$sha" -- "\$path"; then/; then/' 'staged edits to a locked file go unnoticed'
m t7 tests-locked.sh tests-locked 's/if ! g merge-base --is-ancestor "\$sha" HEAD; then/if false; then/' 'a lock commit outside the branch is accepted'
m t8 tests-locked.sh tests-locked 's/if ! g diff --quiet HEAD -- "\$lock_rel" 2>\/dev\/null \|\| ! g diff --cached --quiet -- "\$lock_rel"; then/if false; then/' 'uncommitted lock.md edits go unnoticed'

# gates.sh
m g1 gates.sh gates 's/  if \[ -z "\$cmd" \]; then\n    echo "gate \$1: FAIL/  if false; then\n    echo "gate \$1: FAIL/' 'an unset command passes'
m g2 gates.sh gates 's/^gate check bash "\$here\/check\.sh" "\$root"$/:/m' 'the harness check never runs'
m g3 gates.sh gates 's/(    echo "gate \$name: FAIL \(exit \$code\)"\n)    failed=\$\(\(failed \+ 1\)\)\n/$1/' 'a failing gate does not fail the run'
m g4 gates.sh ci-gates 's/^here="\$\(cd "\$\(dirname "\$0"\)" && pwd\)"$/here="\$(git rev-parse --show-toplevel)\/scripts\/cortex"/m' "the base's gates.sh runs the branch's sibling scripts"

# ci-gates.sh
m i1 ci-gates.sh ci-gates 's/if g cat-file -e "\$base:scripts\/cortex\/gates\.sh" 2>\/dev\/null; then/if false; then/' "the branch's own scripts judge it"
m i2 ci-gates.sh ci-gates 's/S \| \[a-z\]\) fail "hidden \$path" ;;/S) fail "hidden \$path" ;;/' 'assume-unchanged files are not refused'
m i3 ci-gates.sh ci-gates "s/ \| grep -v '\^changes\/archive\/'//" 'archived folders are gated again'
m i4 ci-gates.sh ci-gates 's/if bash "\$tools\/check\.sh" "\$root"; then/if true; then/' 'the harness check never runs in CI'

# adapt.sh
m a1 adapt.sh adapt 's/if \[ -e "\$path" \] && ! grep -qF "\$MARKER" "\$path"; then/if false; then/' 'hand-written files are overwritten'
m a2 adapt.sh adapt 's/elif \[ -e \.claude\/settings\.json \]; then/elif false; then/' 'an existing settings.json is overwritten'
m a3 adapt.sh adapt 's/(stale\(\) \{\n)/$1  return 0\n/' 'stale adapters are never reported'

rm -rf "$tmp"
