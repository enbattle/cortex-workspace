# AI Workspace Extensions — Deferred Additions

These are deliberate omissions from workspace v1. Each was excluded because adding it before its problem exists produces maintenance burden without benefit. This document tells you (the executing AI coding agent — Claude Code, Cursor, Copilot, Gemini CLI, Codex, or similar — or a future human maintainer) **when** each addition has earned its way in, **how** to build it, and **what failure modes to avoid**.

## Operating rule for this document

Do not implement anything here because it "seems like a good idea" or because the user asks for "everything in the extensions doc." For each extension, first check its **trigger** against reality — the retro log (`changes/archive/retro-log.md`) is the primary evidence source. If the trigger hasn't fired, say so and recommend waiting. If the user overrides, comply, but state the cost you expect them to pay.

**This catalog is curated, not exhaustive — and that is deliberate.** Its job is to solve the awareness problem (you cannot recognize a need for a practice you have never heard of) without creating an obligation problem (practices adopted because they are listed, not because they are needed). Awareness is free; implementation is gated. Anyone may propose a new catalog entry at any time, but every entry must arrive in the standard shape — **trigger** (the observable project condition that means it is now needed), **implementation** (how to build it within the workspace's design rules), **pitfalls** — before it is added. A practice that cannot articulate its trigger is not ready for the catalog; "all serious projects do this" is not a trigger.

When you do implement an extension, follow the workspace's existing design rules (R1–R10 in the bootstrap document), run a retro afterward, and update the root `AGENTS.md` routing table if the extension adds anything agents need to find.

---

## 1. Runbooks

**Trigger — add when any of these appear:**
- The same operational procedure (deploy sequence, migration steps, incident response, environment rebuild, credential rotation) has been explained ad-hoc in conversation **three or more times** (rule of three; check the retro log).
- An agent or engineer performed an operational task incorrectly because the procedure lived in someone's head.
- The team is about to onboard someone who will hold operational duties.

**Implementation:**
- Create `knowledge/runbooks/` (runbooks are system-specific — they belong in knowledge, never in harness).
- One file per procedure: `runbooks/<verb>-<object>.md` (e.g., `deploy-payments-service.md`, `rotate-db-credentials.md`).
- Fixed format per runbook: **Purpose** (one line) · **When to run** · **Preconditions** (access, approvals, state checks) · **Steps** (numbered; every step has an explicit *verify* line — what you must observe before proceeding) · **Rollback** · **Escalation** (who/where when it goes sideways) · **Last verified** date.
- Add a `runbooks` row to `knowledge/index.md` and a routing line to root `AGENTS.md`: "operational procedures → `knowledge/runbooks/`, follow steps exactly, never improvise around a failed verify step."
- Optionally add `harness/commands/runbook-new.md`: interviews the operator, drafts in the fixed format, and — importantly — asks "what went wrong last time?" to capture failure knowledge, not just the happy path.

**Pitfalls:**
- Runbooks rot faster than any other doc type. The `Last verified` date is the defense: the retro command should flag any runbook untouched for 90+ days as stale, and stale runbooks should say so at the top rather than pretend authority.
- Do not let agents *execute* destructive runbook steps autonomously (anything irreversible: prod deploys, data deletion, credential changes). Runbooks should mark such steps `HUMAN-GATE:` and agents must stop there and hand off. Encode this in the routing line.
- Resist writing runbooks for procedures that should instead be automated into a script. Rule: if the runbook has no judgment calls or verify branches — it's a pure command sequence — it should be a script in `scripts/` with a three-line runbook pointing at it.

---

## 2. Eval suite (measuring whether the harness works)

**Trigger — add when any of these appear:**
- You are about to change a core command (`review.md`, `spec-clarify.md`) and cannot say whether the change helps or hurts.
- A second team or consumer is adopting the harness (you now need evidence, not anecdotes, that it works).
- The retro log shows the same class of failure recurring after edits that were supposed to fix it — you're flying blind on whether edits do anything.

**Implementation — start with measurement, not infrastructure:**

*Tier 1 (build first, it's nearly free):* a metrics habit, not code.
- Extend `retro.md` to record, per completed change: number of clarify questions that changed the proposal; number of review findings by severity; number of post-review defects discovered later (the one that really matters); whether the spec needed mid-implementation rewrites.
- Keep it as rows appended to `changes/archive/metrics.md`. After ~10 changes you have a baseline; trends after harness edits are your first real signal.

*Tier 2 (add only if Tier 1 shows you need controlled comparison):* golden-task evals.
- Create `harness/evals/` with: `tasks/` — 5–10 frozen, real-ish tasks (a buggy diff the reviewer should catch with known planted defects; a deliberately ambiguous proposal the clarify command should interrogate; a spec the implement command should refuse for missing approval).
- Each task file: input artifacts + a rubric of expected behaviors (e.g., "must catch the authz gap in file X," "must ask about the undefined term Y," "must refuse and name the missing gate").
- `harness/commands/eval-run.md`: runs a named command against each relevant task in a fresh context, then a separate grading pass scores output against the rubric. Record scores with date and command version in `harness/evals/results.md`.
- Run before and after any nontrivial edit to a core command. Regression → revert or fix before merging the command change.

**Pitfalls:**
- The seductive failure is building eval infrastructure instead of shipping work. Tier 1 is a table in a markdown file; skipping ahead to Tier 2 because it is more interesting to build is the pattern to guard against.
- Rubric-graded evals of nondeterministic agents are noisy. Run each task 3× and look at the distribution; a single pass/fail tells you little. If two runs disagree, the rubric item is probably ambiguous — fix the rubric.
- Never let planted-defect tasks leak into training the reviewer prompt ("check for the authz gap in auth.py") — that's memorizing the test. Rotate planted defects when you edit the review command.
- Guard the metric you actually care about: real defects escaping review. Eval scores are a proxy; if proxy goes up while escaped defects don't go down, the evals are measuring the wrong thing.

---

## 3. CI-enforced spec-sync

**Trigger — add when any of these appear:**
- A change folder was found approved-but-stale relative to merged code (spec says X, code does Y) — this is the drift event the whole design exists to prevent; treat the first confirmed instance as the trigger.
- A contract file in `knowledge/contracts/` was discovered out of date relative to a shipped interface change.
- PRs are merging without any change folder at all for nontrivial work.

**Implementation — enforce mechanically only what can be checked mechanically; keep judgment in review:**

*In each product repo* (add via a normal change folder per repo):
- **Change-folder presence check:** CI fails a PR touching source paths unless the diff includes a file under `changes/*/` (proposal or tasks update), OR the PR carries an explicit `no-spec` label plus a one-line justification in the description. The escape hatch is mandatory — typo fixes shouldn't need ceremony — but label usage should be visible in metrics so overuse gets caught.
- **Task-state check (optional, later):** if `tasks.md` in the touched change folder has unchecked tasks but the PR description claims completion, fail with a message pointing at the folder.

*In the workspace repo:*
- **Contract-drift check:** a script (extend `scripts/`) that, for each contract file, extracts the declared shape and diffs it against the actual source of truth in the producing repo (OpenAPI file, schema file, proto — whatever exists). Run on a schedule (nightly) and on workspace PRs; failures open an issue rather than silently accumulating. Only build extractors for contracts that have a machine-readable source; for prose-only contracts, fall back to a staleness rule (flag contract files older than their producer's interface directory, by git log comparison).
- **Template-version check:** bootstrap already warns on stale repo stubs; promote it to a scheduled CI job so drift surfaces without anyone running bootstrap.

**Pitfalls:**
- Do not attempt "CI verifies the code semantically matches the spec." That is a judgment task; it belongs to the review command, not a pipeline. CI enforces *presence, freshness, and mechanical consistency* — nothing more. Overreaching here produces flaky gates that teams learn to bypass, which is worse than no gate.
- Watch the `no-spec` escape-hatch rate. If it climbs above roughly a third of PRs, the ceremony is too heavy for the work mix — fix the process weight (e.g., a lighter micro-change template) rather than tightening enforcement.
- Enforcement lands politically differently than tooling. If other humans work in these repos, socialize the check before turning it on: run it in report-only mode for two weeks first.

---

## 4. Harness extraction (when a second team arrives)

**Trigger:** a second real consumer wants the harness — not before. Speculative extraction is the failure mode the v1 seam exists to postpone.

**Implementation:**
- First, audit the seam: `grep` `harness/` for any system-specific leakage that crept in despite R1. Fix leaks *in place* before extracting.
- Extract `harness/` to its own repo. Version it — tags with semver; breaking changes to command contracts (renamed commands, changed preconditions, changed template fields) bump major.
- Consumers vendor a pinned version (git subtree or a pinned-tag copy script) rather than tracking HEAD. An agent harness that changes under a team mid-project is worse than a stale one.
- Add a `CHANGELOG.md` and a compatibility note per release ("templates stamped by v1 remain valid; re-stamp optional").
- Decide ownership explicitly: a shared harness is a product with a maintainer, an issue queue, and release judgment. If nobody will own it, don't extract — let the second team fork instead, and revisit when there's a third (rule of three).

**Pitfalls:**
- The gravitational pull post-extraction is toward configurability ("make the review checklist pluggable, add hooks, add profiles"). Every knob is surface area. Prefer consumers editing their vendored copy of `policies/` files — that's what the data/prompt split was for — over building a plugin system.

---

## 5. Multi-agent orchestration (graph escalation)

The workspace pipeline (spec-new → clarify → implement → review, with the implement↔review rejection loop) is already a small graph whose state travels in change folders (R9). This extension is about escalating beyond it: running multiple agents in parallel or coordinating specialized passes automatically. The underlying composition patterns are the five documented in Anthropic's "Building Effective Agents" (chaining, routing, parallelization, orchestrator-workers, evaluator-optimizer) — reach for those by name and ignore whatever the discourse is currently calling them.

**Trigger — add when any of these appear in the retro log:**
- Changes routinely decompose into independent workstreams that only need each other at the end (parallelizable work being done serially).
- Pipeline *latency* — not quality — is the recurring complaint. Quality problems are explicitly NOT a trigger: orchestration amplifies whatever quality you have; fix commands and knowledge first.
- A single change regularly requires three or more specialized passes (implementation, security review, docs, migration) that today are hand-sequenced.

**Implementation:**
- Governing principle: **code controls predictable routing; models handle steps requiring interpretation or judgment.** The orchestrator is a script (extend `scripts/`), not a prose "orchestrator prompt" that re-decides the workflow on every run — an agent re-deriving routing each time burns tokens and adds nondeterminism exactly where you want neither.
- Nodes are the existing commands, unchanged. R9 makes this possible: every command already runs from artifacts in a fresh context. If a command can't be invoked that way, fix the command, not the orchestrator.
- Edges are explicit. For each handoff, the script defines: the artifact passed (change folder path, diff), the success predicate checked *in code* (tests pass, findings file empty, approval line present), and the failure route (retry within the R10 budget, then escalate to a human). No implicit edges.
- Start with the two cheapest patterns only: parallel fan-out of independent tasks with a join, and the evaluator-optimizer loop you already have. Add routing or orchestrator-worker shapes only when a concrete change demands them.
- State lives in files, never in the orchestrator's memory: the orchestrator must be resumable after a crash by re-reading change folders. If killing the orchestrator mid-run loses information, the design is wrong.

**Pitfalls:**
- Failure surface: when a single loop fails, one agent failed; when a graph node fails, it becomes necessary to trace whether bad output propagated downstream. Log every node's inputs and outputs (artifact paths and content hashes) from day one — the trace is needed before the first post-mortem, not after.
- Premature graphs: a graph forces you to declare every node, edge, and failure mode up front; that rigidity is the price of explicitness. If the retro log shows the workflow still changing week to week, it is too early — loops tolerate ambiguity, graphs punish it.
- Parallel writers: never let two nodes write to the same repo concurrently without branch isolation; the join step reconciles branches, and a human resolves conflicts. An orchestrator that auto-resolves merge conflicts is making judgment calls in the code layer — a violation of the governing principle.
- Cost compounding: parallel agents multiply token spend and can compound errors. The orchestrator reports per-run cost and node-level failure counts from its first version — without visible cost reporting, there is no way to judge whether the graph earns its keep.

---

## 6. Other practices worth adding — each with its own trigger

**Agent permissions & sandboxing.** *Trigger:* the first time an agent runs with credentials that can touch shared or production state, or the workspace is used by anyone beyond you. *Do:* document per-command blast radius (which commands may write, which are read-only) in a tool-neutral table (e.g., `harness/policies/permissions.md`); then translate that table into whatever permission model each team member's tool provides (Claude Code allowed/deny tool rules, Cursor auto-run allowlists, Copilot policy settings, Gemini CLI tool confirmation, sandboxed execution where available) — the neutral table is canonical, the per-tool config is an adapter, same pattern as R8; mark destructive operations `HUMAN-GATE:` as in runbooks; never store secrets in the workspace repo — add secret-pattern checks to `.gitignore` review and CI once CI exists.

**Session/context budget audit.** *Trigger:* retro log shows agents running out of context mid-task, or ignoring instructions late in long sessions. *Do:* audit what each command actually loads (constitution + checklist + routing adds up); shorten the constitution before shortening knowledge; split any knowledge file that agents only ever need part of.

**Cross-repo change orchestration.** *Trigger:* the first genuinely multi-repo change reveals the workspace `changes/` folder needs more than the standard templates. *Do:* extend the change-folder template for the multi-repo case only — add a rollout-order section (which repo merges first, compat window, contract version bridging) — rather than complicating the single-repo template that most changes use.

**Horizon scan (the unknown-unknowns channel).** *Trigger:* quarterly, alongside retro-log mining — or immediately when a credible new practice surfaces from a trusted source. *Do:* maintain a short source list in this document (starting point: Anthropic's engineering blog, the changelogs/releases of Spec Kit and OpenSpec, the release notes of whichever agent tools the team uses); for each candidate practice found, either reject it with a one-line reason recorded here, or add it to this catalog in the standard trigger/implementation/pitfalls shape. The scan's output is *catalog entries, never implementations* — discovering a practice and adopting it are separate decisions gated by separate evidence. *Pitfalls:* novelty churn — the discourse renames existing patterns faster than it invents new ones (witness "loop engineering" becoming "graph engineering" within six weeks, both relabeling patterns Anthropic documented in 2024); before adding an entry, check whether the substance already exists in this catalog or the bootstrap doc under a different name, and if so, note the alias rather than duplicating. A catalog that grows with every trend is not comprehensive, it is unmaintained marketing.

**Retro-log mining.** *Trigger:* the retro log exceeds ~20 entries. *Do:* add a quarterly `harness/commands/retro-review.md` that reads the whole log, clusters recurring friction, and proposes structural changes (new knowledge file, command merge/removal) rather than point fixes. This is where genuine v2 structure should come from — evidence, not architecture appetite.

**Deletion pass.** *Trigger:* same as retro-log mining, and standing thereafter. *Do:* every structural review must nominate at least one thing to delete — a command nobody invokes, a knowledge file nothing routes to, a checklist item that has never produced a finding. A harness that only grows is decaying in slow motion.

---

## Suggested adoption order

If triggers fire in the expected sequence for a single-team workspace, the natural order is: **runbooks → Tier-1 metrics → CI presence-check → contract-drift check → Tier-2 evals → multi-agent orchestration → (much later) extraction**. But the triggers, not this list, are the authority — evidence over roadmap.
