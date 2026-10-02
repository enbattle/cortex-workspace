# Test-suite audit, 2026-10-02

Plan items 26 and 25 (`docs/specs/2026-10-01-quality-plan.md`), at cortex
`2b0d55a`, on Windows 11 with Git Bash (16 logical processors, 15.6 GB of
memory, 3.1 GB free at the time).

## Where the time goes (item 26)

A suite takes about 10 minutes here and about 5 seconds in CI on Linux (all
seven took 34 s). Two full local runs were stopped by the machine running low
on memory.

- **Process start-up is the cost.** Measured here: an external program
  48 ms, `git` 64 ms, a `$(...)` subshell 22 ms, against about 1 ms on Linux.
- **`check.sh` dominates.** One run on a filled install takes 3.3 s and
  starts about 120 external commands, because C1, C2, C4 and C7 run one
  `grep` per harness file. Copying an installed repository (`fresh_install`)
  takes 0.3 s.
- **`check.test.sh`:** 44 cases, 498 s, a mean of 11.3 s and a range of
  about 11-18 s per case. No single case stands out; each runs `check.sh`
  one or more times, plus git commits.

Memory was not measured per process (Git Bash has no reliable tool for it).
The suites are small bash processes; the memory stops happened while agent
subagents were also running.

**Recommended fix:** make `check.sh` start a bounded number of processes,
for example one `grep -l` over all harness files per check instead of one
`grep` per file, as spec Amendment 5 did for `install.sh`. Behavior must not
change, so it goes through a spec amendment and tests from a separate agent
(including a process-count criterion like Amendment 5's). Expected effect:
`check.sh` from about 3.3 s to well under 1 s here, which also speeds up the
`gates`, `ci-gates` and `check` suites that run it.
