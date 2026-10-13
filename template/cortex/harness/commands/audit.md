# audit

## Purpose

Find what no single change shows: docs that changes have made false
between them, friction that recurs across changes, and things the
repository could delete. A per-change review sees only its own diff, so a
fact two changes together make false is seen by neither. Run it when
`retro` proposes it, or on demand.

## Preconditions

- A clean working tree, on a branch other than the default.
- Load `cortex/constitution.md`.

## Procedure

1. **List the surface**, now, from the repository (a list kept here would
   go stale): the repository's `AGENTS.md` files (the root one outside
   cortex's block, and a package's own), `cortex/AGENTS.md`, every file
   under `cortex/knowledge/`, the constitution's `## Project` section,
   `cortex/deferred-practices.md`, the project's agent instructions the
   router names, and the READMEs and docs that the router or the knowledge
   index names. Leave out `cortex/harness/` (procedure, which upgrades
   replace), change folders, the archive and the logs: they record the
   past.
2. **Read it, fresh.** A fresh, read-only context gets the list and this
   instruction: "Read each listed file in full. Extract every checkable
   claim (a path, a command, a list, a cross-reference, a stated
   convention) and check it against the repository; don't assume. Report
   each claim that is now false, with what is true and a fix. Report each
   fact copied by hand into two or more files, naming every copy and which
   should be the source (constitution E4). Nominate at least one thing to
   delete or merge, weighing the severity of what it would catch and not
   only how often it fires, or say why nothing qualifies. Edit nothing."
   A surface more than one context can read in full is split across fresh
   readers with the same instruction (design rule R13).
3. **Recurring friction, when due:** when
   `cortex/changes/pipeline-log.md` has 10 or more rows past the count the
   last row of `cortex/changes/audit-log.md` covered. A second fresh,
   read-only context gets the pipeline log, the audit log and
   `cortex/deferred-practices.md`, and this instruction: "Group friction
   that recurs in two or more rows: the same gate failure, finding kind,
   cause of a review round, escaped defect or retro edit. For each group,
   name its rows and propose the smallest structural change that would
   have prevented it, in this order of preference: delete or merge
   something, a mechanical check, a correction in place, and a new sentence
   only when none fits, saying what it replaces. Name any retro edit that
   later rows show didn't hold, and any deferred practice whose trigger
   fired across rows. Don't repeat a proposal the audit log lists as
   declined unless newer rows add evidence. At most five groups, the
   costliest first. Edit nothing."
4. **Decide.** Show the user every finding as the readers returned it; the
   session that merged them judges none (R13). Add your own evidence
   beside a finding where you have some (the file and line, or the
   command and its output). The user decides each one. Before an approved
   edit to `cortex/harness/`, the constitution, an `AGENTS.md` file,
   `cortex/knowledge/` or the project's agent instructions is applied, it
   gets the independent read `retro` step 5 describes.
5. **Record** one row in `cortex/changes/audit-log.md` (its header defines
   the columns), once the user has decided: what was applied, and what was
   declined and why, so the next audit doesn't propose it again.

Budget: one pass of each reader; no loop. A finding the user declines is
recorded, not re-raised in this audit.

## Output

The audit-log row and the approved edits, landed like any change: on a
branch, through a pull request. An approved edit that changes how a
command behaves is a change of its own, with its change folder.

## Autonomy

The readers are read-only. The session lists the surface and gathers
evidence unattended, and applies only the edits the user approved. Never
pushes or merges.
