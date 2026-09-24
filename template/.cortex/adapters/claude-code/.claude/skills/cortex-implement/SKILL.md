---
name: cortex-implement
description: Implement an approved change against its locked tests (cortex implement), in a fresh subagent.
---

<!-- cortex:generated -->

Don't run the command in this session, and never fork: spawn the
`cortex-implementer` subagent (Agent tool, `subagent_type: cortex-implementer`) and give it
only the change folder's path. When it returns, run `scripts/cortex/tests-locked.sh <change-folder>`,
the build/test/lint commands from `AGENTS.md`, and `scripts/cortex/check.sh`
yourself; a failure goes back to the user, not to a retry.
