# Plan: the audits' open nominations (no release)

Status: **approved by the maintainer, 2026-10-10.** A point-in-time
record.

## Context

These items are still open:
- the 3.1.0 audit's two nominations (`evals/audits/2026-10-10.md`);
- the 3.0.0 audit's two test-merge nominations (`evals/audits/2026-10-08.md`);
- one fixture gap from the golden cycle (`results/2026-10-10.md`).

On 2026-10-10 the maintainer asked for all of them. None changes what an
install does, so there is no CHANGELOG entry and no version bump.

## Items

- **N1. One helper for "the recorded entry is present."**
  - What it is: `_footprint.sh` gains
    `entry_present PATH RULE-FIELD TEXT`. TEXT is a file's whole content,
    or one line of it.
  - What it decides: for `.prettierignore`, whether TEXT has a
    `PRETTIERIGNORE_LINE`. For any other path, whether TEXT contains the
    field's quoted rule. A field without one is never present.
  - Callers: C13 (`check.sh`) and `remove.sh` step 2 use it in place of
    their own copies of that logic.
  - A refactor: behavior doesn't change, and the existing suites are its
    tests.
- **N2.** Remove the global `placeholder_kept=0` from `bin/install.sh`.
  `merge3` and the root block's merge each set it before anything reads it.
- **N3.** `check.test.sh` has five cases (`case_C1*`) for the retired C1.
  They become one case for 3.0.0's criterion 34 ("C1 is retired"), which
  covers the same inputs:
  - a harness file naming the project;
  - a leftover `PROJECT_NAME`;
  - an empty `PROJECT_NAME`;
  - the whole-word variants (AC18).
  - It asserts no `[C1]` line for any of them. Assertion counts drop, and
    the commit says by how much.
- **N4.** `install.test.sh`: `case_2x_same_version_refused` is merged into
  `case_2x_install_refused`. Both test install step 0's refusal of a 2.x
  install. The merged case keeps both inputs (another version, the same
  version), and the commit gives the count change.
- **N5. The fixture's recorded gate output follows the gate list.**
  - When `refresh.sh` rewrites a commit whose `tasks.md` has a
    `## Gate output` block that ends `gates: ok`, it rewrites that block's
    `gate <name>: ok` lines to the gates `cortex/bin/gates.sh` runs, in
    its order.
  - It reads that list from `template/cortex/bin/gates.sh`: its `gate`
    and `config_gate` calls.
  - Criterion: at `golden-clean`, the block equals the output of
    `bash cortex/bin/gates.sh <folder>` run there, line for line. It is
    checked in `tests/golden-fixture.test.sh`, a test written by a
    separate agent before the change.
  - The refreshed fixture then passes that test.

## Order

1. The approved spec.
2. Tests for N5, plus N3 and N4 (test edits), by a separate agent.
3. N1, N2 and N5's `refresh.sh`, then the fixture refreshed.
4. The full suites, one pull request, and a merge on green CI.
