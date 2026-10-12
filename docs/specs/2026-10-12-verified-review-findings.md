# Plan: the 2026-10-12 review's verified findings (3.2.0)

Status: **approved by the maintainer, 2026-10-12.** A point-in-time
record: the completeness audit maps every item below to evidence.

## Context

On 2026-10-12 a review of the repository, split across four fresh
reviewers by area, reported about thirty findings. A second round of four
fresh verifiers, each given cortex's design rules, mental traps, extensions
catalog, the relevant specs and audits, re-checked every finding a fix was
proposed for, tried to refute it, and reproduced the ones that could be
reproduced. What survived is below, triaged by R13: a finding becomes work
when it is confirmed and either above the bar or a cheap test for a severe
class (data loss, the test lock); the rest is recorded as a known
limitation, with the reason.

Each script change gets tests from a separate agent, committed before the
script changes (root `AGENTS.md`).

## Items

### V1. An unclosed block is refused, not truncated (data loss)

Reproduced: with a cortex begin marker and no end marker after it,
`block_set` (`_footprint.sh`) drops every line after the begin marker, and
`adapt.sh` (`emit_block`) and an upgrade (the root agents block) reach it.
R15 and the 3.0.0 spec's "Marked blocks" say content outside the markers is
never read or written.

- `_footprint.sh` gains `block_closed PATH ID`: true when the file's first
  begin marker for ID has an end marker for ID after it (line endings as in
  `block_set`: a trailing CR is ignored).
- `adapt.sh` checks every recorded block (and every file it would write a
  block into that has a begin marker) before writing anything, alongside
  its D11 refusals, and refuses with exit 2:
  `refused <path>: its cortex <id> block has no end marker; restore it, then run again`.
  Nothing is written, the footprint included.
- An upgrade (`bin/install.sh`) makes the same check before any file is
  merged, with the same message and exit 2, changing nothing.
- `remove.sh` makes the same check with its other refusals, before step 1,
  changing nothing.
- `block_set` and `block_strip` leave the file unchanged and return 1 when
  the end marker is missing, and `fp_remove_block` then neither prints
  `removed block` nor drops the record (defense in depth).
- C13 (`check.sh`) fails a recorded block whose begin marker has no end
  marker: `FAIL [C13] <path>: cortex <id> block has no end marker`.
- Markers with either comment style (`<!-- -->` and `#`) and CRLF files are
  covered.

### V2. An unknown `CI` value removes nothing

Reproduced: `CI=GitHub` prints "nothing written for it" and then removes the
recorded workflow and CODEOWNERS block, the pull request boundary.

- `adapt.sh`'s removal pass skips `ci`-owned records unless `CI` is
  `github` or `none`. The warning stays. `CI=none` still removes them (on
  purpose, as today).

### V3. Records can't be kept inside `cortex/` by any spelling

Reproduced: `remove.sh --keep-records ./cortex/x` moves the records into
`cortex/` and then deletes `cortex/`. The guard matches only the literal
`cortex` and `cortex/*`. D6: deleting records takes an explicit choice.

- The guard takes the records path's deepest existing ancestor (the path
  itself, if it exists), resolves it physically (`cd` into it, `pwd -P`),
  and walks that physical path up to the root, refusing when any directory
  on it is the same file as `cortex` (`[ "$d" -ef cortex ]`), with the
  current message and exit 2, changing nothing. This catches `./cortex/x`,
  `cortex/./x`, an absolute path, a symlink to `cortex/` or to a directory
  inside it (`lnk -> cortex/changes`, then `lnk/x`), and `Cortex/x` on a
  case-insensitive file system.
- `docs/cortex`, `cortexrecords` and `docs/cortex-records` are still
  accepted.

### V4. The test lock is judged before any project code runs

Reproduced: in the workflow's single gates step, a process started by
`TEST_CMD` after `gate tests-locked: FAIL` overwrote the rest of the running
base-branch `gates.sh` and the step exited 0. Implementation code is not
locked and needs no code owner's approval, so this defeats the lock that
R11 makes CI the boundary for. A setup step placed before the gates
(`npm ci` and its lifecycle scripts) can do the same through
`$GITHUB_ENV` or `$GITHUB_PATH`. A step's result is fixed when it ends, so
the fix is ordering.

- `gates.sh` honors `CORTEX_GATES_LOCK_ONLY=1`: it runs `tests-locked`,
  `tasks` and `check`, and prints `gate build: skipped (lock only)` (and the
  same for `test` and `lint`) without running them, each line where that
  gate's line is today, so the order is unchanged. Its exit code and final
  line are as today. Unset, its output is unchanged.
