# cortex

An installable harness for AI-assisted software engineering in a single
repository (one package or a monorepo): spec-first changes, tests written by
a separate agent before any implementation and then locked, isolated
adversarial review, and a feedback loop that changes the process only on
evidence. It is plain markdown and a few bash scripts, works with any agent
tool, and ships a Claude Code adapter that enforces as much of the isolation
as the tool allows.

**Status:** 3.0.0, released 2026-10-09: everything cortex installs lives in
one `cortex/` directory, and installs upgrade and remove cleanly (see
[CHANGELOG.md](CHANGELOG.md)). Its release candidate was installed, used for
one real change, upgraded and removed in a real repository first
([the pilot](evals/pilots/2026-10-09-rc-pilot-til.md)). The scripts are covered by test suites
written by a separate agent before the scripts were (`tests/`, 9 suites). The
whole pipeline has run end to end
three times on toy repositories, and once in a real one (the pilot
above). In
[pilot 1](evals/pilots/2026-09-23-toy-repo.md), review caught a real
compatibility break, and a fresh reviewer caught a planted bug the tests
missed. [Pilot 2](evals/pilots/2026-09-24-pilot-2.md) then ran the Claude
Code adapter for real from inside an installed repository: each role was
delegated to its own subagent, the three-commit test lock held, and review
again caught a real compatibility break. The rebuilt golden task
([evals/golden/](evals/golden/review-maxlength/)) passes.
[Pilots 3](evals/pilots/2026-10-03-pilot-3.md) and
[3b](evals/pilots/2026-10-03-pilot-3b.md) counted the permission prompts a
person would see, which fell to 5 in 129 actions after their fixes. cortex
has not yet been used on a real project; treat the first real change as part
of the evaluation.

## What you get

Installed into your repository, all in one directory:

```
cortex/
  AGENTS.md                    a 60-line router, with the project's conventions
  constitution.md              non-negotiables: cortex's, and the project's under ## Project
  config                       build, test and lint commands, test globs, tools, CI
  knowledge/                   index, glossary, architecture, verification recipe, decisions/
  changes/                     one folder per change, and the pipeline log
  harness/                     commands (spec-new ... retro, onboard), policies, templates
  bin/                         check, gates, tests-locked, ci-gates, adapt, remove
  adapters/  ci/               sources for the tool files and the GitHub workflow
  design-rules.md  deferred-practices.md  version  footprint
```

Outside `cortex/`, only what tools require: a short block of always-on rules
in your `AGENTS.md`, a block in `CLAUDE.md` and the other tool files, Claude
Code's agents and skills, and (with `CI=github`) a workflow and a
`CODEOWNERS` block. Every one is recorded in `cortex/footprint`; nothing of
yours is moved or rewritten.

The workflow for a nontrivial change:

| Command | Who runs it | Produces |
| --- | --- | --- |
| `spec-new` | you + the agent | a change folder with a drafted proposal |
| `spec-clarify` | you + the agent | an interrogated proposal, design, tasks, and a brief from a fresh agent; **you** approve |
| `test-first` | a fresh agent | failing tests, committed and locked |
| `implement` | another fresh agent | the change, with the locked tests untouched (checked by script) |
| `review` | another fresh, read-only agent | a verdict with findings; a separate security pass for new external surfaces |
| `retro` | you + the agent | approved process fixes and a pipeline-log row |

In any agent tool: *"Read and execute `cortex/harness/commands/<name>.md`."*
In Claude Code, the adapter adds `/cortex-<name>` skills that delegate the
three role-separated commands to subagents.

## Install, upgrade, remove

