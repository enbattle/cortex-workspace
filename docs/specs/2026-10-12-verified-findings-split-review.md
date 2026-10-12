# Plan: findings checked against recorded decisions, and a read-only role split across agents (3.3.0)

Status: **draft, awaiting the maintainer's approval.** A point-in-time
record.

## Context

The evidence, from the 3.2.0 effort
(`docs/specs/2026-10-12-verified-review-findings.md`, its Context and
"Known limitations recorded, not fixed"; `evals/audits/2026-10-12.md`):

- A review of this whole repository (about 20,000 lines) was more than one
  context could read without summarizing, so four fresh reviewers each
  took one area. They reported about thirty findings.
- Four fresh verifiers, given the design rules, the mental traps, the
  extensions catalog, the relevant specs and the audits, checked every
  finding a fix was proposed for. Several were then recorded as known
  limitations rather than fixed, because the fix would have contradicted a
  recorded decision or the behavior was already documented: reading the
  reviewer's instructions from the base branch (R4 defines them as the
  repository's files; it would block legitimate checklist edits); an
  unknown `TOOLS` name removing files (the documented v2 behavior); a fresh
  install's `adapt.sh` failing (it can't, with a fresh config).
- The separate test writers' questions corrected the spec in three places
  before any code (commit 6a74c63), and the first completeness audit found
  a regression the changes had introduced (V3's records guard) and a test
  suite that died on bash 3.2 yet was reported passing (findings A and B).

What exists already: R13 confirms a finding against the code before it
becomes work, and `implement` step 1 triages review findings against the
code, with disputes stopping for the user. The catalog
(`docs/02-extensions.md`) has "One role, several agents over disjoint
files", triggered by a *change* more than one agent can read in full: seen
once (`til`), with a data point (micro-minds). The repository review above
is a related occurrence (a repository, not a change).

What is missing: (1) a triage that asks whether a finding's fix
contradicts a decision the project recorded, which an agent that saw only
part of the project can't know; (2) a way to split a read-only role when
its material overflows one context, without weakening R4.

R14's four checks:
- **Mechanism:** a single context asked to read too much summarizes and
  misses defects; an agent with partial context proposes a fix the project
  already decided against.
- **Fit:** both observed in the 3.2.0 effort, as above.
- **Cost here:** extra agent runs only when material overflows one context,
  or when findings come from agents that lacked the decisions; a few lines
  in R13, `review.md`, `implement.md`, the review skill and this
  repository's `AGENTS.md`. No new command, file type or script.
- **Reversibility:** text only.

## Items

- **D1. R13 (`docs/01-design-rules.md`), the principle, once.**
  - The triage bullet: a finding is confirmed before it becomes work,
    against the code (the input occurs, it reproduces, it is reachable)
    and against the decisions the project recorded for that work, by a
    context that has them. A finding whose fix would contradict one is
    disputed: it stops for the user, who revisits the decision or records
    the finding. (A High finding still can't become a known limitation:
    `implement`.)
  - A new bullet: a read-only role (review, audit, verification) whose
    material is more than one context can read in full is split across
    fresh agents, each answering for one part, with the same brief. The
    session that briefed them merges their returns without filtering
    them; a finding is judged where findings are triaged, never by the
    session that merged it.
- **D2. `implement` step 1, the triage.** Besides the code, each finding is
  checked against the change's recorded decisions: `proposal.md`'s
  Non-goals, `design.md`'s Alternatives considered, the constitution,
  decision records the change folder names, and known limitations
  recorded in this change's earlier review rounds. A finding whose fix
  would contradict one is **disputed**, naming the decision.
- **D3. `review`, split when it must.** A paragraph under Preconditions: if
  the diff and the change folder are more than one reviewer can read in
  full, the calling session splits the review across fresh reviewers by
  file:
  - the parts together cover every file in the diff, and each part's file
    list is recorded in the round;
  - each piece of code stays in the same part as its tests;
  - every reviewer keeps R4's full inputs (it may read the whole diff and
    change folder) and answers for its own part;
  - one reviewer also owns the gates, the verification on the real
    artifact and the checklist's cross-cutting items;
  - the security pass (step 7) runs once, over the external-surface files
    and their tests;
  - the round lists each reviewer's findings as returned, collapses only
    identical findings (same file, line and defect), and its verdict is
    request changes if any reviewer's is; it counts as one round (R10).
- **D4. The Claude Code review skill.** When D3 applies, it spawns the
  split reviewers with their file lists, records each list in the round,
  and merges their returns as D3 says (an adapter carries out the
  canonical procedure: R8). It stays within C9's 25 lines (16 today).
- **D5. This repository's `AGENTS.md`.** A review or audit of cortex too
  large for one agent is split by area (R13). When its findings come from
  agents that lacked the decisions, a fresh verifier given the design
  rules, the mental traps, the extensions catalog, the relevant specs and
  the earlier audits classifies each (real and to fix, real but already
  decided, not real) before it becomes work, and the maintainer decides.
  The bias it prevents (R12): a partial-context reviewer's, and the
  orchestrator's, attachment to their own findings, and blindness to
  decisions they never read. The completeness-audit rule points to it.
- **D6. The catalog.** "One role, several agents over disjoint files"
  leaves `docs/02-extensions.md` (adopted) for a pointer to R13 and
  `review`; its pitfalls are the ones D3 now states. The template's
  `deferred-practices.md` has no entry for it.

- **D7. What else names a single reviewer.**
  - `.claude/agents/cortex-reviewer.md`: besides the change folder, it may
    be given the file list of its part, and it answers for that part
    (D3); one clause, the procedure staying in `review.md` (R8).
  - `README.md`'s workflow table: `review` runs in "one or more fresh,
    read-only agents" (split when the change is more than one can read).
  - Checked and unchanged: `security-review.md` (it runs once, D3), the
    security reviewer's agent, `retro` (a split round is one round),
    `docs/04-operator-feedback-loop.md`, INSTALL, the suites (only
    `golden-fixture.test.sh` reads these files, through the refresh), and
    the template's "Parallel or orchestrated agents" entry (a different
    practice: independent tasks, not one role).

## Non-goals

- No size threshold in a script: whether material fits one context is a
  judgment (R14), guided by the data points (a 39-file diff stalled one
  reviewer; a 20,000-line repository needed four).
- No splitting of writing roles (the test writer, the implementer): no
  evidence, and a split writer raises lock and consistency questions.
- No fresh verifier for every review finding in a project: `implement`'s
  triage, with the user deciding disputes, is that check.
- No cross-change list of known limitations: that is the catalog's "Known
  limitations that outlive their change", with its own trigger.
- No new command, file type or golden task: the golden task's diff is small,
  so D3 doesn't apply there; whether a split review finds what a single one
  would is measured the first time a real change needs one.

## Tests and evals

No script changes, so no new tests. Editing `review.md` and the review
skill means, in order: the golden fixture refreshed (`refresh.sh`;
`tests/golden-fixture.test.sh` fails until the installed copies match);
the golden task run twice with fresh reviewers (root `AGENTS.md`); and the
reviewer-tools probe re-run (the review skill changed, as for 3.2.0's V9).

## Release

A minor version (3.3.0): command procedures change, no contract breaks. A
`CHANGELOG.md` entry, and the release steps as for 3.2.0.
