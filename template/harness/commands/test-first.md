# test-first

## Purpose

Write the failing tests for an approved change, before any implementation
exists, and lock them. This runs as its own role in a fresh context (design
rule R12): a context that already has the implementation in mind shapes the
tests to fit it, so the tests stop encoding the spec.

## Preconditions

- A fresh context. If this conversation already contains the planning or an
  implementation of this change, stop and tell the user to start this command
  in a fresh session or isolated context.
- A change folder whose `proposal.md` has a filled-in approval line written
  by the user, and a filled `tasks.md`. If either is missing, stop and name
  the step (`spec-clarify`, or the user's approval).
- The work happens on a branch named for the change folder, not the default
  branch. Create it if needed.
- Load `harness/policies/constitution.md` and the repository's `AGENTS.md`
  (for the test command and conventions).

## Procedure

1. Read only the change folder and the code the tests will exercise. Don't
   read or plan the implementation.
2. For each criterion marked **automatable**, write one or more tests in the
   repository's test style. Create or edit test files and test fixtures only;
   never an implementation file.
3. Run the test command and confirm each new test **fails for the expected
   reason**: the behavior is missing, not a typo, an import error, or a
   broken fixture. A test that passes before the implementation exists tests
   nothing; rewrite it.
4. Commit the tests on the change branch. Record in `tasks.md`:
   - a line `Tests-locked-at: <the commit's full sha>`;
   - a `## Locked tests` heading followed by one `- <path>` line per test or
     fixture file this command created or changed;
   - the mapping from each criterion to its test(s).
5. Record each **manual-verify** criterion in `tasks.md` as an item that
   needs the user's sign-off after implementation.
6. Run `scripts/cortex/tests-locked.sh <change-folder>` and confirm it passes.

Budget: 3 attempts to get a test failing for the right reason. On the third
failure, stop and tell the user: the criterion is probably not testable as
written, which is a spec problem for `spec-clarify`.

## Output

A commit containing only tests and fixtures, and `tasks.md` updated with the
lock, the locked-file list and the criterion-to-test mapping. End by telling
the user to run `implement` in a fresh context.

## Autonomy

May write and commit tests on the change branch unattended. Must stop for the
user on a missing approval, an untestable criterion, or budget exhaustion.
Never edits implementation files, never pushes.
