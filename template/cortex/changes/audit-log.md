# Audit log

One row per `audit` (`cortex/harness/commands/audit.md`), appended once
the user has decided on its findings.

**When an audit is due.** When `cortex/changes/pipeline-log.md` has 10 or
more rows past the **Log rows** of the last row here whose **Friction** is
`yes`, or 10 rows and no such row. `retro` then proposes one, and `audit`
runs its friction read (step 3). This paragraph is the one statement of
the rule; the commands point here.

Columns:

- **Log rows** — how many rows the pipeline log had when this audit ran.
- **Friction** — `yes` if the friction read ran, else `no`.
- **Stale** — claims found false, then how many were fixed.
- **Copied** — facts found copied by hand into two or more files.
- **Applied** — what changed, in a few words; an edit deferred to a change
  of its own as `deferred to <change folder>`.
- **Declined** — each declined finding or proposal, with the user's
  reason, so the next audit doesn't propose it again without new evidence.

| Date | Log rows | Friction | Stale | Copied | Applied | Declined |
| ---- | -------- | -------- | ----- | ------ | ------- | -------- |
