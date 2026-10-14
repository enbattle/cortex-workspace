---
name: cortex-retro
description: Turn friction from a finished change into approved edits and log it (cortex retro).
---

Read and execute `cortex/harness/commands/retro.md` in this session. For
step 5's independent read, don't read the edits yourself and never fork:
spawn the `cortex-reader` subagent (Agent tool,
`subagent_type: cortex-reader`) with step 5's instruction (point it at
`cortex/harness/commands/retro.md` step 5), the proposed diff, and the
paths of the evidence each edit cites and of the files it edits.
