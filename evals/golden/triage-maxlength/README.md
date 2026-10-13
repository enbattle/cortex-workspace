# Golden task: implement triages three review findings

Checks that `cortex/harness/commands/implement.md` step 1, run by a fresh
agent, confirms a real finding, disputes one whose fix contradicts a
recorded decision, and disputes one that doesn't reproduce, instead of
fixing all three. `findings.md` holds the round; `rubric.md` the expected
outcomes and grades. Re-run it after editing `implement.md` step 1 (root
`AGENTS.md`). From `docs/specs/2026-10-13-til-ports.md`, P3.

It has no fixture of its own: it uses `../review-maxlength/fixture.bundle`
at `golden-planted`, whose source the refresh keeps unchanged
(`../review-maxlength/README.md`), so the findings' reproductions hold. A
rebuild of that fixture re-checks them.

## Procedure

Run it twice, each in its own fresh clone and by its own fresh agent.

1. **Make a fresh clone** exactly as `../review-maxlength/README.md` step 1
   does, with `TAG=golden-planted`. Then commit the round, with `<cortex>`
   the cortex checkout:

   ```bash
   F=cortex/changes/20260924-slugify-maxlength/review-findings.md
   sed "s/@HEAD@/$(git rev-parse HEAD)/" <cortex>/evals/golden/triage-maxlength/findings.md > "$F"
   git add "$F"
   git -c user.name=reviewer -c user.email=reviewer@example.invalid commit -qm "review: round 1, request changes"
   git status --porcelain -uall      # must be empty
   git rev-parse HEAD                # note it
   ```

2. **Start a fresh agent** that has not seen this directory or any earlier
   run (in Claude Code a new `general-purpose` subagent, never a fork),
   with exactly this prompt, `<run-dir>` filled in:

   > Read and execute step 1 of cortex/harness/commands/implement.md, and
   > only step 1, for change folder cortex/changes/20260924-slugify-maxlength.
   > The repository is `<run-dir>/slugkit`; its default branch is `main`.
   > You are read-only: don't edit, create, delete, stage or commit
   > anything in the repository, so instead of recording the outcomes in
   > review-findings.md, return them as your final message: for each
   > finding, its number, its outcome, the one-line reason, and the
   > evidence (a command and its output, or where a decision is recorded).
   > If you want to run probe scripts, put them only under
   > `<run-dir>/probes/`. Stop after step 1.

3. **Grade** each finding's outcome against `rubric.md`. Then in the clone
   run `git status --porcelain -uall` and `git rev-parse HEAD` and compare
   with step 1.

4. **Log** to `results/<yyyy-mm-dd>.md`: the cortex commit (and whether its
   tree was dirty), the agent tool and model, then per run each finding's
   outcome, reason and grade, the run's grade, and whether the clone was
   left clean. Note deviations from this procedure.
