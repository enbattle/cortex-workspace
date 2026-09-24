# Pilot log (working notes)

cortex state used: branch v2-single-repo-template at cd98457 PLUS uncommitted working-tree edits
(README, docs, tests-locked.sh, tests/lib.sh modified; INSTALL.md, AGENTS.md, CHANGELOG.md untracked). Pilot ran against the working tree.

## Step 1
- slugkit created, 4 tests pass, commit 5e32880 on main. Node v22.14.0.

## Step 2 install
- git switch -c cortex-install; install.sh: 40 created, 0 skipped. Clear output.
- OBS: check.sh prints `check: ok` BEFORE any placeholder is filled (PROJECT_NAME=<project name>, TOOLS=<tools>, TODOs everywhere).
- OBS: adapt.sh with TOOLS=<tools> exits 0 and prints nothing at all.
- OBS: BUILD_CMD/TEST_CMD/LINT_CMD in .cortex/config are read by NO script (grep scripts/: zero hits). AGENTS.md duplicates them by hand ("fill in from .cortex/config"). Two sources of truth, one unused.
- HUMAN (interview): name slugkit; one-liner; build/lint = node --check src/slugify.js (no real build or linter exists: lint requirement forced a fake); test = node --test; globs *.test.js; tools claude.
- HUMAN: principles: gave 3 (no runtime deps; pure functions; invalid args throw TypeError). Declined 5-8: "it's a 12-line library". INSTALL asks for 5-8 but constitution has ONE TODO slot (#4); adding 3 meant renumbering 4..14 -> 4..16 by hand; my first scripted renumber broke (two "5."/"6."), fixed manually. No check catches duplicate numbers.
- OBS: constitution project principles live under harness/policies/ -> contradicts R1 "harness upgrade is a file copy"; an upgrade copy would clobber them. Also R1 says harness never names "its domain terms"; a natural project principle ("slugify output only [a-z0-9-]") would violate R1 in spirit but C1 only greps PROJECT_NAME.
- HUMAN: deferred-practices: keep all (none can be ruled out as "never").
- glossary: slug, separator, word. architecture: 2 rows.
- adapt.sh: wrote CLAUDE.md, .claude/* (13 files). check: ok (first try, no failures).
- Smoke test (INSTALL step 6): fresh general-purpose agent ran onboard.md; answered both check questions correctly from files. Its confusion list:
  - R4/R11/R12 cited in installed commands (test-first, implement, review, tests-locked.sh) but defined nowhere in the installed repo (design rules stay in cortex docs/01-design-rules.md). REAL.
  - "branch named for the change folder": exact format undefined. REAL.
  - universal invocation in Claude Code runs in-session (not fresh) for test-first/implement/review; onboard step 3 doesn't warn. REAL.
  - onboard "stop when answered correctly" needs a live grader; INSTALL step 6 says give fresh context ONLY the command (no human to grade).
  - review.md says reviewer writes review-findings.md; claude adapter reviewer has no edit tools -> caller writes. Split only visible in adapter.
  - pre-existing: slugify(null) -> "null" violates constitution #6 as I (human) wrote it. (my own doing; shows new principles can instantly make existing code non-compliant with no prompt to note it)
- Committed install on cortex-install (e0...); HUMAN: approved ff-merge into main. FRICTION: INSTALL step 7 says don't merge, but says nothing about the first change needing the install on its base; a user starting spec-new from main would have no harness. Plan branch base unclear.

## Step 3 spec-new / spec-clarify
- ORCH: spec-new created changes/20260923-slugify-maxlength/ in main's working tree. spec-new/spec-clarify name NO branch and NO commit; folder sits uncommitted on the default branch until test-first creates a branch. Nothing says who commits proposal/design/tasks.
- HUMAN: agreed the draft (AC1-4 + 2 open questions).
- clarify round 1 (5 Qs): first word > maxLength; valid maxLength; invalid options; empty slug; truncate before/after trim.
- HUMAN DECISIONS: first word too long -> hard cut to maxLength (only mid-word cut; rejected '' and whole-word). maxLength integer>=1 else TypeError (Infinity throws). options null/number/string -> TypeError; arrays/functions unspecified (non-goal). Accepted that slugify(s, null) now throws (was ignored) - tiny compat break, recorded in design.
- 1 round sufficed. Criteria AC1-AC7 all automatable.
- OBS: design.md "Approach" necessarily describes the implementation algorithm; test-first is told to "read only the change folder ... Don't read or plan the implementation". The change folder IS a plan of the implementation. R12's bias argument is undercut.
- OBS: "Approved-by:" has no format; I wrote "Pilot Operator (pilot operator acting as user)". Nothing checks it's non-empty except the agent reading it.
- HUMAN wrote approval line.

## Step 4 test-first (fresh general-purpose agent)
- Created branch 20260923-slugify-maxlength (name = folder basename; its own choice). Wrote test/slugify-maxlength.test.js (22 tests incl. oracle + sweep over 309 inputs x maxLength 1..42), commit 5c154ae (test file only).
- ORCH verified: tests-locked.sh -> "tests-locked: 1 file(s) unchanged since 5c154ae" exit 0. node --test: 8 pass / 18 fail. Failures = untruncated output ('hello-big-world' vs 'hello-big') and 'Missing expected exception' -> right reason.
- FRICTION: test-first step 3 "a test that passes before the implementation exists tests nothing; rewrite it" conflicts with regression criteria (AC1 "unchanged for every input", AC2 "returned unchanged"). Agent kept 4 pre-passing tests as regression guards and flagged it. Command has no carve-out.
- FRICTION: change folder (proposal/design/tasks incl. approval + lock) still UNTRACKED after test-first: spec-new/clarify never commit, test-first's commit is "tests only". The lock sha thus doesn't include the approved spec; approval isn't in history.
- FRICTION: test-first appended Tests-locked-at/## Locked tests AFTER "## Gate output" (template comment says "at the end of this file"). tasks-locked.sh's awk ends the locked list at the next line starting '#'; any gate output later pasted after it that starts with "- " would be parsed as a locked path, "# tests 26" would end it. Fragile ordering.
- OBS: tests carry a reference oracle (expectedTruncation) = a second implementation written by the test writer. Fine here; worth noting a review of the tests themselves is not in any command.

## Step 5 planted lock checks (throwaway copies, deleted)
- edit locked test -> "LOCK modified: test/slugify-maxlength.test.js" exit 1. OK.
- untracked test/extra.test.js -> "LOCK added: test/extra.test.js" exit 1. OK. Both together -> both lines. OK.
- GAP (must fix): editing PRE-EXISTING test/slugify.test.js (not in Locked list, existed at sha) -> exit 0, undetected. implement.md forbids only locked tests & new test files; weakening an existing regression test passes every gate.
- GAP: untracked test/helper.js containing a test -> node --test RUNS it (Node default discovery includes test/**/*.js) but TEST_GLOBS=*.test.js misses it -> exit 0. INSTALL asks "how test files are named", not "what does the runner discover".
- new fixture test/fixtures/new.json -> exit 0 (not covered; arguably fine).

