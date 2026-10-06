# Verification recipe

How to run this repository's software the way a user would, so that
`implement` checks a change on the real thing and `review` repeats the same
steps independently (the review checklist's "Verification on the real
artifact"). Fill in a feature's row when a change first touches it; nobody
has to map everything up front. When a step stops working, fix it in the
change that noticed.

## Start, check, stop

<!-- TODO: the exact commands, run from the repository root.
- Start: how to build and launch it, and anything it needs first (a seeded
  database, environment variables named without their values).
- Healthy: what to run or look at to know it started correctly.
- Stop and clean up: how to shut it down and remove what a run left behind.
For a library, "start" is a short script that imports it the way a caller
does; say where such scripts go (outside the repository, or a scratch
directory the repository ignores). -->

## Features

<!-- TODO: one row per feature, added as changes touch them. -->

| Feature | How a user reaches it | How to drive it here | What proves it worked |
| --- | --- | --- | --- |
| | | | |

## Evidence

<!-- What to paste into a change's tasks.md: the command and its output, the
request and the response, or the observed state. Never secrets or personal
data. -->
