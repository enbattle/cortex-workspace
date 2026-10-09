# Install, upgrade or remove cortex

You are an AI coding agent. The user has asked you to install cortex into the
repository you're working in (or to upgrade or remove it: see the last two
sections). Follow these steps in order. Never invent project facts: anything
the user doesn't know yet stays a visible `<!-- TODO -->`, listed for them at
the end. The one exception is `cortex/AGENTS.md`, which agents read before
any work: it must end with no `TODO` (`check.sh` C12), so write what is known
and route the unknowns to a knowledge file that keeps the `TODO`.

Everything cortex brings goes under `cortex/`. Outside it, cortex only adds
marked blocks (`<!-- cortex:begin ... -->` to `<!-- cortex:end ... -->`) to
files like `AGENTS.md` and `CLAUDE.md`, or creates files tools require, and
records each one in `cortex/footprint`, so `cortex/bin/remove.sh` can take it
all out again. **Never edit a project file outside cortex's blocks** while
installing; nothing in these steps asks you to.

## 1. Check the starting point and get cortex

- Confirm the current directory is the root of a git repository with a clean
  working tree (`git status`). If it isn't clean, ask the user to commit or
  stash first, so the install is one reviewable diff.
- Create a branch: `git switch -c cortex-install`.
- Clone cortex **outside** this repository, at the release tag the user named
  (or the latest `v*` tag), with full history: upgrades read the installed
  version from it, so don't use `--depth`.
  `git clone --branch v<version> <url> <somewhere-outside>/cortex`
  Below, `<cortex>` means that clone.

## 2. Install

Run `bash <cortex>/bin/install.sh .` and show the user its output. It creates
`cortex/`, adds a short block of always-on rules to `AGENTS.md` (creating the
file if there is none), and writes `cortex/footprint`. It refuses, changing
nothing, when something here would be overwritten: a `cortex/` directory that
isn't an install, a cortex-named file it didn't write, a 2.x install. Report
the refusal to the user; don't work around it.

## 3. Interview the user, then fill in the placeholders

Read the repository's own `AGENTS.md` (and `CLAUDE.md`, a `CONTRIBUTING`
guide) first: much of what follows may already be written there, and
cortex reads those files too, so it doesn't need a copy. Then ask, in one
batch where you can:

0. If the repository already has a development process of its own (agent
   instruction files beyond cortex's blocks, a contributing guide, an
   existing spec, test-lock or review workflow), which one governs
   nontrivial changes: cortex's commands, or the project's with cortex's
   checks alongside. Write the answer as the first line of
   `cortex/AGENTS.md`'s Conventions section. Either way, where the
   project's rules and cortex's differ, the stricter one applies.
1. One sentence on what the repository is.
2. The build, test and lint commands. Detect candidates first (`package.json`
   scripts, a `Makefile`, `pyproject.toml`, `Cargo.toml`, CI workflows) and
   ask the user to confirm them rather than asking from scratch. Suggest
   that the lint command also run what the stack offers for formatting
   (checked, not rewritten), its standard style guide, type checking, a
   complexity limit, duplicate detection and dependency-boundary rules:
   these turn items of the review checklist's "Design and simplicity"
   section into gates. They are the project's tools; add only the ones the
   user agrees to.
3. What the test runner loads (for `TEST_GLOBS`): not just how test files
   are named, but every helper, fixture and setup file it picks up. Check the
   runner's discovery rules; for example `node --test` loads more than
   `*.test.js` from a `test/` directory. When unsure, lock the whole test
   directory (`test/**`). Include the runner's own configuration too
   (`package.json` if its scripts pick the tests, `jest.config.*`,
   `pytest.ini`, and similar), or the test command can be narrowed without
   touching a test. Patterns are git pathspecs: one that doesn't start with
   `*` is anchored at the root, so write `**/test_*.py` for test files in
   any directory. `adapt.sh` notes each pattern that matches no tracked file.
4. Which agent tools the team uses (`claude`, `cursor`, `copilot`, `gemini`,
   `codex`).
5. Whether the repository is hosted on GitHub and should get the pull
   request boundary (step 5), and who must review the files no script can
   judge (`CODE_OWNERS`: a team or people).
6. The project's own non-negotiable principles, for the constitution's
   Project section (as many as it needs; the generic ones are already
   there). If they have none, propose some from the stack you've seen and
   get explicit approval for each.
7. Terms that are overloaded or confused in this codebase (glossary seeds),
   and the main components and who owns them (architecture seeds).
