# Plan: an audit across changes, an independent read of retro edits, and a ruling on disputed findings (3.5.0)

Status: **approved by the maintainer, 2026-10-13** (written by the agent on
the maintainer's instruction, "Approve; you record it", with the cadence
at 10 log rows). A point-in-time record.

## Context

3.4.0 (`docs/specs/2026-10-13-til-ports.md`) left two of `til`'s practices
for later, "after the first real install's first retros": a docs
staleness audit and an independent read of the retro's process edits. Its
audit recorded a third gap as a known limitation: when the user agrees a
disputed finding isn't real, nothing says what is recorded. On 2026-10-13
the maintainer asked for all three now, before a real install.

That changes the evidence behind **Fit** (R14). It rests on mechanism and
on `til`, not on a cortex install:
- **Drift across changes.** A per-change review sees only its own diff,
  so a fact that two changes together make false is seen by neither.
  `til`'s audits found 14, 24 and 9 inaccurate claims and 11-15
  hand-copied facts in their first runs, and five friction aggregations
  whose proposals were mostly applied.
- **The retro author's blind spot.** The session that writes a process
  edit reads it with the reasoning that produced it, and hasn't loaded
  the text it may contradict. `til`'s reader narrowed edits (its log, rows
  for raw-html-sink-variants and the 203-row friction fixes).

The catalog's own operating rule applies: the maintainer may adopt before
a trigger, at a stated cost. **Cost:** a command, a role, two Claude Code
agents and a skill, one template file, about 60 lines of procedure, and
the agent runs when they're used (none on a change that runs neither).
None is loaded by routine work (R13). **Reversibility:** text and
template files only; no script changes.

## Items

### A. `audit`: drift, recurring friction and deletion, across changes

A new command, `cortex/harness/commands/audit.md`, run on demand or when
`retro` proposes it (A2). It absorbs two catalog entries, "Pipeline-log
mining" and "Deletion pass" (Deletion, below).

- **Preconditions:** a clean working tree on a branch other than the
  default; load the constitution.
- **Step 1, the surface.** The session lists, at run time (a list kept in
  the command would go stale): the repository's `AGENTS.md` files (the
  root one outside cortex's block), `cortex/AGENTS.md`, every file under
  `cortex/knowledge/`, the constitution's `## Project` section,
  `cortex/deferred-practices.md`, the project's agent instructions the
  router names, and the READMEs and docs the router or the knowledge index
  names. Not: `cortex/harness/` (procedure, replaced by upgrades), change
  folders, the archive and the logs (records of the past).
- **Step 2, the read.** A fresh, read-only context gets the list and the
  instruction: read every file in full; extract each checkable claim (a
  path, a command, a list, a cross-reference, a stated convention) and
  verify it against the repository; report each claim now false, with
  what is true and a fix; report each fact copied by hand into two or more
  files, naming every copy and which should be the source (E4); nominate
  at least one thing to delete or merge, weighed by the severity of what
  it would catch, or say why nothing qualifies. A surface too large for one
  context is split (R13).
- **Step 3, friction, when due:** when `cortex/changes/pipeline-log.md` has
  10 or more rows past the count the last audit covered. A second fresh,
  read-only context gets the log, the audit log's declined proposals and
  `cortex/deferred-practices.md`: group friction that recurs in two or more
  rows (the same gate failure, finding kind, round cause, escaped defect or
  retro edit), propose the smallest structural change for each (a deletion
  or merge first, then a mechanical check, then a correction in place, a
  new sentence last, naming what it replaces), name a retro edit later rows
  show didn't hold and a deferred practice whose trigger fired across rows,
  and repeat no declined proposal without newer evidence. At most five
  groups, costliest first.
- **Step 4, decide.** The session shows every finding as returned (R13: the
  session that merged them judges none), with the evidence it adds for
  each, and the user decides each one. Approved edits to process text
  (A3's list) get the edit reader (B) before they're applied.
- **Step 5, record.** One row in `cortex/changes/audit-log.md`: date, log
  rows covered, stale claims, copied facts, what was applied, what was
  declined and why.
- **Output:** the audit-log row and the approved edits, landed like any
  change (a branch, a pull request); an edit that changes how a command
  behaves is its own change folder.
- **Budget:** one pass; no loop. **Autonomy:** the readers are read-only;
  the session applies only what the user approved.

**A2. When it's proposed.** `retro` gains a step: after the log row, if
the log has 10 or more rows past the last audit's count (or 10 rows and
no audit yet), propose running `audit`. The user decides.

