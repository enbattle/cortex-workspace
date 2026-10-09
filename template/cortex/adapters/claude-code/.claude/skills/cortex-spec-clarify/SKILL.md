---
name: cortex-spec-clarify
description: Interrogate a drafted proposal and plan its design and tasks (cortex spec-clarify).
---

Read and execute `cortex/harness/commands/spec-clarify.md` in this session. For
step 6, don't write the brief yourself and never fork: spawn the
`cortex-spec-briefer` subagent (Agent tool, `subagent_type: cortex-spec-briefer`)
with only the change folder's path, write its brief to `brief.md` in the
folder, and show it to the user.
