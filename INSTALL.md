# Install cortex into this repository

You are an AI coding agent. The user has asked you to install cortex into the
repository you're working in. Follow these steps in order. Never invent
project facts: anything the user doesn't know yet stays a visible
`<!-- TODO -->`, listed for them at the end.

`<cortex>` below means the directory this file is in.

## 1. Check the starting point

- Confirm the current directory is a git repository with a clean working
  tree (`git status`). If it isn't clean, ask the user to commit or stash
  first, so the install is one reviewable diff.
- Create a branch: `git switch -c cortex-install`.

## 2. Copy the files

Run `<cortex>/scripts/install.sh .` and show the user its summary. Files it
reports as `skipped (exists, differs)` already existed; you will merge them in
step 4. It never overwrites anything.

## 3. Interview the user, then fill in the placeholders

Ask, in one batch where you can:

1. The project's name, and one sentence on what the repository is.
2. The build, test and lint commands. Detect candidates first (`package.json`
   scripts, a `Makefile`, `pyproject.toml`, `Cargo.toml`, CI workflows) and
   ask the user to confirm them rather than asking from scratch.
3. How test files are named (for `TEST_GLOBS`, e.g. `*.test.ts tests/**`).
4. Which agent tools the team uses (`claude`, `cursor`, `copilot`, `gemini`,
   `codex`).
5. Five to eight non-negotiable engineering principles for the constitution's
   TODO slots. If they have none, propose some from the stack you've seen and
   get explicit approval for each.
6. Terms that are overloaded or confused in this codebase (glossary seeds),
   and the main components and who owns them (architecture seeds).

Then fill in `.cortex/config`, the placeholders in `AGENTS.md` (keep it at 60
lines or fewer), the constitution's project lines, `docs/knowledge/glossary.md`
and `docs/knowledge/architecture.md`. Delete any entry in
`docs/deferred-practices.md` that can never apply here, with a one-line reason.

Rules while filling in: nothing under `harness/` may name the project, and
nothing under `harness/` or `docs/knowledge/` may name an agent tool
(`check.sh` enforces both). Project-specific principles go in the
constitution as principles ("no database access across module boundaries"),
not as project names.

## 4. Merge what already existed

For each file `install.sh` skipped:

- **An existing `AGENTS.md`:** keep its project facts (commands, conventions,
  layout); move anything longer than a routing line into
  `docs/knowledge/`; add cortex's routing table and rules from
  `<cortex>/template/AGENTS.md`. Show the user the merged result before
  writing it.
- **An existing `CLAUDE.md` or other tool file:** its content moves into
  `AGENTS.md` or `docs/knowledge/`, and the file becomes the generated
  pointer. Show the user what moves where; it must lose nothing.
- **An existing `.claude/settings.json`:** don't replace it. Show the user the
  `permissions` block from `.cortex/adapters/claude-code/.claude/settings.json`
  and merge it with their approval.
- **Anything else:** show the user both versions and ask.

## 5. Generate adapters and check

```bash
scripts/cortex/adapt.sh
scripts/cortex/check.sh
```

Fix every `FAIL` line (each names the rule it enforces) and re-run until it
prints `check: ok`. If `.github/workflows/` exists, offer to add a CI step
that runs `scripts/cortex/check.sh`.

## 6. Smoke test in a fresh context

Ask the user to open a **new** session (or, where the tool supports it,
spawn a fresh subagent) and give it only: *"Read and execute
`harness/commands/onboard.md`."* If the fresh context can't answer its own
two check questions from the files alone, a knowledge or routing file is
missing something: fix it now.

## 7. Hand off

Commit on the `cortex-install` branch, but don't push or merge. Tell the user:

- what was created, merged, and skipped;
- every remaining `TODO`, by file;
- the recommended first step: take one small, real change through
  `spec-new` → `spec-clarify` → `test-first` → `implement` → `review` →
  `retro`, and let that run's friction decide what to adjust.
