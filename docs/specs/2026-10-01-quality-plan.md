# Plan: DRY/YAGNI cleanup, judgment over proxies, and quality standards

Status: agreed in discussion with the maintainer, 2026-09-30 to 2026-10-01.
The philosophy edits in PR 2 (marked **diff first**) are drafted as diffs
for the maintainer's approval before they are applied. A point-in-time
record: the completeness audit after PR 2 maps every item below to evidence.

**The line this plan draws.** A rule stays rigid where it constrains the
actor who would rationalize an exception (human approval, the test lock,
reviewer isolation, untrusted content, never pushing). Everywhere else,
rules ask for judgment: understand a practice's mechanism, check that its
failure can happen here, weigh its cost here (including context cost in
every installed repository) and its reversibility, then decide, and record
the reasoning.

Sources, in brackets: **[audit]** the first DRY/YAGNI review;
**[tests/evals]** the follow-up review of tests and evals; **[standards]**
the codification and testing discussion; **[rigidity]** the review of
over-rigid rules; **[seams]** the plan's own cohesion review; **[pstack]**
the comparison with pstack; **[routing]** the final check that each standard reaches the agent that needs it.

## PR 1: DRY/YAGNI cleanup (branch `refactor/dry-yagni`)

- [x] 1. Drop shipped CI checks from `template/docs/deferred-practices.md`
  and `docs/02-extensions.md` §3. [audit] `444b557`
- [x] 2. Remove `docs/00-highlights.md`, its sync rule and its links.
  [audit] `09fb2fc`
- [x] 3. Spec Amendment 6, one config parser. [audit] `7050e67`
- [x] 4. Amendment 6 tests, by a separate agent, before the change. `6df5d05`
- [x] 5. `template/scripts/cortex/_config.sh`; `check.sh`, `gates.sh`,
  `tests-locked.sh` and `adapt.sh` source it. [audit]
- [x] 6. `tests/lib.sh` gains the helpers copied across suites, with
  assertion counts unchanged: `commit_all` (3 copies) [audit];
  `config_lines`, `config_variant`, `write_stub_parser` (4 copies each); one
  lock-fixture helper for `gated_repo`, `variant_gated_repo` and
  `lock_folder` (`write_lock` stays: it builds malformed locks); and
  `set_config` reuses `append`. [tests/evals]
- [x] 7. Constitution E4, judged by whether copies must change together
  (the third copy is when to look, not a mandate) [seams], and including:
  migrate internal callers and delete the old path in the same change,
  while public interfaces follow E2. [standards] [pstack]
- [x] 8. Maintainer rule in root `AGENTS.md`: logic used by two or more
  scripts lives in a sibling file; helpers used by two or more suites live
  in `tests/lib.sh`; a doc that summarizes another links to it; DRY applies
  to maintained files, not dated records (pilots, results, audits).
  [standards] [tests/evals]
- [x] 9. `evals/golden/review-maxlength/refresh.sh` replaces the hand-written
  history-rewrite filter; the README's "Which template this fixture
  matches" keeps the current state and the check, not each refresh's
  hashes; its "Log" step records results and deviations only, not the
  procedure. Past results files stay as written. [tests/evals]
- [x] 10. Refresh the golden fixture (scripts and `_config.sh` changed).
- [x] 11. `CHANGELOG.md` entry; the full `bash tests/run.sh` passes (all 7 suites at `12d5349`; shellcheck runs in CI);
  shellcheck passes in CI.

No golden review runs in PR 1: every review-text edit moved to PR 2 so the
golden runs happen once. [seams]

## PR 2: judgment over proxies, and quality standards

Judgment over proxies [rigidity]:

- [x] 12. **diff first** A design rule, R14, in `docs/01-design-rules.md`:
  the rigidity line above, and what counts as evidence for adopting a
  practice (an observed incident, or a well-understood failure that can
  occur here, passed through the four checks: mechanism, fit, cost here,
  reversibility), with the answers recorded. It is a design rule, not only
  a traps-document principle, because `install.sh` copies the design rules
  into every installed repository as `.cortex/design-rules.md`; the traps
  document is never installed, so a retro there could not read it.
  `docs/03-mental-traps.md` explains the reasoning beside P5 and points to
  R14. [routing]
- [x] 13. **diff first** Every restatement points to R14 instead of
  defining evidence itself: P2, T1's antidote and pre-addition question 1, T5,
  the traps document's own entry rule, `docs/02-extensions.md`'s operating
  rule, `docs/04-operator-feedback-loop.md`'s judgment rules ("act on
  second" becomes cost-dependent: a cheap, reversible fix may act on the
  first occurrence), and `template/docs/deferred-practices.md`.
