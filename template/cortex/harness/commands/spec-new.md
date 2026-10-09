# spec-new

## Purpose

Start a change folder for a unit of nontrivial work (a feature, a bugfix of
unknown size, a refactor) and draft its proposal with the user.

## Preconditions

- A description of the work from the user. If the request is trivial by the
  rule in `cortex/AGENTS.md`, say so and stop: it doesn't need a change folder.
- Load `cortex/constitution.md`.

## Procedure

1. Create a branch `change/<yyyymmdd>-<slug>` from an up-to-date default
   branch (the same date and slug as the folder), then create `cortex/changes/<yyyymmdd>-<slug>/` (today's date, a short kebab-case
   slug) on it and copy `proposal.md`, `design.md` and `tasks.md` from
   `cortex/harness/templates/change-folder/` (not `lock.md`: `test-first` adds it in a
   commit of its own, and the lock fails if any other commit touches it)
   into it. In a monorepo the folder still lives at the root; list the
   packages it touches in the proposal.
2. Read `cortex/knowledge/index.md` and only the knowledge files it points to
   for this area, plus the code the change will touch. A proposal written
   without reading the code invites a mismatched implementation. Before
   changing or removing a behavior, check why it exists: the history of
   those lines, and the change folder or pull request that added them.
   Note in the proposal anything there that bears on the change; a
   deliberate behavior removed by accident is a regression no new test
   catches.
3. Draft `proposal.md` with the user: the problem, the desired outcome,
   acceptance criteria, non-goals, and affected areas. For a bug fix, the
   problem records how to reproduce it and its root cause, or says the
   cause isn't known yet so `spec-clarify` asks: a fix aimed at the symptom
   passes a test written for the symptom. Acceptance criteria
   must be objectively checkable: concrete numbers, behaviors, error cases
   and edge cases. Reject a vague one ("users can log in") and push for the
   precise version ("a wrong password returns 401 with no hint whether the
   account exists; five failures in 10 minutes lock the account for 15").
4. Check the draft against the constitution. If the work needs to break a
   principle there, say so now; the user either amends the constitution or
   changes the request.
5. Leave `design.md` and `tasks.md` as skeletons; `spec-clarify` fills them.

Budget: does not iterate beyond the conversation with the user; stop when the
user agrees the proposal draft says what they want.

## Output

`cortex/changes/<yyyymmdd>-<slug>/` with a drafted `proposal.md` and skeleton
`design.md` and `tasks.md`. End by telling the user to run `spec-clarify`.

## Autonomy

May create the folder and draft text. Must stop for the user on every
acceptance criterion and on any constitution conflict. Never writes the
approval line.