8. How to start the software, check it's healthy, and stop it (for
   `cortex/knowledge/verification.md`), if there is something to run. Its
   feature rows are filled in later, as changes touch each feature.
9. Conventions: the style guide the lint command enforces, and, for an
   existing codebase, which patterns shouldn't be copied and what replaces
   each. Those the root `AGENTS.md` already states stay there; write only the
   rest.

Then fill in, all under `cortex/`: `cortex/config` (`BUILD_CMD`, `TEST_CMD`,
`LINT_CMD`, `TEST_GLOBS`, `TOOLS`, and `CI=github` with `CODE_OWNERS` if
step 5 applies), the placeholders and the Conventions section of
`cortex/AGENTS.md` (keep it at 60 lines or fewer; longer conventions go in
`cortex/knowledge/conventions.md`, routed from there), the Project section of
`cortex/constitution.md` (P1, P2, ...), `cortex/knowledge/glossary.md`,
`cortex/knowledge/architecture.md` and, where known, the start, check and
stop section of `cortex/knowledge/verification.md`. Delete any entry in
`cortex/deferred-practices.md` that can never apply here, with a one-line
reason in the commit message.

Nothing under `cortex/harness/` may name an agent tool (`check.sh` C2).
Project principles go in the constitution's Project section; an upgrade keeps
your edits anywhere under `cortex/` (it merges them), and removing cortex
keeps the Project section and the conventions as records.

## 4. Generate adapters and check

```bash
bash cortex/bin/adapt.sh
bash cortex/bin/check.sh
```

`adapt.sh` writes each tool's files: a block in `CLAUDE.md` (or a new
`CLAUDE.md`), Claude Code's agents and skills under `.claude/`, and so on. If
the repository already has a `.claude/settings.json`, it never edits it: it
prints the permission rules the file lacks as `entry .claude/settings.json
<line>` lines. Merge those lines into the file's `permissions` block, each in
the list its source shows (the path is printed above them), with the user's
approval; `check.sh` (C13) fails until they're in. An agent's own
permissions may refuse an edit to its settings file; then the user merges
the lines. A root `.prettierignore` gets the same treatment: `adapt.sh`
prints `entry .prettierignore cortex/` for the user to merge, since cortex's
files follow cortex's style, not the project's.

Then run `LINT_CMD` once. If another formatter or linter flags files under
`cortex/`, add `cortex/` to its ignore file with the user's approval (that
line is the project's; removal doesn't list it). cortex's blocks in
`AGENTS.md` and `CLAUDE.md` are written in the form markdown formatters
produce, and a formatter's blank lines in them are not an edit.

Fix every `FAIL` line (each names the rule it enforces) and re-run until it
prints `check: ok`. On a fresh install it fails on purpose: C11 for each
`cortex/config` value still unset, and C12 while `cortex/AGENTS.md` has a
`TODO`.

In Claude Code, the `.claude/settings.json` cortex provides allows the routine
commands the pipeline runs (read-only `git`, `git add`, `git commit`,
`git switch`, `git checkout -b`, and `bash cortex/bin/*`, for Bash and
PowerShell) and asks before push, merge, rebase and hard reset. Add this
repository's build, test and lint commands from `cortex/config` to its
`allow` list with the user (for example `"Bash(npm test*)"`; these rules are
the project's, so cortex doesn't record them and removal leaves them), or running them
directly prompts (the gates themselves run through the allowed
`cortex/bin/gates.sh`). Add the command that runs the project too (for a Node
library, `"Bash(node *)"`), so `implement` and `review` can check a change on
the real artifact without a prompt. These `allow` rules take effect only once
each person has trusted the folder in Claude Code; a headless or unattended
run in an untrusted folder gets none of them (pass `--allowedTools`, or put
the same rules in the untracked `.claude/settings.local.json`). Because
`git commit` is allowed, a commit to the default branch doesn't prompt
either: protect the default branch on the server (step 5), since the rule
against committing there is an instruction, not a permission.

## 5. Make the pull request the boundary (hosted on GitHub)

The local gates are guardrails: an agent with git access on its own machine
can get around them. The boundary is the pull request. With `CI=github` and
`CODE_OWNERS` set, `adapt.sh` (step 4) wrote:

