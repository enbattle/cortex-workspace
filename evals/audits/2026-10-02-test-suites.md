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

## What the suites would not catch (item 25)

`2026-10-02-mutate.sh` breaks one condition in a gate script at a time (35
mutants across `check.sh`, `_config.sh`, `tests-locked.sh`, `gates.sh`,
`ci-gates.sh` and `adapt.sh`), checks the mutant still parses, runs the
suite that should catch it, and restores the file. It ran on GitHub Actions
(run 36968369549, on a throwaway branch from `refactor/dry-yagni`, deleted
afterwards; the scripts and tests there match this branch). The unmutated
suites passed first.

**25 caught, 10 survived.** Every mutant applied and parsed.

Survivors, triaged (R13, R14):

| Mutant | What survives | Judgment |
| --- | --- | --- |
| c7 | C7 exempts every template, so `Approved-by:` could appear in any of them | **Real gap in a rigid rule** (R6: only a human writes approval). Worth a planted-violation test. |
| t6 | A staged edit to a locked file, with the working tree restored, passes: the commit takes the weakened index copy, the check compares the working tree | **Real gap in the local guardrail.** CI's fresh checkout catches it (R11's boundary). Worth a planted-violation test. |
| c2 | C2 misses one tool name (`codex`): only some names are planted | Low. A cheap test per listed name. |
| c6 | C6 accepts `Budget:` anywhere in a line | Low. |
| c9 | C9 allows a 26-line skill: the boundary isn't pinned | Low. |
| c10 | C10 accepts a weaker trust phrase | Low. |
| c12 | C12 misses `TODO` without a colon | Low. |
| p3 | The parser stops skipping comment lines | **Equivalent.** A comment line's key is `# KEY`, never equal to a key, so the skip changes nothing; it documents the format. |
| t2 | One later edit to `lock.md` allowed by the count | **Covered elsewhere.** Two lock commits break the parent check, which reports `LOCK moved`. |

**Recommendation:** planted-violation tests for c7 and t6 (a rigid rule and
a lock bypass), written by a separate agent as for any test. The five Low
survivors are cheap one-line plants too; whether to add them is the
maintainer's call. Automating mutation testing in CI is not recommended yet:
the regex mutants are tied to the scripts' exact text and would break on
every edit; re-run this file's audit after a substantial script change
instead.
