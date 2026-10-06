# Plan: quality parity with pstack, the cortex way

Status: **approved by the maintainer, 2026-10-06**, with both open questions
answered (at the end). A point-in-time record: the completeness audit maps
every item below to evidence.

## Context

A comparison with pstack (Lauren Tan's Cursor plugin; the horizon scan in
`docs/02-extensions.md` recorded it on 2026-10-01) rated cortex behind on
three quality layers and even on one:

| Layer | Before | Target | Items |
| --- | --- | --- | --- |
| Works for real (verification on the real artifact) | pstack ahead | above | 1-6 |
| Design quality | pstack ahead | even | 7-12 |
| Compatibility (blast radius) | even | above | 13-15 |
| Review breadth (model diversity) | pstack ahead | measured, not adopted | 16-17 |

pstack's edge in each comes from a mechanism, not a feature list: a
maintained per-project verification recipe; explicit design principles
applied from the caller's side; proof that callers outside the diff still
work; and reviewers on different models. This plan takes the mechanisms and
fits them into cortex's existing files and routing. It adds no command, no
script change and no new required file. "Target" is a hypothesis: the golden
task (item 16) and a first real project are what would show it.

**What stays rejected**, as the 2026-10-01 horizon scan decided: autonomous
and autopilot playbooks (they conflict with the human gates, R14), parallel
workers (deferred until latency is the complaint), competing prototypes on
every change (cost), prose-polishing skills (the "content quality" catalog
entry covers them), personal transcript tools, and per-role model routing.

**Constraints from the maintainer:** cortex focuses on Claude Code for now,
so a reviewer on another model family is deferred (it needs a second
provider). DRY and YAGNI stay as constitution E4 states them: E4 already
scopes DRY to copies that must change together and YAGNI to the acceptance
criteria, so neither is reworded; the new design items are written under it.

## Items

Each item with R14's four checks (mechanism, fit, cost here, reversibility),
answered once per group where they are shared.

### Works for real

Mechanism: today each `implement` run improvises how to run the changed
thing, so verification is inconsistent and drifts toward "the tests pass";
a recipe kept in the repository makes it repeatable, and the reviewer
reproduces the same steps independently, which pstack's single-agent
verification doesn't. Fit: any repository with something to run (for a
library, the caller's position). Cost: one knowledge file, read only by
`implement` and `review` and only when the change folder names it (R4, R5);
it stays true because a reviewer who can't follow it reports that (an
observable failure, T13). Reversible: delete the file and three lines.

- [x] 1. New `template/docs/knowledge/verification.md`, a stub with TODOs:
  how to start the thing and check it's healthy, how to stop and clean up,
  and a feature map (feature; how a user reaches it; how an agent drives
  it; what observable state proves it worked). It is filled in per feature
  as changes touch it, not all at install.
- [x] 2. A row for it in `template/docs/knowledge/index.md`.
- [x] 3. `implement.md`: step 6 follows the recipe for the features the
  change touches; step 5 (stale docs) adds or updates the recipe's entry
  for a feature the change adds or alters, and fixes a recipe step that no
  longer works.
- [x] 4. `tasks.md` template, `## Verification`: name the recipe entries
  used, so the change folder names `docs/knowledge/verification.md` and the
  reviewer may read it within R4's inputs (no design-rule change).
- [x] 5. `review.md` step 3 repeats the recorded verification by the recipe;
  a recipe that can't be followed is a Low finding, a step that fails is a
  finding at the severity of what fails (as today).
- [x] 6. `INSTALL.md` step 3: fill in the recipe's start, health and stop
  sections during the interview when known; otherwise leave the TODOs.

### Design quality

Mechanism: agents default to the first workable shape and to the patterns
nearest in context; naming a few design properties, judged from the call
site, gives `spec-clarify` something to design to and `review` something to
check. Fit: every code change. Cost: about eight checklist lines (offset by
merging the Simplicity section, so the checklist gets one section, not two)
and a few lines in two commands; the checklist is already loaded by both
roles that use it. Reversible: text edits.

The three rules that keep these items subordinate to E4 (the conflict raised
in discussion: single responsibility and "make invalid states
unrepresentable" both pull toward more units, types and layers):

1. **E4 wins any tie.** No design item justifies a layer, type or
   abstraction the acceptance criteria don't need. (The constitution
   already outranks a policy; this states it where the reader is.)
2. **Scope:** the items apply to code the change touches, never to
   refactoring nearby code "while here".
3. **Severity:** a design finding is Low unless it names a concrete cost (a
   caller that breaks, a defect the shape invites). Duplication of a rule
   whose copies must change together stays what it is today: an E4 breach,
   so High. This keeps style preferences from spending the two review
   rounds (R13).

- [x] 7. `review-checklist.md`: replace `## Simplicity (constitution E4)`
  with `## Design and simplicity (constitution E4)`: the three rules above
  as its preamble, the two existing simplicity items, and:
  - interfaces are shaped from the call site (how a caller uses it reads
    plainly);
  - invalid states are hard to represent, where the language's types
    express it cheaply, rather than guarded by scattered conditionals;
  - each new unit has one reason to change;
  - dependencies point the way `docs/knowledge/architecture.md` says, and
    no new cycle appears;
  - a constraint is encoded as a type, a test or a lint rule where it can
    be, not only as a comment; comments say why, not what;
  - names match `docs/knowledge/glossary.md`.

  SOLID is not named: the two parts that hold in any language (one reason
  to change, dependency direction) are in the list by their mechanism, and
  the object-oriented rest would invite the speculative abstraction E4
  forbids (T5). Boundary validation is not repeated: it is S2 and the
  Security section.
