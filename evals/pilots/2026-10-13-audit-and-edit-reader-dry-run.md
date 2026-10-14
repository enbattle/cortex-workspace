# Dry run: `audit` and the retro edit reader, 2026-10-13

The 3.5.0 spec's "Tests and evals" asks that `audit` and the reader run as
written on the golden fixture's repository, and that the reader return
something a user can act on, before release.

- **Repository:** `slugkit` from `evals/golden/review-maxlength/fixture.bundle`
  (refreshed at fdbd84f), `main`, in scratch clones outside cortex.
- **Setup:** cortex at fdbd84f. Each read a fresh `general-purpose`
  subagent in Claude Code (Opus 5.5), given exactly the instruction its
  step states and the file list the session made in step 1. Read-only;
  every clone was left as found.
- **Not exercised:** the Claude Code skill and agents (the instructions
  were given directly, as in any tool), and steps 4-5 (no user to decide).

## Runs

| Run | What it read | Planted | Found |
| --- | --- | --- | --- |
| a1 | `audit` step 2 on `cortex/AGENTS.md`, `cortex/knowledge/*`, the constitution's Project section, `cortex/deferred-practices.md` | `cortex/AGENTS.md` says tests live in `tests/` and run with `npm test` (they're in `test/`, run by `node --test`) | yes, rated high: a test written under `tests/` runs but sits outside `TEST_GLOBS`, so the lock never protects it |
| a2 | `audit` step 3 on a log seeded with 12 rows (no audit log) | three friction kinds recurring every four rows, a retro edit that never held, a "first time" claim made three times | yes, all: four groups, costliest first, the failed retro edit named, the false "first time" named |
| r1 | `retro` step 5 on a proposed `implement.md` edit and its evidence | "add a test in a new file" (contradicts step 2, permissions, the lock), "Budget: 5 attempts ... on the third failure" (contradicts itself), evidence citing files the branch doesn't have | yes, all three, with four dry-run changes where the text gave no clear answer; recommended dropping both edits |

## What the reads found that wasn't planted

- **a1**, real drift in the fixture's own docs (written for 2.2.0 and never
  audited): constitution P3 and the conventions say arguments are
  validated, but `slugify(null)` returns `"null"`; three disagreeing
  statements of the dependency rule; a glossary definition that's wrong
  for upper-case input; a router line listing fewer gates than `gates.sh`
  runs; facts copied between the router, the architecture overview and
  `cortex/config`, with the copies that drifted nominated for deletion.
- **a2**, a gap in 3.4.0 itself: the fixture's `LINT_CMD` is
  `node --check src/slugify.js`, which never reads a test file, so
  `test-first`'s lint-before-lock step (P2 (a)) checks nothing there. Any
  project whose lint command doesn't cover its tests has the same gap.
  Raised to the maintainer.

## Verdict

Both commands ran as written, and every planted problem was found and
explained in terms a user can act on. The friction read and the edit reader
each recommended a deletion over new text, as their instructions ask.
