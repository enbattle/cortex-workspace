---
name: cortex-test-first
description: Write and lock failing tests for an approved change (cortex test-first), in a fresh subagent.
---

Don't run the command in this session, and never fork: spawn the
`cortex-test-writer` subagent (Agent tool, `subagent_type: cortex-test-writer`) and give it
only the change folder's path. When it returns, run `bash cortex/bin/tests-locked.sh <change-folder>`
yourself, as a command of its own (not chained), and confirm the new tests fail; don't trust its report.
On a re-lock it stops with `lock.md` written but uncommitted: get the user's
sign-off on it (design rule R6), commit `lock.md` alone, update
`## Criteria to tests` in `tasks.md`, then run the check.
