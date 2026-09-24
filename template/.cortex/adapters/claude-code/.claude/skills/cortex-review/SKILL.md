---
name: cortex-review
description: Adversarially review an implemented change (cortex review), in fresh read-only subagents.
---

<!-- cortex:generated -->

Don't run the command in this session, and never fork: spawn the
`cortex-reviewer` subagent (Agent tool, `subagent_type: cortex-reviewer`) and give it
only the change folder's path. Record `git status --porcelain -uall` before
and after; any difference is a finding. If it reports an external surface,
also spawn `cortex-security-reviewer` with the same path. Write its findings
to `review-findings.md` in the change folder, as `review.md` specifies.
