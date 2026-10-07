# Plan: quality standards for the code itself (2.3.0)

Status: **approved by the maintainer, 2026-10-07**, with both open questions
answered (at the end). A point-in-time record: the completeness audit maps
every item below to evidence.

## Context

The maintainer's bar for code written under cortex: **readable and clear**
(simple logic, clear names, small functions, comments that say why),
**maintainable and modular** (single responsibility, independent pieces),
**performant and efficient**, **robust and reliable** (errors handled,
secure, strictly tested), and **compliant and consistent** (industry style
guides, uniform with the codebase). Checking 2.2.0 against that bar:

| Quality | Covered by | Gap |
| --- | --- | --- |
| Readable and clear | Design and simplicity (call site, glossary names, comments say why); a complexity limit in lint | E4 forbids building more than the criteria need; nothing asks for the simplest construction of what they do need |
| Maintainable and modular | One reason to change, dependency direction, E4 | None |
| Performant and efficient | "Huge input" as an edge case | No check for wasted work or leaked resources |
| Robust and reliable | E3, S1-S5 and the security pass, the Tests bar, the test lock | None |
| Compliant and consistent | "Follows the conventions in `AGENTS.md`"; lint suggestions | Nothing on following the codebase's existing patterns, or on never copying a bad one; no formatter or style guide suggested |

**And one structural gap:** `test-first` writes to the checklist's Tests
section and `spec-clarify` designs to its Design and simplicity section, but
`implement`, the role that writes the code, is never pointed at the quality
bar. It meets it only when review rejects its work, which spends a review
round.

**And a measurement gap:** the golden task's one plant is a correctness bug,
found by checking behavior against the criteria. No golden run exercises the
Design or Performance items, so nothing shows whether review enforces them.
The control also has no single right answer (`results/2026-10-06.md`:
reviewers rated the same real `map(slugify)` break anywhere from not raised
to High).

## Principles that bound this plan

- **Mechanisms, not labels.** "The simplest construction", not "KISS"; the
  SOLID decision of 2026-10-06 stands (T5).
- **The harness stays stack-neutral.** Style guides and formatters are the
  project's choice, made at install and enforced by `LINT_CMD` (R1, R7, R8).
- **Consistency by default; departures are decisions.** An implementer that
  judges on its own whether an existing pattern is "best" is the actor who
  would rationalize (R14), and each change would bring its own idea of best.
  So nearby patterns are followed, with a hard floor that is never copied
  (the constitution, security rules, lint gates), and choosing a better
  pattern is a design decision the user approves and the conventions record.
- **Performance is a check against waste, not a license to optimize.**
  Optimization nobody asked for is E4's speculative work; the golden task's
  own plant is such an "optimization", and it broke correctness.
- **Context is paid on every run (R13).** About eight checklist lines and a
  few command lines in total; nothing else is added.

## Items

### Quality standards (template)

Mechanism, shared: each item names a failure that agent-written code shows
(dense code that meets the criteria, per-change pattern drift, a copied
defect, waste on growing input) and makes it something the author writes to
and the reviewer checks. Fit: every code change. Cost: the lines above.
Reversible: text edits.

- [x] 1. `implement.md`: Preconditions load the checklist's "Design and
  simplicity" and "Performance and resources" sections; step 3 writes each
  task's code to them and to the repository's conventions. This is the
  routing `test-first` already uses for the Tests section.