**A3. Where it shows.**
- `cortex/changes/audit-log.md`, a new template file: its header and an
  empty table (Date, Log rows covered, Stale, Copied, Applied, Declined).
- The router: one row ("Auditing docs and friction across changes").
- `permissions.md`: an `audit` row (reads the surface and the logs; writes
  approved edits and the audit log; runs read-only commands; never an
  unapproved edit).
- README's workflow table; the operator guide's "calendar notices" signal
  names the command.
- Claude Code: a `cortex-audit` skill (at most 25 lines, C9) that spawns
  the read-only `cortex-auditor` agent for steps 2 and 3 (two, in parallel,
  when step 3 is due) and never forks.

### B. `retro`: an independent read of process edits

- **R14.** Mechanism and fit: above. Cost: one fresh context per retro
  that proposes a process edit; none otherwise. Reversibility: text.
- **The step.** Before showing the user its proposals (step 5), when any
  proposed edit touches `cortex/harness/`, the constitution, an `AGENTS.md`
  file, `cortex/knowledge/` or the project's agent instructions, a fresh,
  read-only context gets the proposed diff, the friction evidence for each
  edit (the files the retro cited, not its reasoning) and the paths, and
  answers: does an edit contradict existing text (counts and step numbers
  included); could a newcomer apply it two ways; is each edit earned by its
  evidence; would a check or a deletion make the text unnecessary. It also
  dry-runs the edits against two or three realistic changes and says where
  they gave no clear answer. One pass: the retro fixes what it can't refute
  in a sentence and shows the user the rest beside the proposals.
- **R12** names the role and its bias: "the author of a process edit reads
  it with the reasoning that produced it, and hasn't loaded the text it
  may contradict." The four roles stay four; the reader is a
  single-purpose read a stage calls for, like `review`'s security pass.
- Claude Code: the `cortex-retro` skill spawns a read-only
  `cortex-edit-reader` agent for the step.

### C. A ruling on a disputed finding is recorded

- `implement` step 1: when the user rules on a disputed finding, the
  session records the ruling under that round, as one of: **not real** (the
  user agrees it doesn't reproduce or isn't reachable; no work);
  **decision stands** (it contradicts a recorded decision the user keeps;
  no work, and the reviewer re-raises it only with new evidence);
  **fix** (the user revisits the decision: a spec change, with renewed
  approval when the criteria change, R6); or **known limitation** (not
  for a High).
- R13's triage bullet names the same rulings, in one clause.

## Deletion (T14)

- `docs/02-extensions.md` loses "Pipeline-log mining" and "Deletion pass"
  for a pointer to `audit` (adopted).
- Nominated and kept: cortex's own completeness audit (AGENTS.md). It maps
  a plan to evidence for a release, which `audit` doesn't; `audit` runs in
  installed repositories, which cortex isn't.

## Non-goals

- No script: cadence, the surface and the audit log are judged by the
  session and the user; a check that counts rows would duplicate `retro`'s
  step (E4).
- No golden task for `audit` or the reader yet. *Trigger:* a stale claim
  an audit should have found trips a later change, or a reader-approved
  edit is reverted by the next retro.
- No Agents column in the log (3.4.0's Non-goals).
- C15 still doesn't check rows without a leading `|` (3.4.0, known
  limitation).

## Tests and evals

- No script changes, so no new tests; the suites must still pass (a new
  template file and new adapter files go through install, adapt, upgrade
  and remove like the others; C5, C6 and C9 check the command and skills).
- The golden fixture is refreshed (new and changed template files).
- C edits `implement` step 1: the triage golden task runs twice after it,
  and its rubric gains nothing (its findings are triaged, not ruled on).
- A dry run of `audit` and of the reader on the golden fixture's
  repository, recorded in `evals/pilots/`, before release: they run as
  written, and the reader returns something a user can act on.
- A completeness audit before release (`evals/audits/`).

## Release

A minor version (3.5.0): a new command and template file, a new step in
`retro` and `implement`; no contract breaks. A `CHANGELOG.md` entry; the
release steps as for 3.4.0. No push, merge or tag without the
maintainer's go-ahead.
