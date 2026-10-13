---
name: cortex-retro
description: Turn friction from a finished change into approved edits and log it (cortex retro).
---

Read and execute `cortex/harness/commands/retro.md` in this session. For
step 5's independent read, don't read the edits yourself and never fork:
spawn the `cortex-edit-reader` subagent (Agent tool,
`subagent_type: cortex-edit-reader`) with only the proposed diff, the
paths of the evidence each edit cites, and the paths it edits.