- [x] 8. `spec-clarify.md` step 5: `design.md`'s approach is written to the
  checklist's Design and simplicity section (the routing pattern the Tests
  section already uses), and each alternative shows its call site: a few
  lines of the caller's code.
- [x] 9. `design.md` template: the Alternatives comment asks for each
  alternative's call site.
- [x] 10. `spec-new.md` step 2: before changing or removing behavior, check
  why it exists (the history of those lines, and the change folder or pull
  request that added them); note anything that bears on the change in the
  proposal. This is pstack's `/why` as one sentence; a deliberate behavior
  removed by accident is a regression no test written for the new criteria
  catches.
- [x] 11. `spec-new.md` step 3 and the `proposal.md` template's Problem
  comment: for a bug fix, record how to reproduce it and the root cause, or
  say the cause is not yet known so `spec-clarify` asks. A fix aimed at a
  symptom passes a test written for the symptom.
- [x] 12. `INSTALL.md` step 3, question 2: recommend that `LINT_CMD` include
  what the stack offers for type checking, a complexity limit, duplicate
  detection and dependency-boundary rules. These are the project's tools
  (R7), and they turn design items from instructions into gates, which is
  where cortex can go past pstack's instruction-only principles.

### Compatibility

Mechanism: a change can break a caller outside its diff; the spec asks about
callers and review rates a broken caller High, but nobody records evidence
of which callers exist and that one still works. Fit: any interface-
affecting change. Cost: a short list in `tasks.md`, only for those changes.
Reversible: text edits.

- [x] 13. `implement.md` step 6: for an interface-affecting change, record a
  blast radius under `## Verification`: the callers found, with the search
  that found them, and at least one existing caller run against the change.
- [x] 14. `review-checklist.md`, Interfaces: every consumer is accounted for
  by the recorded search, and the reviewer runs its own search rather than
  trusting the list.
- [x] 15. `tasks.md` template: the `## Verification` comment mentions the
  blast radius.

### Review breadth: measure, don't adopt

A second reviewer on a different model family needs a second provider and is
deferred (the maintainer's Claude Code focus). A different Claude model works
inside one subscription but shares training lineage, so its blind spots may
largely overlap the default reviewer's; and a smaller model must never
replace the default one. So this plan measures before deciding.

- [x] 16. The golden task, after items 1-15 (required anyway: `review.md`
  and the checklist change): `golden-planted` twice and `golden-clean` once
  with the default reviewer, per its README; then the same three runs with
  a reviewer on a smaller Claude model (in Claude Code, a fresh
  `general-purpose` subagent with a model override). Record both in
  `results/<date>.md`. Limit, stated in the results: one task with one
  planted defect shows whether the smaller model finds the plant and how
  noisy it is, not whether it adds different findings; that needs more
  golden tasks.
- [x] 17. `docs/02-extensions.md`, "A second reviewer on a different
  model": note that a different family needs a second provider; that a
  different Claude model is the step available in one subscription, adopted
  only as an addition (it can add findings, never approve alone or outvote)
  and only when a golden task shows it finds something the default reviewer
  misses; and record item 16's result.

### Catalog and release

- [x] 18. `docs/02-extensions.md`: a new entry, **a smoke-test gate**
  (`VERIFY_CMD`, an optional command `gates.sh` runs that starts the real
  thing and exercises it). *Trigger:* a change passes every gate and review
  and then doesn't work when run. Why deferred: it changes a script's
  contract (spec and separate-agent tests first), CI must be able to start
  the application, and where end-to-end tests exist it duplicates
  `TEST_CMD` (E4). Item 1's recipe covers most of its value without a gate.
- [x] 19. The horizon scan's pstack line: add what this plan adopts
  (verification recipe, design section, why-before-change, root cause,
  blast radius) and what was measured instead of adopted.
- [x] 20. Refresh the golden fixture (`refresh.sh`; the template changed),
  before item 16.
- [x] 21. `CHANGELOG.md` entry; the full `bash tests/run.sh` and CI pass;
  `VERSION` 2.2.0 at release (additive: no command contract, required file
  or template field is removed or renamed; the new knowledge file is a
  stub).
- [ ] 22. A completeness audit before release (root `AGENTS.md`),
  including its nomination of something to delete or merge. This plan's own
  nomination: the Simplicity section, merged into item 7.

## Not changed

- Constitution E1-E4, S1-S5, W1-W5: no wording change (see Constraints).
- `docs/01-design-rules.md`: no change; item 4 keeps verification inside
  R4's inputs, and R14's four checks are recorded above.
- Scripts and their suites: no change. `tests/check.test.sh` must still pass
  against the template (no tool name in the new knowledge file, C2).

## Questions, answered by the maintainer on 2026-10-06

Q1: this lands first, as 2.2.0. Q2: Sonnet.

- **Q1. Order against the 3.0.0 spec** (`docs/specs/2026-10-05-v3-removable-layout.md`,
  draft, untracked on `spec/v3-removable-layout`). Proposed: this lands
  first as 2.2.0. It is small, markdown-only and independent; 3.0.0 then
  moves these files with the rest (its layout list gains
  `knowledge/verification.md`), and its migration covers any 2.x. The
  alternative is to fold these items into 3.0.0, which delays them behind a
  multi-PR effort with open questions.
- **Q2. Which smaller model for item 16:** Sonnet (the closest to Opus in
  capability) unless the maintainer prefers another.
