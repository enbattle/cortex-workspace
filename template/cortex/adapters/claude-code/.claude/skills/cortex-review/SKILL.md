---
name: cortex-review
description: Adversarially review an implemented change (cortex review), in fresh read-only subagents.
---

Don't run the command in this session, and never fork: spawn the
`cortex-reviewer` subagent (Agent tool, `subagent_type: cortex-reviewer`) and give it
only the change folder's path. Record `git status --porcelain -uall`,
`git rev-parse HEAD` and `git rev-parse --abbrev-ref HEAD` before spawning
it. If it (or, split, any of them) reports an external surface, also spawn
`cortex-security-reviewer` once, with the same path. Write the round, approval
or not (its `Verdict:` line, then the findings or the approval's paragraph),
to `review-findings.md` as a `## Round <n>` section, then record all three
again: the only difference from before may be `review-findings.md` in the
status, and any other (a new commit or another branch included) is a
finding. Then commit that file alone.

If the change is more than one reviewer can read in full, split it as
`cortex/harness/commands/review.md` (Preconditions) says: one
`cortex-reviewer` per part, spawned together, each given the change
folder's path and its part's file list. Write their returns into one round
as that paragraph says, adding no judgment of your own.
