# Audit log

One row per `audit` (`cortex/harness/commands/audit.md`), appended once
the user has decided on its findings. `retro` reads the last row's
**Log rows** to tell when the next audit is due (10 more pipeline-log
rows), and the audit's friction reader reads **Declined** so it doesn't
propose the same thing again without new evidence.

Columns:

- **Log rows** — how many rows `cortex/changes/pipeline-log.md` had when
  this audit ran.
- **Stale** — claims found false, then how many were fixed.
- **Copied** — facts found copied by hand into two or more files.
- **Applied** — what changed, in a few words.
- **Declined** — each declined finding or proposal, with the user's reason.

| Date | Log rows | Stale | Copied | Applied | Declined |
| ---- | -------- | ----- | ------ | ------- | -------- |
