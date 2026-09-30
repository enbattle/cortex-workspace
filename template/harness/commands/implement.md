# implement

## Purpose

Make the locked tests pass and complete the approved change, including the
docs it makes stale. Runs as its own role in a fresh context (design rule
R12, in `.cortex/design-rules.md`), separate from the test writer and the reviewer.

## Preconditions

- A change folder whose `proposal.md` has the user's approval line and whose
  folder has a `lock.md` (written by `test-first`). If not, stop and name the
  missing step (`test-first`).
- `bash scripts/cortex/tests-locked.sh <change-folder>` passes before you start.
- You are on the change branch.
- Load `docs/constitution.md`, the repository's `AGENTS.md`, and
  only the knowledge files the change folder names.

## Procedure

1. If `review-findings.md` exists in the folder with open findings, triage
   each against the current code before any work, with evidence: does the
   input occur, does it reproduce, is it reachable. Under that round, record
   one outcome per finding with a one-line reason, and commit the file:
   **fix**; **fix via test-first** (only when a test can exercise real
   behavior; you never write it: report it, and the user decides whether
   `test-first` re-runs, as in step 2); **known limitation**; or
   **disputed**. A disputed finding stops for the user, who decides: you
   are biased toward rejecting it, the reviewer toward inflating it. So
   does a known limitation on a Medium finding: it is a waiver request, and
   you can't change the reviewer's rating. A High finding, including any
   that breaks the constitution, can't be a known limitation: fix it, or
   stop for the user to change the spec or explicitly amend
   `docs/constitution.md` so it is no longer a High. The **fix** outcomes are then this run's task list. Otherwise
   work through `tasks.md` in order.
2. **The locked tests are the specification.** Never edit, delete, or add a
   test: not one listed in `lock.md`, not an existing test, not a new one.
   Never edit `lock.md` or `.cortex/config` either; both are locked for the
   duration of the change. That is the test writer's job. If a test looks wrong, stop and report it. A wrong
   test is a spec problem; the user decides whether `test-first` re-runs.
3. For each task: make the change, run its done-check, check it off in
   `tasks.md` with a one-line note on what was done, and commit. A commit per
   task means a failed attempt can be reverted to the last good task.
4. When reality diverges from the spec (a different mechanism, a changed
   interface, a behavior the tests forced), stop and propose the spec update
   to the user; with their confirmation, record it in an `## As built`
   section of `design.md` and continue. Never let code drift silently from
   the folder.
5. Update any doc the change makes stale: `AGENTS.md`, `docs/knowledge/`,
   a README. Only what actually changed.
6. Before handing off, run `bash scripts/cortex/gates.sh <change-folder>` (the
   test lock, the build, test and lint commands from `.cortex/config`, and
   the harness check) and paste its output under `## Gate output` in
   `tasks.md`, then commit `tasks.md`: `review` requires a clean tree. It
   must end with `gates: ok`.

Budget: 3 attempts per task at passing its done-check. On the third failure,
or when the same failure recurs on two consecutive attempts, stop, record
what was tried in the task's note, and escalate to the user.

## Output

Commits on the change branch, `tasks.md` checked off with notes and gate
output, docs updated. End by telling the user to run `review` in a **fresh
context** that has not seen this conversation.

## Autonomy

May work through in-budget tasks unattended. Must stop for the user on a
test that looks wrong, a disputed finding or waiver request, spec
divergence, a constitution conflict, or budget exhaustion. Never pushes or
merges.
