# audit

## Purpose

Find what no single change shows: docs that changes have made false
between them, friction that recurs across changes, and things the
repository could delete. A per-change review sees only its own diff, so a
fact two changes together make false is seen by neither. Run it when
`retro` proposes it (`cortex/changes/audit-log.md` says when one is due),
or on demand.

## Preconditions

- A clean working tree, on a branch of its own from an up-to-date default
  branch (`audit/<yyyymmdd>`), not inside a change in progress.
- Load `cortex/constitution.md`.

## Procedure

1. **List the surface**, now, from the repository (a list kept here would
   go stale): the repository's `AGENTS.md` files (the root one outside
   cortex's block, and a package's own), `cortex/AGENTS.md`, every file
   under `cortex/knowledge/`, the constitution's `## Project` section,
   `cortex/deferred-practices.md`, the project's agent instructions the
   router names, and the READMEs and docs that the router or the knowledge
   index names. This surface is design rule R5's one exception: the
   audit's job is the whole of it. Leave out `cortex/harness/` (procedure,
   which upgrades replace), change folders, the archive and the logs: they
   record the past.
2. **Read it, fresh.** A fresh, read-only context gets the list and this
   instruction: "Read each listed file in full. Extract every checkable
   claim (a path, a command, a list, a cross-reference, a stated
   convention) and check it against the repository; don't assume. Check a
   command by reading where it is defined (the configuration, the script,
   the package manifest), not by running it. Report each claim that is now
   false, with what is true and a fix. Report each fact copied by hand into
   two or more files, naming every copy and which should be the source
   (constitution E4). Nominate at least one thing to delete or merge,
   weighing the severity of what it would catch and not only how often it
   fires, or say why nothing qualifies. Edit nothing." A surface more than
   one context can read in full is split across fresh readers with the
   same instruction (R13).
3. **Recurring friction, when due** (the audit log's header says when). A
   second fresh, read-only context gets `cortex/changes/pipeline-log.md`,
   `cortex/changes/audit-log.md` and `cortex/deferred-practices.md`, and
   this instruction: "Group friction that recurs in two or more rows of the
   pipeline log: the same gate failure, finding kind, cause of a review
   round, escaped defect or retro edit. For each group, name its rows and
   propose the smallest structural change that would have prevented it, in
   this order of preference: delete or merge something, a mechanical check,
   a correction in place, and a new sentence only when none fits, saying
   what it replaces. Name any retro edit that later rows show didn't hold,
   and any deferred practice whose trigger fired across rows. Don't repeat
   a proposal the audit log lists as declined unless newer rows add
   evidence. At most five groups, the costliest first. Edit nothing."
4. **Decide.** Draft an edit for each finding you can (an exact change to
   the file it names), and give every edit that touches `cortex/harness/`,
   the constitution, an `AGENTS.md` file, `cortex/knowledge/` or the
   project's agent instructions the independent read of `retro` step 5.
   Then show the user every finding as the readers returned it (the session
   that merged them judges none: R13), with your evidence and draft edit
   beside it and the edit reader's findings you couldn't refute. The user
   decides each one. An approved edit that changes how a command behaves
   isn't applied here: it is a change of its own (`spec-new`), and the
   audit log records it as deferred to that change.
5. **Apply and record.** Apply the approved edits, append one row to
   `cortex/changes/audit-log.md` (its header defines the columns), and
   commit them together on the audit's branch.

Budget: one pass of each reader; no loop. A finding the user declines is
recorded, not re-raised in this audit.

## Output

A commit on the audit's branch with the approved edits and the audit-log
row, for a pull request the user opens. Deferred edits are named in the
row.

## Autonomy

The readers are read-only. The session lists the surface, gathers
evidence and drafts edits unattended, applies only what the user approved,
and commits on the audit's branch. Never pushes or merges.