- [x] 2. Checklist, Design and simplicity, a new item: *the simplest
  construction that meets the criteria, so a reader new to the code follows
  it without the conversation that produced it.* Low unless a finding names
  a concrete cost (the section's existing rule).
- [x] 3. Checklist, Design and simplicity, a new item: *new code follows the
  patterns the repository's conventions name, or failing that, the ones
  nearby code uses for the same problem (errors, logging, data access,
  validation). A pattern that breaks the constitution, a security rule or a
  lint gate is never copied. Choosing a better pattern over the nearby one
  is a design decision: `design.md` names both and why, the user approves
  it with the spec, and the conventions record it so later changes follow
  it.*
- [x] 4. `spec-clarify.md` step 5: when the nearby pattern for the change's
  problem is dated or weaker, raise it with the user, who chooses: follow it
  (recorded as known debt in `design.md`), adopt the better one for this
  change (recorded in the conventions), or migrate the old uses as a change
  of its own. `implement` step 4 (stop on divergence) already covers finding
  it late.
- [x] 5. `review.md` step 8: a new instance of a defect that exists
  elsewhere in the code is introduced by this diff, not already present.
  Without this sentence a copied bad pattern can be filed as pre-existing
  and never block.
- [x] 6. Checklist, a new section, **Performance and resources**:
  - *No waste that grows with input: no work quadratic in input that can
    grow, no I/O or query inside a loop where one call serves, and no
    unbounded memory growth. Every resource (file, connection, lock,
    timer) is released on every path, including error paths.*
  - *Performance work beyond that only where a criterion asks for it, and
    measured. An unrequested optimization is E4's speculative work.*

  Severity: under `review.md`'s existing scale, waste with a realistic
  trigger is a Medium (a real defect outside the criteria); a leaked
  resource on an error path likewise.
- [x] 7. `INSTALL.md` step 3, question 2: besides type checking, a
  complexity limit, duplicate detection and dependency-boundary rules,
  suggest a formatter and the stack's standard style guide, and name the
  style guide in `AGENTS.md`'s conventions. This makes "consistent" a gate.
- [x] 8. `INSTALL.md` step 3, a new question for an existing codebase:
  *which patterns here shouldn't be copied, and what replaces each?*
  Answers go into `AGENTS.md`'s conventions while they fit its 60 lines
  (the template has 39), or into a knowledge file it routes to, under the
  existing rule for content longer than a routing line.
- [x] 9. `permissions.md`: `implement` reads the checklist (already listed);
  no change unless items 1-8 change a row. Checked, not assumed.

### Golden fixture rebuild (evals)

Mechanism: a golden task measures only what its plants exercise, and its
control is only as good as its single right answer. Fit: every edit to the
review text runs it (root `AGENTS.md`). Cost: one rebuild, two more runs per
cycle (five instead of three). Reversible: the old bundle is in history.

- [x] 10. **Tests first.** `refresh.sh` and `tests/golden-fixture.test.sh`
  know two tags. A spec section here states the new behavior: both treat
  `golden-quality` like `golden-planted` (the test fails, naming the file,
  when that tag changes a harness file; the refresh rewrites and checks all
  three tags). A separate agent that hasn't seen the change writes the
  test cases from that section, committed before `refresh.sh` changes
  (root `AGENTS.md`). The suite's existing assertion counts stay unchanged.
  The section is "Fixture tags" below.
- [x] 11. Rebuild the fixture from the current template, following the
  golden README's build steps, with these differences in the change folder:
  - **The control gets one right answer:** the proposal names the
    `map(slugify)` case under compatibility; `design.md` gives the
    migration (`arr.map(s => slugify(s))`); the implementation adds it
    where consumers read it (the JSDoc and a `CHANGELOG.md` entry in the
    fixture, with a minor version bump).
  - **The 2.2.0 paths are exercised:** `docs/knowledge/verification.md`
    holds an entry for `slugify`, `tasks.md` names it and records a blast
    radius (the search and its result), and `design.md` names the knowledge
    files it relies on.
  - Source, tests and both existing plants keep their behavior, so the
    rubric's reproductions stay valid.
- [x] 12. A third tag, **`golden-quality`**: `golden-clean` plus one commit
  that rewrites truncation so it builds the result word by word and
  re-scans what it has built on each step. Before it is accepted:
  - gates and all tests pass at the tag;
  - its output equals `golden-clean`'s on a sweep of inputs (the plant is
    purely a quality defect);
  - the slowdown is large and repeatable at a stated input size (seconds
    against milliseconds), not timing noise;
  - `golden-clean` has none of it, and the plant adds no second defect.
- [x] 13. `rubric.md` and the golden README: the control's expected verdict
  is approve, and blocking on `map(slugify)` is now a false positive (FAIL);
  `golden-quality` passes only with request changes naming the repeated
  re-scan at Medium or higher; the procedure runs `golden-planted` twice,
  `golden-quality` twice and `golden-clean` once.
- [x] 14. Run the golden cycle once, after items 1-13 (all review-text
  edits land first, so the runs happen once), and record it in
  `results/<date>.md`.

### Catalog and release

- [x] 15. `docs/02-extensions.md`, "Golden-task evals" tier 2: record the
  quality plant, and as a catalog note (not built) a second quality plant,
  a duplicated rule for E4, with its trigger: a review finding that E4
  duplication escaped, or the quality tag passing everywhere for a cycle of
  edits.
