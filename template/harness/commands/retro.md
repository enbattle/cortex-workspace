# retro

## Purpose

Turn friction from a finished change into specific edits to the harness or
the knowledge, and log the run so patterns across changes become visible.
This is the maintenance loop for everything under `harness/` and
`docs/knowledge/`; it produces diffs, not impressions.

## Preconditions

- A change that has been through `review` (approved or stopped), or a session
  the user wants to reflect on.
- The change folder, its `review-findings.md` if any, and the gate output in
  `tasks.md`. Friction is taken from these, not from memory.

## Procedure

1. Collect friction that actually happened. Don't invent any:
   - context an agent needed and couldn't find (a knowledge gap, or a routing
     failure: check which before fixing);
   - an instruction that was ambiguous or ignored (a command edit);
   - knowledge that was wrong or stale (a correction);
   - a gate that failed, or a step that added nothing (a candidate for
     removal: deletions count as improvements);
   - an adapter that broke (`scripts/cortex/adapt.sh` or its source).
2. For each, propose a specific file edit, at the strongest level that fits:
   a mechanical check (a script or test) first, then a correction to the file
   that already covers it, then new text only if neither applies. A new
   check gets a planted-violation test before it's trusted.
3. A recurring review finding (the same kind across changes) means something
   upstream leaks: propose moving the check earlier (the constitution, the
   clarify questions, the repository's conventions).
4. Check `docs/deferred-practices.md`: has any entry's trigger fired during
   this change? If so, propose adopting it to the user (a large one is its
   own change folder) and update the entry; don't build it inside the retro.
5. Show the user the proposed edits. Apply only what they approve.
6. Append one row to `changes/pipeline-log.md` recording what was actually
   applied (its header defines the columns). An **escaped defect** (a bug
   found after review approved the change that introduced it) is recorded
   in that change's row and gets a retro immediately.

Budget: one pass over the evidence; no loop. Proposals the user declines are
logged in the row, not re-proposed in the same retro.

## Output

Approved edits applied, and one new row in `changes/pipeline-log.md`.

## Autonomy

May collect evidence and draft edits unattended. Must stop for the user
before applying any edit.
