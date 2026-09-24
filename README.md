# cortex

An installable harness for AI-assisted software engineering in a single
repository (one package or a monorepo): spec-first changes, tests written by
a separate agent before any implementation and then locked, isolated
adversarial review, and a feedback loop that changes the process only on
evidence. It is plain markdown and a few bash scripts, works with any agent
tool, and ships a Claude Code adapter that enforces as much of the isolation
as the tool allows.

**Status:** v2.0.0. The scripts are covered by test suites written by a
separate agent before the scripts were (`tests/`, 5 suites). The whole
pipeline has run end to end once, on a toy repository
([pilot 1](evals/pilots/2026-09-23-toy-repo.md)): review caught a real
compatibility break, and a fresh reviewer caught a planted bug the tests
missed. Its 15 friction points are fixed. The Claude Code adapter's
subagents haven't yet run from inside an installed repository, and cortex
hasn't been used on a real project; treat the first real change as part of
the evaluation.

## What you get

Installed into your repository:

```
AGENTS.md                      a 60-line router every agent reads first
harness/commands/              spec-new, spec-clarify, test-first, implement, review, retro, onboard
harness/policies/              review checklist, security review, permissions
harness/templates/             change folder (proposal, design, tasks), ADR
docs/constitution.md           the project's non-negotiables (project-owned; upgrades never touch it)
docs/knowledge/                index, glossary, architecture, decisions/
docs/deferred-practices.md     practices considered and deferred, with triggers
changes/pipeline-log.md        one row per change: gates, findings, retro, escaped defects
scripts/cortex/                check.sh, tests-locked.sh, gates.sh, adapt.sh
.cortex/                       config, version, design rules, adapter sources per agent tool
```

The workflow for a nontrivial change:

| Command | Who runs it | Produces |
| --- | --- | --- |
| `spec-new` | you + the agent | a change folder with a drafted proposal |
| `spec-clarify` | you + the agent | an interrogated proposal, design, tasks; **you** write the approval |
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
bash cortex-workspace/scripts/install.sh /path/to/your/repo
```

`install.sh` copies files only where none exist, so it is safe on an existing
repository and safe to re-run. Then open your repository in your agent tool
and say: *"Read and execute `<path to cortex>/INSTALL.md`"*. It fills in
`.cortex/config`, `AGENTS.md`, the constitution and the knowledge stubs with
you, merges any existing `AGENTS.md` or `CLAUDE.md`, and runs the adapters
and checks. Everything it can't know is left as a visible `TODO`.

## Reading order

| Document | For | When |
| --- | --- | --- |
| [docs/00-highlights.md](docs/00-highlights.md) | anyone | first: the ten practices in sixty seconds |
| [docs/01-design-rules.md](docs/01-design-rules.md) | maintainers, installers | the normative rules R1–R12 |
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

## Developing cortex

See [AGENTS.md](AGENTS.md). `bash tests/run.sh` runs every suite; CI runs
them plus shellcheck on each push.

## License

MIT
