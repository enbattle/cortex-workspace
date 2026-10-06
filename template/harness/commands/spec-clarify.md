# spec-clarify

## Purpose

Interrogate a proposal for ambiguity before any test or code exists, then
plan the work. This is the cheapest place to find a mistake: be adversarial
toward the spec, not polite to it.

## Preconditions

- A change folder with a drafted `proposal.md` (from `spec-new`). If there is
  none, stop and tell the user to run `spec-new`.
- Load `docs/constitution.md`, `docs/knowledge/glossary.md`, and
  only the knowledge files the proposal's affected areas point to.

## Procedure

1. Read the proposal and generate questions in these categories:
   - undefined or overloaded terms (check the glossary);
   - unstated assumptions (about data, users, load, ordering, existing
     behavior);
   - missing error and edge behavior (empty, huge, concurrent, repeated,
     partial failure);
   - compatibility with existing callers and data: who uses the code this
     changes today, and what happens to them (a new parameter, a stricter
     validation, a changed default can all break a caller that the proposal
     never mentions);
   - conflicts with the constitution;
   - acceptance criteria that aren't objectively checkable.
2. Ask the user in batches of at most 5 questions. Update the proposal with
   every answer, in the proposal itself, not only in the conversation.
3. Stop interrogating when you can honestly say: "I could hand this proposal
   to an engineer with no other context and they would build the right
   thing." Say it to the user, with the reason.
4. Mark each acceptance criterion **automatable** (a test will encode it) or
   **manual-verify** (with the reason no test can). `test-first` consumes
   this marking.
5. Fill `design.md`: approach, alternatives considered and why each was
   rejected, risks, rollback plan. Design to the "Design and simplicity"
   section of `harness/policies/review-checklist.md`, and show each
   alternative's call site: a few lines of the caller's code, so the
   options are compared from where they are used. Fill `tasks.md`: small, ordered tasks,
   each with a done-check that can be run or observed. Until the last task
   the locked tests still fail, so an earlier done-check names the tests it
   runs, not the whole test command. A task can't edit a file the test lock
   covers (a non-test file matching `TEST_GLOBS`, such as the test runner's
   config, or `.cortex/config`): flag it before approval and settle it with
   the user (a separate change, or a narrower `TEST_GLOBS`).
6. Brief the user from a fresh context: one that hasn't seen this
   conversation (a new session or an isolated subagent) reads the change
   folder and the files it names and returns one screen, which you save as
   `brief.md` in the folder: what the change does, the decisions in it a reasonable owner
   could make either way, the risks, a recommendation, and any question it
   would still ask. Show the user the brief and ask them to approve. Only
   the user decides (design rule R6): they write the approval line in
   `proposal.md`, or explicitly tell you to fill it in for this change
   folder, in which case write their name marked "(written by the agent on
   <name>'s instruction)" and the date, and commit it yourself with the
   user's instruction quoted in the commit message, so the record shows who
   wrote it and on what words. Never infer approval from anything else, and
   never draft the line.
7. Once the approval line is filled in, commit the change folder (with
   `brief.md`) on the change branch, so the approved spec is in history
   before any test is written against it.

Budget: at most 4 rounds of questions. If the proposal still isn't clear
enough after 4 rounds, stop and tell the user the scope is too uncertain to
specify yet (a spike or a smaller first change may be needed).

## Output

A commit on the change branch containing the approved change folder: an updated `proposal.md` (criteria marked
automatable or manual-verify), a filled `design.md` and `tasks.md`, the brief, and a request for the
user's approval. End by telling the user to run `test-first`
once they have approved.

## Autonomy

May draft questions, designs and tasks. Must stop for the user's answers and
for approval. Writes the approval line only on the user's explicit
instruction (R6), never otherwise.
