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

A runner (deleted after the completeness audit, which found its patterns already stale; it is in this file's history) broke one condition in a gate script at a time (35
mutants across `check.sh`, `_config.sh`, `tests-locked.sh`, `gates.sh`,
`ci-gates.sh` and `adapt.sh`), checks the mutant still parses, runs the
suite that should catch it, and restores the file. It ran on GitHub Actions
(run 36968369549, on a throwaway branch from `refactor/dry-yagni`, deleted
afterwards; the scripts and tests there match this branch). The unmutated
suites passed first.

**26 caught, 9 survived.** Every mutant applied and parsed. (Corrected after the completeness audit, `2026-10-02.md`: first written as 25 and 10; the table below always listed nine.)

Survivors, triaged (R13, R14). A surviving mutant means no test would notice that breakage; the scripts as committed are correct in every case below.

| Mutant | What survives | Judgment |
| --- | --- | --- |
| c7 | Widening C7's exemption to every template (so `Approved-by:` could appear in any of them) goes unnoticed. `check.sh` itself exempts only the proposal. | **Test gap on a rigid rule** (R6: only a human writes approval). Worth a planted-violation test. |
| t6 | Dropping the index comparison goes unnoticed: no test stages a weakened locked file and restores the working tree (the commit would take the weakened copy). `tests-locked.sh` itself compares both. | **Test gap on the lock** (R11). Worth a planted-violation test. |
| c2 | C2 misses one tool name (`codex`): only some names are planted | Low. A cheap test per listed name. |
| c6 | C6 accepts `Budget:` anywhere in a line | Low. |
| c9 | C9 allows a 26-line skill: the boundary isn't pinned | Low. |
| c10 | C10 accepts a weaker trust phrase | Low. |
| c12 | C12 misses `TODO` without a colon | Low. |
| p3 | The parser stops skipping comment lines | **Equivalent.** A comment line's key is `# KEY`, never equal to a key, so the skip changes nothing; it documents the format. |
| t2 | One later edit to `lock.md` allowed by the count | **Covered elsewhere.** Two lock commits break the parent check, which reports `LOCK moved`. |

**Recommendation:** planted-violation tests for c7 and t6 (a rigid rule and
the lock), written by a separate agent as for any test. The five Low
survivors are cheap one-line plants too; whether to add them is the
maintainer's call. Automating mutation testing in CI is not recommended yet:
the regex mutants are tied to the scripts' exact text and would break on
every edit; write fresh mutants against the code as it is then, after a
substantial script change, instead.

## Follow-up: check.sh with a bounded number of processes (PR 3)

Spec Amendment 7. Each check now runs one `grep` over every file it covers
(C5 one per heading), so the count no longer grows with the template: with
40 files added, every count stays the same (criterion 43). Old and new
printed byte-identical output and exit codes on a fresh install, a filled
install, every check failing at once, C2 in both directories, C5 and C6,
C9 at 25, 26 and unmarked, and with `harness/`, `docs/knowledge/` or
`harness/commands/` missing.

- `check.sh` on a filled install: 2.1 s against 7.3 s for the old script,
  run side by side on the same loaded machine (3.3 s unloaded above).
- `check.test.sh`: 54 cases (10 new) in 497 s, a mean of 9.2 s per case
  against 11.3 s: about 19% faster per case.

The suites are now dominated by the test harness itself: each assertion in
`tests/lib.sh` starts a `grep`, and each fixture runs several `git`
commands, at 50-60 ms per process here. Assertions written with bash
pattern matching instead of `grep` would be the next lever; that changes
the helpers, so assertion counts must stay the same.

Found on the way: with `harness/` or `docs/knowledge/` missing, `check.sh`
exits 1 with no output (a `set -e` stop inside `files_under`). The new
script keeps that exit code, as H1 requires; a message saying what is
missing would be a spec change of its own.
