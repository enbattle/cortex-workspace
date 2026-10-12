# Plan: the 3.2.0 release audit's two nominations (no release)

Status: **approved by the maintainer, 2026-10-12.** A point-in-time
record.

## Context

The 3.2.0 release audit (`evals/audits/2026-10-12-3.2.0.md`) nominated two
merges. On 2026-10-12 the maintainer asked for both. Neither changes what
an install does, so there is no CHANGELOG entry and no version bump.

## Items

- **M1. One source for the entry rule.** `_footprint.sh` gains
  `ENTRY_RULE_RE`, the pattern of an entry line's quoted rule
  (`^[[:space:]]*("[^"]*")`). `entry_rule` and `entry_present` use it,
  and `adapt.sh` calls `entry_rule` in place of its own `sed` copy.
- **M2. `fp_first`.** `_footprint.sh` gains `fp_first KIND [PATH [FIELD3]]`:
  the first record `fp_match` would print, or nothing. The six
  `fp_match ... | sed -n 1p` calls (`_footprint.sh`, `adapt.sh`,
  `bin/install.sh`) use it.
- Both are refactors: output, exit codes and every caller's behavior are
  unchanged, and the existing suites are their tests (as for the 2026-10-10
  plan's N1).