- `.github/workflows/cortex.yml`: on every pull request it checks out the
  branch as pushed and runs the base branch's copy of
  `cortex/bin/ci-gates.sh`, which uses the base branch's copies of every
  other checker. Add the setup steps its comment asks for (runtime,
  dependency install) to its source, `cortex/ci/github/cortex.yml`, then run
  `bash cortex/bin/adapt.sh` again: the source is cortex's file, so an
  upgrade merges your steps with cortex's changes, and removal deletes the
  workflow cleanly. (An edit to the generated workflow itself is kept by
  both, never updated, and left behind by removal.) It runs the test lock only for change
  folders whose `lock.md` the pull request adds or changes. To bring a
  locked branch up to date, merge the base into it, and if that changed
  locked files, re-lock with the user's sign-off (`test-first` step 7,
  naming the merge commit); don't rebase.
- a `codeowners` block in the repository's `CODEOWNERS` (the one GitHub
  reads: `.github/`, the root, or `docs/`): the test locks, the harness and
  its configuration, the test paths in `TEST_GLOBS`, and the workflow. In
  CODEOWNERS the last matching line wins, so for those paths the block
  replaces the project's own owners; put them in `CODE_OWNERS` too if they
  must keep approving.

Then tell the user the repository settings that make both binding (they are
not in the code): require a pull request before merging, require the
`cortex` check to pass, and require review from Code Owners. The last one is
load-bearing: on a pull request the branch supplies the workflow file and
`cortex/config` (whose commands the gates run), so a person reviewing them
is what keeps both honest. Two consequences to tell the user: GitHub doesn't
count an author's approval of their own pull request, so a sole maintainer
needs a second code owner or leaves Code Owners review off and relies on the
required check; and a Code Owners rule on a file a bot updates (Dependabot
and `package.json`, say) holds the bot's auto-merge until an owner approves.

On another host, set up the equivalent by hand: the same script in CI, and
required human review for the same paths.

## 6. Smoke test in a fresh context

Ask the user to open a **new** session (or, where the tool supports it,
spawn a fresh subagent) and give it only: *"Read and execute
`cortex/harness/commands/onboard.md`."* If the fresh context can't answer its
own two check questions from the files alone, a knowledge or routing file is
missing something: fix it now.

## 7. Hand off

Commit on the `cortex-install` branch, but don't push or merge; the user
merges it. Every change after this starts from the default branch with the
install merged. Tell the user:

- what was created, and which project files got a block;
- every settings entry still to merge, and every remaining `TODO`, by file;
- the hosting settings from step 5, if it applied;
- the recommended first step: take one small, real change through
  `spec-new` → `spec-clarify` → `test-first` → `implement` → `review` →
  `retro`, and let that run's friction decide what to adjust.

## Upgrade

When the user asks to upgrade cortex: in the clone, `git fetch --tags` and
check out the new release tag (the clone must still have the commit the
installed version came from; the install refuses with the fetch command if
not). Then, in the repository, on a new branch with a clean work tree:

```bash
bash <cortex>/bin/install.sh .
```

It merges three versions of every cortex file: the one installed, the new
one, and this repository's. Files the project didn't edit are replaced;
edits are kept; where both changed, `git merge-file` merges them, and an
overlap leaves conflict markers and a `conflict <path>` line (exit 1).
`cortex/config` is never changed: a key the new version added is printed as
`config KEY=default`, to add if wanted. It also prints each release's notes
for installed repositories. Merge any `entry .claude/settings.json` lines it
prints, as in step 4. Resolve every conflict (C14 fails until they're
gone), run `bash cortex/bin/check.sh`, show the user the diff, and commit.
To undo before committing: `git restore . && git clean -fd`; after:
`git revert` the commit.

A new major version refuses while a change is in progress (an open
`cortex/changes/*/lock.md`): finish or archive it first, and changes in
progress on other branches too.

## Remove

When the user asks to remove cortex, on a new branch with a clean work tree:

```bash
bash cortex/bin/remove.sh
```

It stops twice before changing anything, and you relay both to the user:

1. The hosting steps: remove `cortex` from the required checks, then the
   Code Owners requirement if cortex is why it is on. Deleting the workflow
   while its check is required blocks every pull request. Once the user has
   done both, re-run with `--hosting-done`.
2. Project lines that name paths under `cortex/` (a script calling
   `cortex/bin/gates.sh`, a link to `cortex/knowledge/`). Fix them with the
   user and commit, or re-run with `--references-ok`.

The records (change folders, knowledge, the constitution's Project section,
the conventions) are kept in `docs/cortex-records/` unless the user names
another directory (`--keep-records <dir>`) or chooses `--delete-records`.
Then it removes every block and created file the footprint records, keeping a
created file the project edited (`--force` deletes it anyway), lists the
settings lines to remove by hand, and deletes `cortex/`. Show the user the
diff and commit.
