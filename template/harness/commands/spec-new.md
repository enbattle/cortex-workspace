# spec-new

## Purpose

Start a change folder for a unit of nontrivial work (a feature, a bugfix of
unknown size, a refactor) and draft its proposal with the user.

## Preconditions

- A description of the work from the user. If the request is trivial by the
  rule in `AGENTS.md`, say so and stop: it doesn't need a change folder.
- Load `harness/policies/constitution.md`.

## Procedure

1. Create `changes/<yyyymmdd>-<slug>/` (today's date, a short kebab-case
   slug) and copy the three files from `harness/templates/change-folder/`
   into it. In a monorepo the folder still lives at the root; list the
   packages it touches in the proposal.
2. Read `docs/knowledge/index.md` and only the knowledge files it points to
   for this area, plus the code the change will touch. A proposal written
   without reading the code invites a mismatched implementation.
3. Draft `proposal.md` with the user: the problem, the desired outcome,
   acceptance criteria, non-goals, and affected areas. Acceptance criteria
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

`changes/<yyyymmdd>-<slug>/` with a drafted `proposal.md` and skeleton
`design.md` and `tasks.md`. End by telling the user to run `spec-clarify`.

## Autonomy

May create the folder and draft text. Must stop for the user on every
acceptance criterion and on any constitution conflict. Never writes the
approval line.