## Step 6 implement (recap)
- Three impl commits c01c5d8 (T1 validation), 8a8f88f (T2 truncation), 041dbbb (T3 JSDoc) on branch 20260923-slugify-maxlength. Change folder first committed in c01c5d8.

## Step 7 gates + review
- ORCH gates @041dbbb: tests-locked.sh -> "tests-locked: 1 file(s) unchanged since 5c154ae" exit 0; node --test -> 26 pass / 0 fail exit 0; check.sh -> "check: ok" exit 0. Tree clean before review.
- Reviewer: fresh general-purpose agent, prompt = only the one-liner. ~57k tokens, 7 tool uses, 81 s. Gate re-run matched mine.
- VERDICT: request changes (round 1). Findings:
  1. BLOCKING: `['a','b'].map(slugify)` now throws (index passed as options -> AC7 TypeError). No migration/version bump/changelog/JSDoc warning -> constitution 2. ORCH verified the throw. REAL and non-obvious: human (me) approved AC7 thinking only of null/number/string, never of callback use. Spec-level miss that spec-clarify didn't surface; the reviewer correctly routes fix (b) back through spec-clarify.
  2. minor: tasks.md ## Gate output missing implementer's gate paste (review.md precondition says "stop"; reviewer proceeded and ran gates itself instead).
  3. minor: change folder first committed after the test lock -> history can't prove approval preceded lock (same as step 4 friction).
  4. minor: design.md lacks ## As built (lastIndexOf vs slice deviation recorded only in tasks.md).
  Pre-existing: String(input) coercion vs constitution 6 (non-goal).
  Probed-and-sound paragraph present (hostile maxLength values, getters, 1M-char input, AC1-7 by execution).
