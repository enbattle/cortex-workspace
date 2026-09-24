# implement

## Purpose

Make the locked tests pass and complete the approved change, including the
docs it makes stale. Runs as its own role in a fresh context (design rule
R12), separate from the test writer and the reviewer.

## Preconditions

- A change folder whose `proposal.md` has the user's approval line and whose
  `tasks.md` has a `Tests-locked-at:` line and a `## Locked tests` list. If
  not, stop and name the missing step (`test-first`).
- `scripts/cortex/tests-locked.sh <change-folder>` passes before you start.
- You are on the change branch.
- Load `harness/policies/constitution.md`, the repository's `AGENTS.md`, and
  only the knowledge files the change folder names.

## Procedure

1. If `review-findings.md` exists in the folder with open findings, those
   findings are this run's task list. Otherwise work through `tasks.md` in
   order.
2. **The locked tests are the specification.** Never edit, delete, or add a
   file listed under `## Locked tests`, and never add new test files: that is
   the test writer's job. If a test looks wrong, stop and report it. A wrong
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
6. Before handing off, run the gates yourself and include their output in
   `tasks.md`:
   - `scripts/cortex/tests-locked.sh <change-folder>` (the locked tests are untouched);
   - the build, test and lint commands from `AGENTS.md`, all passing;
   - `scripts/cortex/check.sh` (the harness is intact).

Budget: 3 attempts per task at passing its done-check. On the third failure,
or when the same failure recurs on two consecutive attempts, stop, record
what was tried in the task's note, and escalate to the user.

## Output

Commits on the change branch, `tasks.md` checked off with notes and gate
output, docs updated. End by telling the user to run `review` in a **fresh
context** that has not seen this conversation.

## Autonomy

May work through in-budget tasks unattended. Must stop for the user on a
test that looks wrong, spec divergence, a constitution conflict, or budget
exhaustion. Never pushes or merges.
