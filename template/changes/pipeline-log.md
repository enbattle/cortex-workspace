# Pipeline log

One row per change, appended by `retro`. Each retro only sees its own change;
this table is what lets a pattern across changes show up, and what makes a
retro checkable: a change with failed gates or real findings whose retro says
"nothing to change" should say why.

Rows are never rewritten, except to fill in **Escaped defect** when a later
fix traces a bug to that change. An escaped defect is the most important
signal in this file and gets a retro immediately.

Columns:

- **Change** — the change folder's path.
- **Gate failures** — a count, then a few words: every failed gate
  (`tests-locked.sh`, build, test, lint, `check.sh`) and every `test-first`
  re-run; `0` if none.
- **Findings** — first review round's findings introduced by the change, as
  high/medium/low counts, plus `, pre:N` for findings already present.
- **Rounds** — request-changes rounds used (0–2).
- **Retro** — what was actually applied, or `nothing to change` with the reason.
- **Escaped defect** — empty until a later fix traces a bug here.

| Date | Change | Gate failures | Findings (H/M/L, pre) | Rounds | Retro | Escaped defect |
| ---- | ------ | ------------- | --------------------- | ------ | ----- | -------------- |