- Working tree: git status --porcelain -uall empty before and after the reviewer -> unchanged. ORCH then wrote changes/.../review-findings.md (round 1), now the only untracked file. Did NOT run implement again.

## Step 8 golden task
- cp -R slugkit -> slugkit-golden. First-choice bugs (off-by-one at exactly maxLength, trailing '-') would be caught: the locked sweep (309 inputs x maxLength 1..42 vs an oracle) is dense for short inputs. So planted a subtler one the sweep can't reach (inputs < 40 chars):
  commit 2b2c0e6 "perf(slugify): bound the work done on very long inputs when maxLength is set": pre-slices the INPUT to Math.max(256, maxLength*4) chars before building the slug. Wrong for long inputs with many non-alnum chars: `' '.repeat(250)+'helloworld again'`, max 10 -> 'hellow' (want 'helloworld'); 40x'Привет '+'hello world', max 20 -> '' (want 'hello-world').
- Tests: 26/26 pass, tests-locked ok, check ok -> gates MISS it.
- Reviewer (fresh, same one-liner, ~50k tokens, 63 s): REQUEST CHANGES; finding #1 HIGH names exactly the pre-slice, with repros and a 200k-sample differential (27,437 mismatches), cites AC3/AC4 + design "build the full slug exactly as today". -> PASS per rubric. Also flagged 2b2c0e6 as unplanned work not in tasks.md (medium), missing gate paste + no >256-char test (medium), history order (low). No false positives beyond those shared with the real review.
  Notably it did NOT raise the .map(slugify) finding that the first reviewer made blocking: reviewer-to-reviewer variance on the same code; one run is a sample, not a verdict.
- golden/ saved: spec.md (proposal Desired outcome..Open questions), planted.diff (git diff 195d75c HEAD, 406 lines), rubric.md.
- Working tree of slugkit-golden unchanged by review (clean, HEAD 2b2c0e6).
- SIDE EFFECT: golden reviewer wrote a probe script to scratchpad/probe.mjs (outside the repo AND outside pilot/). "Read-only" was honored for the repo but the reviewer still creates scratch files; review.md says "Review never edits anything" without saying where probes may go. Left in place (outside my write scope).

## review.md friction
- Output contradiction: "Read-only apart from review-findings.md" + "write findings to review-findings.md" vs the pilot's read-only instruction (and the claude adapter reviewer with no edit tools). Both reviewers handled it cleanly by deferring the write to the caller; review.md should say who writes it.
- Precondition "tasks.md shows ... implementer's gate output. If not, stop" -- both reviewers hit it (Gate output empty) and both chose to proceed and run the gates themselves. The rule is either too strict or not enforced; implement.md apparently didn't make the paste mandatory enough (implementer skipped it).
- Inputs: "the diff" + base commit had to be supplied by me; review.md never says how to find <base> (merge-base with which branch?). Worked only because I gave 195d75c.
- Throwaway-index instruction: irrelevant here (nothing uncommitted), and the sample command `GIT_INDEX_FILE=<tmp copy> git add -N .` is fiddly/Windows-unfriendly; neither reviewer needed it. Also the change folder being untracked (earlier steps) is precisely the case it's for.
- Security-pass trigger: both reviewers judged "no external surface" -> no second pass. Trigger list is clear for this; it didn't cover "public API break", which is what the real blocking finding was (that's constitution 2, found anyway).
- Budget: "runs once" + "after two request-changes rounds refuse a third" is clear; counting rounds relies on review-findings.md headers, whose format is unspecified (I used "## Round 1").
- Severity labels unspecified: reviewer 1 used Blocking/minor, reviewer 2 High/Medium/Low. Rubric scoring ("medium or higher") needs a fixed scale in review.md.
- "Label introduced vs already present" worked well in both.