- [x] 14. An adoption made on the four checks records its answers (in the
  retro's pipeline-log row or the change folder), as a waiver is recorded:
  `retro.md` step 4 and the extensions operating rule. [seams]
- [x] 15. **diff first** Deletion quotas become "nominate one, or say why
  nothing qualifies": T14's antidote and the extensions' "Deletion pass".
- [x] 16. Removing a checklist item weighs the severity of what it catches,
  not only how often it fires: `review-checklist.md`'s preamble and T14.
- [x] 17. R13: a theoretical finding becomes a known limitation by default;
  a cheap test is allowed when the class is severe (matching `review.md`).
- [x] 18. **diff first** Drop "not through another completeness audit" from
  `docs/04-operator-feedback-loop.md` (it contradicts the root `AGENTS.md`).
- [x] 19. R7 says it limits the harness's own requirements, not the
  project's development tools.
- [x] 19a. Drop the hard-coded rule range "R1–R13" (in `template/AGENTS.md`,
  `README.md`, `docs/02-extensions.md`, and a comment in
  `scripts/install.sh`), so adding R14 doesn't mean editing four places:
  say "the design rules" or "rule IDs (R1, R2, ...)". [routing]

Review text, all in this PR so golden runs happen once [seams]:

- [x] 20. `review-checklist.md`: drop the `check.sh` item (`gates.sh` runs
  it) [audit]; add a simplicity item (no duplicated logic that must change
  together, nothing beyond the criteria) [standards].
- [x] 21. `security-review.md` points to `review.md` step 7 for what counts
  as an external surface, instead of repeating the list. [audit]
- [x] 22. The review verdict lists every procedure step and checklist item
  as done or `skip: <reason>`, so an empty approval is mechanical to spot.
  [pstack]

Test and verification quality:

- [x] 23. A test-quality bar: deterministic and isolated; boundary and
  error cases; never mock the unit under test; assert against literal
  expected values [pstack]; property-based tests where the input space is
  large. [standards] It lives once, in the Tests section of
  `review-checklist.md`, which the reviewer already loads (R4); `test-first.md`
  tells the test writer to meet that section, instead of a copy the
  reviewer can't see. [routing]
- [x] 24. Verification on the real artifact, matched to what changed:
  `implement` runs the changed thing the way a user would (the command, the
  endpoint, the flow) and pastes the evidence into `tasks.md`; `review`
  repeats it. [pstack] What counts as evidence for each kind of change is
  defined once, in `review-checklist.md`; both commands point to it.
  [routing]
- [x] 25. A mutation audit of the five gate scripts (break one condition at
  a time; record what no test catches) in `evals/audits/`; automate only if
  it finds survivors. [standards]
- [x] 26. Measure the suites' time and memory before changing them (a run
  was killed for memory on 2026-09-30). [standards]

Catalog (`docs/02-extensions.md`), each with a trigger:

- [x] 27. Mutation-testing tools for installed repositories (stack-specific,
  so not shipped); flaky-test quarantine (a scale problem); coverage
  reported, never gated (a gate gets gamed). [standards] These three are
  practices for the project, so each is also seeded as a short entry in
  `template/docs/deferred-practices.md`, which installed repositories read
  at every retro; items 28 and 29 change the harness, so they stay in the
  cortex catalog only. [routing]
- [x] 28. Process weight scaled to stakes: a middle tier between trivial
  and the full pipeline, chosen by the human or a fixed rule, never the
  agent; designed from the first real project's data. [pstack]
- [x] 29. A second reviewer on a different model for high-risk changes,
  next to model-tier routing. [pstack]
- [x] 30. The horizon scan records pstack, with what was adopted (items 7,
  22, 23, 24, 28, 29) and what was rejected and why: its size, the
  maintained feature map (a curated summary drifts, R13), "never block on
  the human" (conflicts with the human gates), competing prototypes by
  default (cost), and Cursor-specific model routing. [pstack]

Then:

- [x] 31. Refresh the fixture; run the golden task twice with fresh
  reviewers and record it; `CHANGELOG.md` entry; the full suites pass (CI
  run 37072785977 at `5b107a4`).

Rejected after discussion: lint hooks in the Claude Code adapter (`gates.sh`
and review already run lint; a hook would be a third copy). [standards]

## PR 3: test gaps and a faster check.sh

Agreed 2026-10-02, from the test-suite audit (`evals/audits/2026-10-02-test-suites.md`).

- [x] 33. Spec Amendment 7: `check.sh` starts a bounded number of processes
  (behavior unchanged), and acceptance criteria for the tests the mutation
  audit asked for.
- [x] 34. Tests by a separate agent, before the change: planted violations
  for the survivors c7 and t6 (rigid rules) and c2, c6, c9, c10, c12
  (low severity; one line each), and the process-count criterion.
- [x] 35. `check.sh` with a bounded number of processes; refresh the golden
  fixture; re-time a suite against the audit's numbers.
- [x] 36. `CHANGELOG.md` entry; CI passes.

## After PR 3

- [ ] 32. A completeness audit (root `AGENTS.md`): a fresh agent maps every
  item in this plan to evidence, checks the docs against the code, and
  nominates a removal or says why nothing qualifies.

## Out of scope, still open

The release blockers in `CHANGELOG.md` (pilot 2's F1, F4, F5) and a first
real project, which is what would show the harness holds up in practice.
Nothing is pushed, merged or tagged without the maintainer's go-ahead.