- `template/cortex/ci/github/cortex.yml`:
  - the checkout sets `persist-credentials: false`;
  - a first step, "Test lock, before any project code runs", directly after
    checkout, extracts the base's `ci-gates.sh` as today and runs it with
    `CORTEX_GATES_LOCK_ONLY=1`;
  - the setup comment moves after that step;
  - the last step runs the full gates as today;
  - `on: pull_request` lists `types: [opened, synchronize, reopened, edited]`,
    so changing a pull request's base re-runs the check against the new
    base's scripts (V5). No job-level `if` filters `edited`: a skipped job
    would report success.
- Compatibility: an upgrade pull request runs the new workflow with the
  base's older scripts, which ignore the variable; the lock-only step then
  runs project commands only for change folders whose `lock.md` the pull
  request adds or changes, which an upgrade pull request has none of. Test
  locks and `cortex/config` are unchanged (3.0.0 D12).
- Known limit, unchanged: the branch supplies the workflow file, protected
  by Code Owners review (R11's Limit).

### V5. Retargeting a pull request re-runs the check

Folded into V4's `types` line. Without it, a pull request opened against a
branch whose `cortex/bin` passes everything (or one without cortex, which
takes the branch-copy fallback) keeps its green check when its base is
changed to the default branch. To confirm once on a scratch repository and
record in the 3.2.0 release audit.

### V6. CODEOWNERS covers what TEST_GLOBS locks

Verified: `TEST_GLOBS` entries are git pathspecs, where `*` also matches
`/`; they are copied verbatim into CODEOWNERS, where `*` stays within one
directory. So `tests/*` locks `tests/unit/a.py`, and no code owner has to
review it.

For each entry, `adapt.sh` writes into the CODEOWNERS block:
- an entry starting with `:` (pathspec magic): nothing, and prints
  `note: TEST_GLOBS entry <g> can't be written to CODEOWNERS; add its paths by hand`;
- an entry with exactly one lone `*` (one not next to another `*`), unless
  the entry has no `/` and starts with that `*`: the entry, then the entry
  with that `*` replaced by `*/**/*` (`tests/*` gives `tests/*` and
  `tests/*/**/*`; `src/*.test.ts` gives `src/*.test.ts` and
  `src/*/**/*.test.ts`; `test_*.py` gives `test_*.py` and
  `test_*/**/*.py`; `**/test_*.py` gives `**/test_*.py` and
  `**/test_*/**/*.py`, since a plain pathspec's `**` is two `*`s), which
  together match what the pathspec matches;
- an entry with two or more lone `*`: the entry, and prints
  `note: TEST_GLOBS entry <g>: CODEOWNERS may not own every file it locks; write it with **`;
- any other entry (`*.test.js`, `tests/**`): as today.

INSTALL step 3 says `**` forms are what both the lock and CODEOWNERS read
the same way.

### V7. CODEOWNERS covers the agent definitions

`template/cortex/ci/github/CODEOWNERS` gains `/CLAUDE.md`,
`/.claude/agents/cortex-*`, `/.claude/skills/cortex-*/` and
`/cortex/adapters/`: the files that define the reviewer's isolation and
tools, which R14 makes rigid, and their source. `/AGENTS.md` is already
owned whole; `CLAUDE.md` carries cortex's block the same way. Package
`AGENTS.md` files stay the project's (R3).

### V8. A forced or discarding branch switch asks first

`settings.json` allows `git switch *`, which also matches
`git switch -f` / `--force` / `--discard-changes`: these discard
uncommitted work with no recovery, which `permissions.md` says needs the
user's go-ahead. The pipeline uses only `git switch -c` and a plain
`git switch <branch>`, so the rules add no prompts to it.

- `ask` gains, for Bash and PowerShell: `git switch *--discard-changes*`,
  `git switch *--force*`, `git switch -f*`, `git switch * -f*`.
- `-C` (reset a branch) is not added: whether the tool's rule matching is
  case-sensitive is unverified, and a case-insensitive `-C` rule would also
  match the pipeline's `-c`. Recorded as a known limit.
- `git commit --amend` is not added: an unpushed amend is recoverable from
  the reflog, force-push is denied, and the test lock detects a rewritten
  lock commit.
- `docs/02-extensions.md` §6 and INSTALL step 4 name the new rules.

### V9. Review's integrity check sees commits and branch switches

`review.md` steps 1 and 9 and the review skill record
`git status --porcelain -uall` only. A reviewer that commits, amends or
switches branch leaves it unchanged (`git commit *` is allowed). They also
record `git rev-parse HEAD` and `git rev-parse --abbrev-ref HEAD` (both
already allowed): any difference, other than the skill's own commit of
`review-findings.md` afterwards, is a finding. Ignored files are not added:
the gates legitimately write build output. This edits `review.md`, so the
golden task runs twice with fresh reviewers, and the reviewer-tools probe
is re-run for the skill.

### V10. `HUMAN-GATE:` is removed from `permissions.md`

Nothing in the template uses the marker; it belongs to the runbooks
extension (`docs/02-extensions.md` §1), which defines it when built. The
sentence becomes "Any step that would do one of these stops for the user's
go-ahead."

### V11. This repository's own checks

- **macOS runs every suite.** R7 promises bash 3.2 for every script, and
  the macOS job (about 2 minutes) found a 2.x bash-3.2 bug in `ci-gates.sh`
  only because the upgrade suite happens to call it (e4cbe41). The job runs
  `bash tests/run.sh --parallel`. Windows keeps its three suites (its run
  is 11-18 minutes). This supersedes the 3.0.0 spec's D15 sentence on
  which suites the macOS job runs.
- **A suite with no assertions fails.** `summary` (`tests/lib.sh`) passes
  when nothing passed and nothing failed. It fails when no assertion ran,
  with a planted case: a suite that runs no case exits nonzero. Every
  suite's assertion count is unchanged.
- **Dependabot keeps the action pins current.** `.github/dependabot.yml`,
  the `github-actions` ecosystem, monthly, as the shipped workflow tells
  users to do. The template's checkout pin is kept equal to `ci.yml`'s by
  hand. Both move to `actions/checkout` v7.0.1 now: v4.4.0 runs on Node
  20, which GitHub has deprecated (a warning on every run), and v7's one
  breaking change is for `pull_request_target`, which neither workflow
  uses.
- **shellcheck checks quoting in the shipped scripts.** CI runs
  `--severity=info` on `bin/*.sh` and `template/cortex/bin/*.sh` (the tests
  stay at `warning`). Each finding is fixed or annotated with its reason.
  *Measured on the first run:* no SC2086; nine SC2015 (`A && B || continue`
  or `|| true`, each on purpose) and one SC2094 (a call that reads only the
  file's name), both excluded by code with that reason in `ci.yml`.

## Known limitations recorded, not fixed

- An unknown `TOOLS` name removes the files of a tool no longer named. The
  v2 spec says an unknown tool is ignored, and the files are generated and
  come back on the next run with the right name.
- A fresh install interrupted after `cortex/version` is written re-runs as
  "unchanged"; `check.sh` reports the missing footprint and block, and
  removing `cortex/` and reinstalling fixes it. The order is the one the
  3.0.0 spec prescribes.
- A fresh install's `adapt.sh` can't fail in practice: the fresh config has
  no tools and `CI=none`.
- Review reads its instructions (constitution, checklist, `AGENTS.md`) from
  the branch under review. R4 defines them as the repository's files, the
  diff shows any edit, and Code Owners covers them; reading the base's
  copies would block a change that legitimately edits the checklist.
- `git switch -C` and `git commit --amend` run without a prompt (V8).
- The suites read the developer's global git configuration; CI's is empty.
  Revisit with the "Faster test helpers" entry, the next change to
  `tests/lib.sh` that isn't this one.
- `.shellcheckrc` disables SC2034 for every script, because sourced helpers
  set variables their callers read.
- The repository settings (a pull request rule on `main`, and pinning the
  `macos` and `windows` checks to GitHub Actions) are the maintainer's, not
  code.

## Release

Users see new refusals, a new C13 failure, new permission rules and a
changed workflow: a `CHANGELOG.md` entry, 3.2.0. Nothing breaks a command's
contract, a template field or a required file, so it is a minor version.
Installed repositories: move any setup steps in `cortex/ci/github/cortex.yml`
below the new lock step after upgrading, merge any `entry
.claude/settings.json` lines `adapt.sh` prints, and re-run `adapt.sh` for
the new CODEOWNERS lines.

## Order

1. This spec, approved.
2. Tests for V1-V4, V6-V8 and V11's `summary`, by a separate agent that
   hasn't seen any implementation, committed, and shown failing on CI.
3. The changes, the golden fixture refreshed (`refresh.sh`), and the docs.
4. The golden task twice with fresh reviewers, and the reviewer-tools
   probe (V9).
5. The full suites and shellcheck on CI; the completeness audit in
   `evals/audits/2026-10-12.md`.
6. One pull request; merged on green CI with the maintainer's go-ahead.
