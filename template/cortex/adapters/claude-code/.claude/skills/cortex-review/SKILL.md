---
name: cortex-review
description: Adversarially review an implemented change (cortex review), in fresh read-only subagents.
---

<!-- cortex:generated -->

Don't run the command in this session, and never fork: spawn the
`cortex-reviewer` subagent (Agent tool, `subagent_type: cortex-reviewer`) and give it
only the change folder's path. Record `git status --porcelain -uall` before
spawning it. If it reports an external surface, also spawn
`cortex-security-reviewer` with the same path. Write the findings to
`review-findings.md` as a `## Round <n>` section, then record the status
again: the only difference from before may be `review-findings.md`, and any
other is a finding. Then commit that file alone.
