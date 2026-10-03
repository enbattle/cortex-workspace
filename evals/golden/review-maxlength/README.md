# Golden task: review catches a planted maxLength defect

Checks that `harness/commands/review.md`, run by a fresh agent, blocks a
change whose tests and gates all pass but whose code breaks an acceptance
criterion. Re-run it after editing `template/harness/commands/review.md`,
the review checklist or the security review (root `AGENTS.md`), and after
editing the Claude Code reviewer adapter.

## Contents

- `fixture.bundle`: a git bundle of `slugkit`, a small Node library with
  cortex 2.0.0 installed (on a `cortex-install` branch merged into `main`,
  per `INSTALL.md`; step 5b, the CI setup, is skipped because the fixture
  isn't hosted) and one change taken through the current flow on branch
  `change/20260924-slugify-maxlength` (`spec-new`, `spec-clarify` committing
  the approved folder, `test-first` with its three commits and `lock.md`,
  `implement` with a commit per task, then verification evidence and gate
  output in `tasks.md`). Tags:
  `golden-clean` (the correct change) and `golden-planted` (one planted
  commit on top). Node 18+ and Git Bash are all it needs.
- `rubric.md`: the planted defect, its reproductions, and how to grade.
- `results/<yyyy-mm-dd>.md`: one file per run date.

The bundle supersedes the earlier `spec.md` (the approved criteria, now
`changes/20260924-slugify-maxlength/proposal.md` inside the fixture) and
`planted.diff` (now the `golden-planted` commit), which were removed. The
fixture was rebuilt from the first pilot's source and tests, in the current
format (Amendment 2's `lock.md`).

## Which template this fixture matches

The fixture was built on 2026-09-24 from the template at commit `15de2ea`,
with that commit's `scripts/install.sh` and by following its command texts;
the source, tests, proposal and planted change come from the first pilot
(`1f9e92d`). On 2026-10-02 its change folder was brought up to the current
flow (the completeness audit's L1): `tasks.md` has the template's
`## Verification` section from the spec commit on, and the commit that
records the gate output also records the implementer's run of `slugify`
from a caller's position (the proposal's examples, which hold at
`golden-clean`); the source, tests, proposal and plant are unchanged.
Otherwise only its installed copies have been refreshed. The
current tags are in the bundle, and each results file records the commits
it ran against.

The installed copies that must match their source byte for byte, at
`golden-clean`, with `golden-planted` leaving them unchanged:

- every file `install.sh` copies from `template/`, at the same path, except
  the ones filled in when the fixture was built (`.cortex/config`,
  `AGENTS.md`, `docs/**`, `changes/**`);
- `.cortex/design-rules.md` (from `docs/01-design-rules.md`) and
  `.cortex/version` (from `VERSION`);
- `.claude/**`, which `adapt.sh` copies from
  `.cortex/adapters/claude-code/.claude/`.

`tests/golden-fixture.test.sh` fails, naming each file, when one differs or
is missing, so after an edit to any of them in `template/` the suites fail
until the fixture is refreshed. Otherwise a run tests the old text.

To refresh, run `bash evals/golden/review-maxlength/refresh.sh` and commit
the new `fixture.bundle`. It rewrites the fixture's history with the
current copies and replaces the bundle only if `gates.sh` prints
`gates: ok` at both tags and the project's own files are unchanged (so the
rubric's reproductions still hold). When the template removes a file or
changes how a change is taken through the commands, rebuild the fixture
instead, following the same steps as the first build (install, the approved
change folder, test-first's three commits, the implementation, tag
`golden-clean`, add the planted commit, tag `golden-planted`).

## Procedure

Run `golden-planted` twice and `golden-clean` once, each in its own fresh
clone and by its own fresh agent.

1. **Make a fresh clone.** In Git Bash, with `<cortex>` the cortex checkout
   and `<run-dir>` a new, empty directory outside any repository:

   ```bash
   TAG=golden-planted            # or golden-clean for the control
   git clone -q <cortex>/evals/golden/review-maxlength/fixture.bundle <run-dir>/slugkit
   cd <run-dir>/slugkit
   git switch -q main
   git switch -q -C change/20260924-slugify-maxlength "$TAG"
   git tag -d golden-clean golden-planted >/dev/null
   git remote remove origin
   bash scripts/cortex/gates.sh changes/20260924-slugify-maxlength   # must end: gates: ok
   git status --porcelain -uall                                      # must be empty
   git rev-parse HEAD                                                # note it
   ```

   Deleting the tags and the remote keeps their names out of the reviewer's
   view. (The approval line and the commit author still read "golden
   fixture"; accepted.)

2. **Start a fresh agent** that has not seen this directory, the rubric, or
   any earlier run: a new session, or in Claude Code a new
   `general-purpose` subagent (never a fork: a fork inherits your context).
   Give it exactly this prompt and nothing else, with both paths filled in:

   > Read and execute harness/commands/review.md for change folder
   > changes/20260924-slugify-maxlength. The repository is
   > `<run-dir>/slugkit`; its default branch is `main`. You are read-only:
   > don't edit, create, delete, stage or commit anything in the repository,
   > and don't write review-findings.md. If you want to run probe scripts,
   > put them only under `<run-dir>/probes/`. Return your verdict and
   > findings in the format review.md specifies (for request changes, the
   > review-findings.md content) as your final message.

3. **Grade** the returned verdict against `rubric.md`. Then in the clone run
   `git status --porcelain -uall` and `git rev-parse HEAD` and compare with
   step 1.

4. **Log** to `results/<yyyy-mm-dd>.md`: the cortex commit (and whether its
   tree was dirty), the agent tool and model, then per run the tag, verdict,
   grade, the finding that named the plant (severity and a one-line quote)
   or why it failed, other findings with your judgment of each, and whether
   the clone was left clean. Note deviations from this procedure; don't
   restate it or the fixture's setup.
