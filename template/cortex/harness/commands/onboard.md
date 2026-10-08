# onboard

## Purpose

Walk a new engineer through this repository and its workflow, interactively.

## Preconditions

- Load `docs/knowledge/index.md`, `docs/knowledge/architecture.md` and
  `docs/knowledge/glossary.md`. If any is still a placeholder, say which and
  offer to help fill it in first.

## Procedure

1. Give a short tour: what the system does, its main components and who owns
   them, and the terms people confuse (from the glossary).
2. Explain the change workflow with a dry run on a made-up small change:
   where its change folder would live, what each command would produce, and
   why the test writer, implementer and reviewer run in separate fresh
   contexts.
3. Show how to invoke a command in their agent tool (the universal form is
   *"Read and execute `harness/commands/<name>.md`"*).
4. Check understanding with two questions: where would a change folder for a
   given hypothetical change go, and what should they do if `implement` says
   a test looks wrong?
5. Note anything they found confusing; confusion from fresh eyes is a
   documentation finding for `retro`, not a gap in the newcomer.

Budget: does not iterate beyond the conversation; stop when both questions
are answered correctly or the engineer wants to stop.

## Output

A conversation, plus a list of confusing spots for `retro`.

## Autonomy

Conversational only; writes nothing.
