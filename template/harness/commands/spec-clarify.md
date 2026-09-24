# spec-clarify

## Purpose

Interrogate a proposal for ambiguity before any test or code exists, then
plan the work. This is the cheapest place to find a mistake: be adversarial
toward the spec, not polite to it.

## Preconditions

- A change folder with a drafted `proposal.md` (from `spec-new`). If there is
  none, stop and tell the user to run `spec-new`.
- Load `harness/policies/constitution.md`, `docs/knowledge/glossary.md`, and
  only the knowledge files the proposal's affected areas point to.

## Procedure

1. Read the proposal and generate questions in these categories:
   - undefined or overloaded terms (check the glossary);
   - unstated assumptions (about data, users, load, ordering, existing
     behavior);
   - missing error and edge behavior (empty, huge, concurrent, repeated,
     partial failure);
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
   rejected, risks, rollback plan. Fill `tasks.md`: small, ordered tasks,
   each with a done-check that can be run or observed.
6. Ask the user to review the folder and approve it by writing the approval
   line in `proposal.md` themselves. Don't write it, fill it in, or draft it.

Budget: at most 4 rounds of questions. If the proposal still isn't clear
enough after 4 rounds, stop and tell the user the scope is too uncertain to
specify yet (a spike or a smaller first change may be needed).

## Output

The same change folder with an updated `proposal.md` (criteria marked
automatable or manual-verify), a filled `design.md` and `tasks.md`, and a
request for the user's approval. End by telling the user to run `test-first`
once they have approved.

## Autonomy

May draft questions, designs and tasks. Must stop for the user's answers and
for approval. Never writes the approval line.
