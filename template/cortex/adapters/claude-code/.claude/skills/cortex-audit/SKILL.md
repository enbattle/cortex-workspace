---
name: cortex-audit
description: Audit docs, recurring friction and deletions across changes (cortex audit), with fresh read-only readers.
---

Read and execute `cortex/harness/commands/audit.md` in this session, but
don't do its reads yourself, and never fork: for step 2 spawn the
`cortex-reader` subagent (Agent tool, `subagent_type: cortex-reader`) with
the step's file list and its instruction; when step 3 is due, spawn a
second `cortex-reader` with step 3's files and instruction, in the same
message so they run together. For step 4's edit read, spawn
`cortex-reader` as the `cortex-retro` skill does. Show the user what they
return as returned.
