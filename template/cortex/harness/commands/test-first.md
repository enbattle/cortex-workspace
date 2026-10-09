# test-first

## Purpose

Write the failing tests for an approved change, before any implementation
exists, and lock them. This runs as its own role in a fresh context (design
rule R12, in `cortex/design-rules.md`): a context that already has the implementation in mind shapes the
tests to fit it, so the tests stop encoding the spec.

## Preconditions

- A fresh context. If this conversation already contains the planning or an
  implementation of this change, stop and tell the user to start this command
  in a fresh session or isolated context.
- A change folder whose `proposal.md` has a filled-in approval line (written
  by the user, or on their explicit instruction: design rule R6), and a
  filled `tasks.md`. If either is missing, stop and name
  the step (`spec-clarify`, or the user's approval).
- You are on the change branch, and its latest commit contains the approved
  change folder (`spec-clarify` commits it). If not, stop and say so.
- Load `cortex/constitution.md` and the repository's `AGENTS.md` files
  (for conventions; the test command is `TEST_CMD` in `cortex/config`).
- A re-lock: `lock.md` already exists, and either the user has decided this
  command re-runs because a locked test is wrong (reported by `implement`),
  or the branch has just merged a base that changed locked files. Go to
  step 7.

## Procedure

1. Read only the change folder and the code the tests will exercise. Don't
   read or plan the implementation.
2. For each criterion marked **automatable**, write one or more tests in the
   repository's test style, to the bar in the Tests section of
   `cortex/harness/policies/review-checklist.md`. Create or edit test files and
   test fixtures only; never an implementation file.
3. Run the test command and confirm each new test **fails for the expected
   reason**: the behavior is missing, not a typo, an import error, or a
   broken fixture. A test that passes before the implementation exists tests
   nothing; rewrite it. The exception is a criterion that guards existing
   behavior ("inputs without the new option behave as before"): its test is
   expected to pass now. Say so in the criterion-to-test mapping.
4. Commit the tests on the change branch (commit T). Then, as the **very
   next commit**, copy `cortex/harness/templates/change-folder/lock.md` into the
   change folder, fill in T's full sha and one `- <path>` line per test or
   fixture file T created or changed, and commit it alone. That file isn't
   edited again except by a re-lock (step 7); existing tests matching
   `TEST_GLOBS`, and `cortex/config` itself, are locked automatically. Then fill in
   `## Criteria to tests` in `tasks.md` and commit it.
5. Record each **manual-verify** criterion in `tasks.md` as an item that
   needs the user's sign-off after implementation.
6. Run `bash cortex/bin/tests-locked.sh <change-folder>` and confirm it passes.
7. **Re-lock**, only when the user has decided this command re-runs because
   a locked test is wrong (a spec problem `implement` reported), or after
   merging a base that changed locked files. T2 is a commit of the corrected
   tests and fixtures alone, or, after such a merge, the merge commit.
   Neither may change `cortex/config`: if the base changed it, the change
   can't take that base in; stop and tell the user that the merge must be
   undone, and the change finished without that base or started over from
   it. Rewrite `lock.md`: T2's full sha, every file the earlier lock listed,
   and every file T2 created or changed. Stop for the user's sign-off on
   the `Re-lock signed off by:` line: they write it, or explicitly tell you
   to (design rule R6). If you
   run as an isolated agent that can't wait for the user, stop here with
   `lock.md` written but uncommitted and say so; the session the user is
   talking to gets the sign-off and commits it. Commit `lock.md` alone as
   the very next commit after T2 (the sign-off blesses only T2's own
   changes: anything changed in locked files before T2 still fails), update
   `## Criteria to tests` in `tasks.md`, and repeat step 6.

Budget: 3 attempts to get a test failing for the right reason. On the third
failure, stop and tell the user: the criterion is probably not testable as
written, which is a spec problem for `spec-clarify`.

## Output

Three commits: the tests and fixtures only; `lock.md` only (naming the
first); `tasks.md` with the criterion-to-test mapping. A re-lock adds the
corrected tests, then the signed `lock.md`, then the updated mapping. End by telling
the user to run `implement` in a fresh context.

## Autonomy

May write and commit tests on the change branch unattended. Must stop for the
user on a missing approval, an untestable criterion, budget exhaustion, or
a re-lock's sign-off.
Never edits implementation files, never pushes.