Prerequisites: git and bash (Git Bash on Windows; macOS's bash 3.2 is fine).

Ask your agent, in your repository:

> Install cortex v3.0.0 from https://github.com/enbattle/cortex-workspace by following its INSTALL.md.

It works on a branch, runs the installer, interviews you for the commands,
tools and conventions, and runs the checks. Everything it can't know is left
as a visible `TODO`. Later:

> Upgrade cortex to v3.1.0 by following its INSTALL.md.

> Remove cortex from this repository.

Without an agent, from a clone made outside your repository (full history,
so upgrades can read the installed version):

```bash
git clone --branch v3.0.0 https://github.com/enbattle/cortex-workspace.git ../cortex
bash ../cortex/bin/install.sh .     # install, or upgrade an older 3.x
bash cortex/bin/remove.sh           # remove: it stops for the hosting steps first
```

An upgrade keeps your edits to cortex's files by a three-way merge, and
leaves conflict markers where you and the new version changed the same
lines. Removal keeps your records (change folders, knowledge, project rules,
conventions) in `docs/cortex-records/` unless you say otherwise. See
[INSTALL.md](INSTALL.md).

## Reading order

| Document | For | When |
| --- | --- | --- |
| [docs/01-design-rules.md](docs/01-design-rules.md) | anyone | first: the normative design rules |
| [docs/02-extensions.md](docs/02-extensions.md) | maintainers | before adding anything: what's deferred, and each one's trigger |
| [docs/03-mental-traps.md](docs/03-mental-traps.md) | humans deciding structure | never loaded by agents during routine work |
| [docs/04-operator-feedback-loop.md](docs/04-operator-feedback-loop.md) | the person running it | re-read at each retro |
| [evals/](evals/) | maintainers | pilot reports, and golden tasks to re-run after editing a command |

## Supported agent tools

Set `TOOLS` in `cortex/config`, then run `bash cortex/bin/adapt.sh`.

| Tool | Generated | Isolation for test-first / implement / review |
| --- | --- | --- |
| Claude Code | a block in `CLAUDE.md` (`@AGENTS.md`), `.claude/skills/cortex-*`, `.claude/agents/cortex-*`, `.claude/settings.json` if absent (otherwise the rules to merge are listed) | separate subagents (enforced); reviewers have no Edit/Write tools, but have Bash, so the real check is the before/after `git status` the skill runs |
| Cursor | `.cursor/rules/cortex.mdc` | by instruction: start a new chat for each role |
| GitHub Copilot | a block in `.github/copilot-instructions.md` | by instruction |
| Gemini CLI | a block in `GEMINI.md` | by instruction |
| Codex CLI | nothing (reads `AGENTS.md`) | by instruction |

## Limits

Deliberate trade-offs; each links to where it's explained.

- **Not yet used on a real project.** It has run end to end on toy
  repositories ([pilots](evals/pilots/)); treat your first real change as
  part of the evaluation.
- **No migration from 2.x.** 3.0.0 installs fresh; a 2.x install is
  refused ([the 3.0.0 spec](docs/specs/2026-10-05-v3-removable-layout.md),
  Non-goals). Upgrades within 3.x merge your edits.
- **Every nontrivial change runs the full pipeline:** six stages, four of
  them in fresh agents; pilot 3's change cost about $6 in agent runs. There
  is no lighter tier for small fixes yet ([process weight scaled to
  stakes](docs/02-extensions.md)).
- **The test lock freezes every matching test and fixture** (and
  `cortex/config`) while a change is in progress, so an implementer can't
  weaken old tests. Changing one means re-running `test-first` with your
  sign-off, and so does merging a `main` that changed locked files; a
  locked branch merges `main` in rather than rebasing, and can't take in a
  change to `cortex/config` at all (start over from the new `main`)
  ([`test-first`](template/cortex/harness/commands/test-first.md),
  [rebasing](docs/02-extensions.md)). Merge, don't squash, a locked change
  that other branches build on: after a squash, CI sees the re-locks it
  dropped as dropped locks on those branches
  ([spec Amendment 12, N3](docs/specs/2026-09-23-v2-scripts.md)).
- **Local checks are guardrails, not a boundary.** An agent with full git
  access can get around them; the boundary is CI on the pull request plus
  required human review ([R11](docs/01-design-rules.md),
  [INSTALL.md step 5](INSTALL.md)). CI judges history as pushed: a branch
  rebuilt so that weaker tests carry the first lock needs no sign-off, and
  only the reviewer, who sees those tests in the diff, catches it
  ([spec Amendment 12](docs/specs/2026-09-23-v2-scripts.md)).
- **Enforced isolation only in Claude Code.** In other tools, starting a
  fresh chat per role is up to you ([supported tools](#supported-agent-tools)).
- **One repository.** Systems spread over several repositories are a
  deferred extension ([§7](docs/02-extensions.md)).
- **The CI template is GitHub-only.** Other hosts need the equivalent set up
  by hand ([INSTALL.md step 5](INSTALL.md)).

## Developing cortex

See [AGENTS.md](AGENTS.md). `bash tests/run.sh` runs every suite; CI runs
them plus shellcheck on every pull request and every push to `main`.

## License

MIT
