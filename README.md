# cortex

An installable harness for AI-assisted software engineering in a single
repository (one package or a monorepo): spec-first changes, tests written by
a separate agent before any implementation and then locked, isolated
adversarial review, and a feedback loop that changes the process only on
evidence. It is plain markdown and a few bash scripts, works with any agent
tool, and ships a Claude Code adapter that enforces as much of the isolation
as the tool allows.

**Status:** 2.2.0, released 2026-10-06 (see [CHANGELOG.md](CHANGELOG.md)). The
scripts are covered by test suites written by a separate agent before the
scripts were (`tests/`, 7 suites). The whole pipeline has run end to end
three times, on toy repositories. In
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

Installed into your repository:

```
AGENTS.md                      a 60-line router every agent reads first
harness/commands/              spec-new, spec-clarify, test-first, implement, review, retro, onboard
harness/policies/              review checklist, security review, permissions
harness/templates/             change folder (proposal, design, tasks, lock), ADR
docs/constitution.md           the project's non-negotiables (project-owned; upgrades never touch it)
docs/knowledge/                index, glossary, architecture, verification recipe, decisions/
docs/deferred-practices.md     practices considered and deferred, with triggers
changes/pipeline-log.md        one row per change: gates, findings, retro, escaped defects
scripts/cortex/                check.sh, tests-locked.sh, gates.sh, ci-gates.sh, adapt.sh, _config.sh (their parser)
.cortex/                       config, version, design rules, adapter sources, CI and CODEOWNERS templates
```

The workflow for a nontrivial change:

| Command | Who runs it | Produces |
| --- | --- | --- |
| `spec-new` | you + the agent | a change folder with a drafted proposal |
| `spec-clarify` | you + the agent | an interrogated proposal, design, tasks, and a brief from a fresh agent; **you** approve |
| `test-first` | a fresh agent | failing tests, committed and locked |
| `implement` | another fresh agent | the change, with the locked tests untouched (checked by script) |
| `review` | another fresh, read-only agent | a verdict with findings; a separate security pass for new external surfaces |
| `retro` | you + the agent | approved process fixes and a pipeline-log row |

In any agent tool: *"Read and execute `harness/commands/<name>.md`."* In
Claude Code, the adapter adds `/cortex-<name>` skills that delegate the three
role-separated commands to subagents.

## Install

Prerequisites: git and bash (Git Bash on Windows).

```bash
git clone https://github.com/enbattle/cortex-workspace.git
git -C cortex-workspace checkout v2.2.0   # install from the release tag, not main
```

Then open your repository in your agent tool and say: *"Read and execute
`<path to cortex>/INSTALL.md`"*. It checks for a clean tree, creates a
`cortex-install` branch, runs `scripts/install.sh` (which copies files only
where none exist, so it is safe on an existing repository), and fills in
`.cortex/config`, `AGENTS.md`, the constitution and the knowledge stubs with
you, merges any existing `AGENTS.md` or `CLAUDE.md`, and runs the adapters
and checks. Everything it can't know is left as a visible `TODO`.

## Reading order

| Document | For | When |
| --- | --- | --- |
| [docs/01-design-rules.md](docs/01-design-rules.md) | anyone | first: the normative design rules |
| [docs/02-extensions.md](docs/02-extensions.md) | maintainers | before adding anything: what's deferred, and each one's trigger |
| [docs/03-mental-traps.md](docs/03-mental-traps.md) | humans deciding structure | never loaded by agents during routine work |
| [docs/04-operator-feedback-loop.md](docs/04-operator-feedback-loop.md) | the person running it | re-read at each retro |
| [evals/](evals/) | maintainers | pilot reports, and golden tasks to re-run after editing a command |

## Supported agent tools

Set `TOOLS` in `.cortex/config`, then run `bash scripts/cortex/adapt.sh`.

| Tool | Generated | Isolation for test-first / implement / review |
| --- | --- | --- |
| Claude Code | `CLAUDE.md` (`@AGENTS.md`), `.claude/skills/cortex-*`, `.claude/agents/cortex-*`, `.claude/settings.json` if absent | separate subagents (enforced); reviewers have no Edit/Write tools, but have Bash, so the real check is the before/after `git status` the skill runs |
| Cursor | `.cursor/rules/cortex.mdc` | by instruction: start a new chat for each role |
| GitHub Copilot | `.github/copilot-instructions.md` | by instruction |
| Gemini CLI | `GEMINI.md` | by instruction |
| Codex CLI | nothing (reads `AGENTS.md`) | by instruction |

## Limits

Deliberate trade-offs; each links to where it's explained.

- **Not yet used on a real project.** It has run end to end on toy
  repositories ([pilots](evals/pilots/)); treat your first real change as
  part of the evaluation.
- **No upgrade path yet.** `install.sh` refuses a repository with a
  different version installed, so moving to a later release is a manual
  merge ([extensions §4](docs/02-extensions.md)).
- **Every nontrivial change runs the full pipeline:** six stages, four of
  them in fresh agents; pilot 3's change cost about $6 in agent runs. There
  is no lighter tier for small fixes yet ([process weight scaled to
  stakes](docs/02-extensions.md)).
- **The test lock freezes every matching test and fixture** (and
  `.cortex/config`) while a change is in progress, so an implementer can't
  weaken old tests. Changing one means re-running `test-first` with your
  sign-off, and so does merging a `main` that changed locked files; a
  locked branch merges `main` in rather than rebasing, and can't take in a
  change to `.cortex/config` at all (start over from the new `main`)
  ([`test-first`](template/harness/commands/test-first.md),
  [rebasing](docs/02-extensions.md)). Merge, don't squash, a locked change
  that other branches build on: after a squash, CI sees the re-locks it
  dropped as dropped locks on those branches
  ([spec Amendment 12, N3](docs/specs/2026-09-23-v2-scripts.md)).
- **Local checks are guardrails, not a boundary.** An agent with full git
  access can get around them; the boundary is CI on the pull request plus
  required human review ([R11](docs/01-design-rules.md),
  [INSTALL.md step 5b](INSTALL.md)). CI judges history as pushed: a branch
  rebuilt so that weaker tests carry the first lock needs no sign-off, and
  only the reviewer, who sees those tests in the diff, catches it
  ([spec Amendment 12](docs/specs/2026-09-23-v2-scripts.md)).
- **Enforced isolation only in Claude Code.** In other tools, starting a
  fresh chat per role is up to you ([supported tools](#supported-agent-tools)).
- **One repository.** Systems spread over several repositories are a
  deferred extension ([§7](docs/02-extensions.md)).
- **The CI template is GitHub-only.** Other hosts need the equivalent set up
  by hand ([INSTALL.md step 5b](INSTALL.md)).

## Developing cortex

See [AGENTS.md](AGENTS.md). `bash tests/run.sh` runs every suite; CI runs
them plus shellcheck on every pull request and every push to `main`.

## License

MIT