- [x] 16. `CHANGELOG.md` entry (2.3.0: additive, no command contract or
  required file changes); the full suites and CI pass on the pull request (PR #23, CI run 37575448956 at `5e7b269`).
- [x] 17. A completeness audit before release (root `AGENTS.md`),
  including its nomination of something to delete or merge. This plan's
  nomination: none in the template (each addition is a line or two and
  replaces nothing); in the evals, the rebuild retires the README's notes
  on what the fixture predates.

## Fixture tags (spec for item 10)

The check is `fixture_drift` in `tests/golden-fixture.test.sh`; it is test
code, so the separate agent writes the check and its planted cases together
from this section. The fixture rebuild (items 11-12) is what makes the
committed bundle pass again: between the tests commit and the rebuilt
bundle, the committed-bundle case fails, as tests written first do.

1. The fixture has three tags: `golden-clean`, `golden-planted` and
   `golden-quality`. The harness files compared (the existing
   `expected_pairs`) must be identical at all three.
2. `fixture_drift` reports, one line each, as today:
   `stale <path> (differs from <source>)`, `missing <path> (<source>
   exists)`, `planted-changes <path>` (golden-planted differs from
   golden-clean on a compared file); and, new:
   - `quality-changes <path>`: golden-quality differs from golden-clean on
     a compared file;
   - `missing-tag <tag>`: one of the three tags doesn't exist in the
     bundle. Then the comparisons that need that tag are skipped, not
     crashed.
3. New planted cases, each built from a copy of the committed bundle:
   - golden-quality moved to a commit that changes
     `harness/commands/review.md`: exit 1, and the line
     `quality-changes harness/commands/review.md`;
   - golden-quality deleted: exit 1, and the line
     `missing-tag golden-quality`.
4. The existing cases keep their assertions, and the existing planted
   cases still name exactly what they name today (the seven-line count in
   the source-drift case holds once the bundle has all three tags).
5. `refresh.sh` (not a suite; changed after the tests, which check the
   bundle it produces, not the script):
   rewrites all three tags; refuses the new bundle unless, at each tag,
   `src/`, `test/` and `package.json` are unchanged and `gates.sh` prints
   `gates: ok`.

## As built

- **Item 3:** the pattern item replaces the checklist's "follows the
  conventions in `AGENTS.md`" item (now merged, one source), and the
  "Conventions and docs" section is now "Docs". The template router gains a
  `## Conventions` section (no `TODO`, so C12 holds), because the checklist
  and `INSTALL.md` point at "`AGENTS.md`'s conventions" and the router had
  no place for them.
- **Item 11, the version (maintainer's decision, 2026-10-07):** the fixture
  locks `package.json` during a change (it holds the test command), so the
  change can't bump `slugkit` to 0.2.0; `implement` couldn't edit it, and
  `spec-clarify` would flag it. The change adds a `CHANGELOG.md` entry
  headed `0.2.0 (unreleased)` with the migration, and the proposal says the
  bump happens at the library's release.
- **Item 11, criteria:** the migration note is a new criterion, AC8
  (manual-verify), done by a new task, T4; Open questions gains answer 6
  (the callback break accepted, over ignoring a number, which P3 forbids).
- **Item 12:** the plant drops words from the end until the rest fits,
  rebuilding the remaining string each step. Checked at build time: 0
  differences from `golden-clean` over 1,786,429 inputs and limits; gates
  and all 26 tests pass at each tag; at 100,000 characters, about 1 ms
  against about 8 s, and at 10,000, 0.1 ms against 65 ms: ten times the
  input costs about a hundred times the time.

From the completeness audit (`evals/audits/2026-10-07.md`):

- **Item 9:** checked: `permissions.md` already gives `implement` "the
  review checklist", so no row changed for items 1-8. The review row
  gained `AGENTS.md` (next bullet).
- **R4 (maintainer's decision, 2026-10-07), against "Not changed" below:**
  review's inputs now include the repository's `AGENTS.md` files, in R4,
  `review.md` and `permissions.md`. The checklist checks code against
  their conventions, and R4 didn't list them; the gap predates this plan,
  and item 3 made it load-bearing. Isolation isn't weakened: R4 keeps the
  reviewer from the implementation conversation, and the router is
  project instructions every agent reads first.
- **Item 11, the constitution:** the first golden cycle found the
  fixture's constitution predated E4 (and W1's current wording) while the
  checklist cites E4. The rebuild gives the fixture the template's E, S
  and W rules, keeping its own P1-P3 (`15fd3ec`).
- **Item 10, `refresh.sh` with three tags:** run three times during the
  rebuild, each printing `gates: ok` for `golden-clean`,
  `golden-planted` and `golden-quality`; the last run (bundle in
  `15fd3ec`, refreshed again after the audit's checklist edits) is the
  committed one.
- **Checklist, from the audit:** the Performance section's intro sentence
  merged into its third item (the audit's nomination: the rule was stated
  twice); the pattern item's last sentence points at `spec-clarify` step 5
  instead of restating it; the preamble says nearby code is the pattern
  item's reference, not its subject.
- **Cost (R13), measured by the audit:** the checklist grew from 76 to 86
  lines; the commands by about 100 words; `implement` now also loads two
  checklist sections (about 400 words) on every run.

## Not changed

- The constitution. `docs/01-design-rules.md` changed only in R4, on the
  maintainer's decision after the audit (As built).
- The template's scripts (`scripts/cortex/`). Item 10 changes only the
  evals' `refresh.sh` and its test suite, tests first.
- The catalog's "Performance and observability budgets" entry stays
  deferred: item 6 checks for waste, while budgets (numeric targets
  enforced in CI) still wait for their trigger.

## Questions, answered by the maintainer on 2026-10-07

Q1: 2.3.0. Q2: yes, `slugkit` 0.2.0, then (once the lock conflict surfaced)
a changelog entry now and the bump at the library's release (As built).

- **Q1.** Version: 2.3.0 (additive). Agreed?
- **Q2.** The fixture's own version bump for the AC7 migration (item 11):
  `slugkit` 0.1.0 to 0.2.0, the usual minor bump for a breaking change
  before 1.0. Agreed?
