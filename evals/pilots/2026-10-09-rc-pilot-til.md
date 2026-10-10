# Release-candidate pilot (criterion 48) — til, 2026-10-09

The 3.0.0 spec's criterion 48: install `3.0.0-rc.1` into a real existing
repository on a branch, take one real change through the pipeline, upgrade
to `3.0.0-rc.2` keeping a user edit, and remove cortex on a throwaway branch.

- **Repository:** the maintainer's `til`, a static reference site (Vite,
  React, TypeScript, Python examples), deployed to GitHub Pages. It has its
  own `CLAUDE.md` and docs, its own change pipeline (`/feature`,
  `docs/SDLC.md`), Prettier and oxlint, an `npm run verify` that CI and the
  deploy run, and a `.claude/settings.json` with its own deny and ask rules.
- **Setup:** Windows 11, Claude Code with claude-opus-5-5, one session. All
  pilot work was on local branches from `main` (ac81474). Nothing was pushed,
  and the branches were deleted afterwards.
- **Deviation from criterion 48:** the agent was not "given only the
  one-sentence requests". The session that ran the pilot had written 3.0.0
  and knew the scripts. So this pilot tests the mechanics and the fit with a
  real project, not whether a fresh agent can follow `INSTALL.md` cold. The
  pipeline's own agents (spec briefer, test writer, implementer, reviewer)
  were fresh subagents, as the commands require.

## Results

| Step | Outcome |
| --- | --- |
| Install rc.1 | Footprint exact; nothing of the project's changed. Findings F1–F4 (below) broke the project's gate or conflicted with its rules, so they shipped as rc.2 (spec Amendment 3, PR #27). |
| One change | "`/` opens the search dialog" went through every stage: spec-new, spec-clarify (the brief took 2 rounds), test-first and the lock, implement, review and retro. 0 gate failures, findings 0/0/2. The developer checked it by hand in Chromium; Firefox wasn't available, so that half is unverified and recorded as such. |
| Upgrade to rc.2 | 4 replaced, 0 merged, 1 conflict. The edited files were kept (the constitution's Project section P1–P2, the knowledge files, the workflow, the pipeline log). Blocks Prettier had reformatted were judged `unchanged`, and their records gained the non-blank sha (F5). `check.sh` ok, `npm run format:check` ok. |
| Remove (throwaway branch) | Stopped at hosting, then at the one reference, then ran: 18 removed, 0 kept, 44 entries to remove by hand, records kept in `docs/cortex-records/`. Compared with `main`: `CLAUDE.md` is byte-identical (block removed, Prettier's blank lines included), and every created file is gone, root `AGENTS.md` too. What remains is the feature's own changes, the 44 listed settings lines, one `.prettierignore` line (R1 below) and the records. |

## Findings fixed in rc.2 (spec Amendment 3)

- **F1. Prettier rewrote both blocks, and `adapt.sh` rewrote them back**, so
  `npm run format:check` could never stay green. Fix: framed blocks, and a
  comparison that ignores blank lines everywhere.
- **F2. Prettier flagged ten files under `cortex/`.** Fix: `adapt.sh` asks for
  `cortex/` in `.prettierignore` and records the entry. INSTALL now has the
  agent run `LINT_CMD` once after adapt.
- **F3. Two processes and two sets of agent instructions.** The router said
  only to read the root `AGENTS.md`, which in til holds only cortex's block
  (the project's rules are in `CLAUDE.md`). Fix: the router names the
  project's files and says the stricter rule applies. INSTALL step 3 asks
  at install which process governs nontrivial changes and records the answer
  in the conventions.
- **F4. Smaller fixes:**
  - `TEST_GLOBS` anchoring is now documented.
  - The patterns matching no tracked file are noted.
  - The chmod note names only the executables.
  - The summary count is now correct.
  - INSTALL now states the Code Owners limits for a sole maintainer and for Dependabot.
  - INSTALL step 4 covers an agent's permissions refusing the settings merge (the
    maintainer merged `.claude/settings.json` by hand).
- **F5. Decisions taken while implementing**, approved with PR #27: the
  sixth footprint field, executables found by name (a Windows clone has no
  file modes), what `<n>` counts, and the `.prettierignore` variants.

The first CI run on the rc.2 branch failed shellcheck (SC2120). After that
fix, the golden fixture was stale and failed on Linux, because it had been
refreshed before the fix. Both were fixed before the merge.

## Findings for 3.1 (not fixed)

- **R1. An upgrade from rc.1 doesn't record a `.prettierignore` entry that
  already exists.** The line was added by hand under rc.1, so the footprint
  doesn't have it and `remove.sh` leaves it behind. Only installs made
  before rc.2 are affected. The upgrade could record an existing entry the
  way adapt does.
- **R2. A reworded placeholder conflicts with every filled-in section.** rc.2
  reworded the `## Conventions` comment. til had replaced that comment with
  its own lines, so the upgrade's three-way merge gave a conflict. It was
  resolved by keeping the project's lines. Every install that filled in its
  conventions will hit this whenever the placeholder changes. The upgrade
  could take the project's side automatically when the old version's text
  in that region was only the placeholder.
- **R3. implement left tasks open.** It wrote "Done:" notes on tasks 2, 3 and 5
  but didn't tick them, so review stopped at its precondition. The retro
  proposed making an open task fail `gates.sh`, and stopping spec-clarify
  from writing a "run the gates" task, which would itself still be open
  when the gates run. The developer declined both for this change and
  deferred the first to a later cortex release.
- **R4. Review's approval leaves no record.** An approve verdict is said, not
  written down, so the next session can't tell that a change was reviewed.
- **R5. Review's inputs omit the project's own instructions** (`CLAUDE.md` and
  the `docs/NON_NEGOTIABLES.md` that til's constitution P1 names), so the
  reviewer applies them only if it follows the router. Partly addressed by
  F3's router line.
- **R6. Pipeline friction:**
  - spec-new branches from `main`, not from the branch the install is on,
    which is wrong when cortex itself isn't merged yet.
  - "One command per call" assumes the working directory is the repository root.
  - It isn't clear whether approving the spec also approves committing it.
    The maintainer had the operator write the approval line on their
    instruction (as in pilot 3b's P9).
- **R7. The retro row was written before the developer answered** the
  proposals, then rewritten. retro should ask first, then write the row.
- **R8. remove's reference stop** found the one real reference: a test comment
  that cites the change folder's `proposal.md`. Removal moves the folder to
  `docs/cortex-records/` but doesn't rewrite the citation. That's
  acceptable (the stop exists for this), but a hint pointing at the moved
  path would make the fix obvious.

## Cleanup

In til:
- The pilot branches (`pilot/cortex-rc1`, `pilot/cortex-rc2`,
  `pilot/cortex-remove`) were deleted.
- `main` is unchanged at ac81474.
- The ignored files, local config and hooks match the snapshot taken before
  the install.
- No processes from the pilot are running.
- The `origin/*` refs differ from the snapshot. A separate session working
  in til ran `git fetch --prune` there during the pilot, after til's PR #114
  merged. The refs show the remote as it now is, so they were left alone.

The scratch clone of cortex was deleted.
