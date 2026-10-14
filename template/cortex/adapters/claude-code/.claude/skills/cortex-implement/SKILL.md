---
name: cortex-implement
description: Implement an approved change against its locked tests (cortex implement), in a fresh subagent.
---

Don't run the command in this session, and never fork: spawn the
`cortex-implementer` subagent (Agent tool, `subagent_type: cortex-implementer`) and give it
only the change folder's path. If it stopped for the user's ruling on a
disputed finding, get the ruling, record and commit it as
`cortex/harness/commands/implement.md` step 1 says, and spawn a fresh
implementer for any work left. When it returns, run `bash cortex/bin/gates.sh <change-folder>` yourself, as a
command of its own (not chained);
a failure goes back to the user, not to a retry.
