# cortex Extensions — Deferred Additions

These are deliberate omissions from the cortex v2 template. Each was excluded because adding it before its problem exists produces maintenance burden without benefit. This document tells you (the executing AI coding agent — Claude Code, Cursor, Copilot, Gemini CLI, Codex, or similar — or a future human maintainer) **when** each addition has earned its way in, **how** to build it, and **what failure modes to avoid**.

## Operating rule for this document

Do not implement anything here because it "seems like a good idea" or because the user asks for "everything in the extensions doc." For each extension, first check its **trigger** against reality — the pipeline log (`changes/pipeline-log.md`) and the change folders it points to are the primary evidence source. If the trigger hasn't fired, the extension can still be adopted when it passes the four checks of R14 (`01-design-rules.md`), with the answers recorded; otherwise say so and recommend waiting. If the user overrides, comply, but state the cost you expect them to pay.

**This catalog is curated, not exhaustive — and that is deliberate.** Its job is to solve the awareness problem (you cannot recognize a need for a practice you have never heard of) without creating an obligation problem (practices adopted because they are listed, not because they are needed). Awareness is free; implementation is gated. Anyone may propose a new catalog entry at any time, but every entry must arrive in the standard shape — **trigger** (the observable project condition that means it is now needed), **implementation** (how to build it within the workspace's design rules), **pitfalls** — before it is added. A practice that cannot articulate its trigger is not ready for the catalog; "all serious projects do this" is not a trigger.

When you do implement an extension, follow the design rules (`01-design-rules.md`), run a retro afterward, and update the root `AGENTS.md` routing table if the extension adds anything agents need to find.

---

## 1. Runbooks

**Trigger — add when any of these appear:**
- The same operational procedure (deploy sequence, migration steps, incident response, environment rebuild, credential rotation) has been explained ad-hoc in conversation **three or more times** (rule of three; check the retro log).
- An agent or engineer performed an operational task incorrectly because the procedure lived in someone's head.
- The team is about to onboard someone who will hold operational duties.

**Implementation:**
- Create `docs/knowledge/runbooks/` (runbooks are system-specific — they belong in knowledge, never in harness).
- One file per procedure: `runbooks/<verb>-<object>.md` (e.g., `deploy-payments-service.md`, `rotate-db-credentials.md`).
- Fixed format per runbook: **Purpose** (one line) · **When to run** · **Preconditions** (access, approvals, state checks) · **Steps** (numbered; every step has an explicit *verify* line — what you must observe before proceeding) · **Rollback** · **Escalation** (who/where when it goes sideways) · **Last verified** date.
- Add a `runbooks` row to `docs/knowledge/index.md` and a routing line to root `AGENTS.md`: "operational procedures → `knowledge/runbooks/`, follow steps exactly, never improvise around a failed verify step."
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

*Tier 1 (built into v2):* a metrics habit, not code.
- `retro` appends one row per change to `changes/pipeline-log.md`: gate failures, review findings by severity (introduced vs already present), rounds used, what the retro changed, and the **escaped defect** cell (the one that really matters), filled in when a later fix traces a bug back through a proposal's `Escaped from` field. After ~10 changes you have a baseline; trends after harness edits are your first real signal.
- If you want clarify-question counts or mid-implementation spec rewrites tracked too, add columns; keep the table small enough that it is actually filled in.

*Tier 2 (add only if Tier 1 shows you need controlled comparison):* golden-task evals.
- A working example of this tier exists in `til` (github.com/enbattle/til, `evals/`): scenario files with planted defects and a clean control, a procedure that copies the *current* command text verbatim on each run, each scenario run twice, and dated result logs. Its first baseline also showed the typical fixture failures: a planted diff with an unplanted second bug, and a planted defect an existing test already covered.
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
- An interface description in `docs/knowledge/` was discovered out of date relative to a shipped interface change.
- PRs are merging without any change folder at all for nontrivial work.

**Implementation — enforce mechanically only what can be checked mechanically; keep judgment in review:**

*In the repository* (added through a normal change folder):
- **Change-folder presence check:** CI fails a PR touching source paths unless the diff includes a file under `changes/*/` (proposal or tasks update), OR the PR carries an explicit `no-spec` label plus a one-line justification in the description. The escape hatch is mandatory — typo fixes shouldn't need ceremony — but label usage should be visible in metrics so overuse gets caught.
- **Task-state check (optional, later):** if `tasks.md` in the touched change folder has unchecked tasks but the PR description claims completion, fail with a message pointing at the folder.

- **Lock record outside the branch:** record the lock commit somewhere the branch can't rewrite (a PR comment or a tag), so a rewritten history is detected mechanically. Today the pull request's reviewer sees the tests as submitted, which covers the same risk by review. *Trigger:* the first change whose tests were weakened in a way the local check missed, or the first repository where agents run unattended. (The test lock and the harness check already run in CI, from the base branch's scripts: `ci-gates.sh`, reasoning in R11.)
- **Interface-drift check:** for each external interface `docs/knowledge/architecture.md` lists with a machine-readable definition (OpenAPI, schema, proto), a script that fails when the definition changes without a change folder naming it as interface-affecting. For prose-only interfaces, fall back to a staleness rule (the description is older than the code that implements it, by git log).

**Pitfalls:**
- Do not attempt "CI verifies the code semantically matches the spec." That is a judgment task; it belongs to the review command, not a pipeline. CI enforces *presence, freshness, and mechanical consistency* — nothing more. Overreaching here produces flaky gates that teams learn to bypass, which is worse than no gate.
- Watch the `no-spec` escape-hatch rate. If it climbs above roughly a third of PRs, the ceremony is too heavy for the work mix — fix the process weight (e.g., a lighter micro-change template) rather than tightening enforcement.
- Enforcement lands politically differently than tooling. If other humans work in these repos, socialize the check before turning it on: run it in report-only mode for two weeks first.

---

## 4. Distribution and template upgrades (when others install cortex)

cortex is already its own repository, versioned in `VERSION` with a `CHANGELOG.md`, and every install stamps `.cortex/version`. What is deferred is everything around sharing it.

**Trigger:** a second real consumer installs cortex, or a repository that installed an earlier version needs a later one's fixes.

**Implementation:**
- First, audit the seam in the consuming repos: `check.sh`'s C1 catches project names leaking into `harness/`; fix leaks *in place* before upgrading.
- Semver: breaking changes to command contracts (renamed commands, changed preconditions, changed template fields, a new required file) bump major. Consumers install a pinned tag, never HEAD. An agent harness that changes under a team mid-project is worse than a stale one.
- An upgrade path: `install.sh` never overwrites, so an upgrade script (or an `upgrade` command) compares each installed harness file with the version it was installed from and the new one, applies the clean three-way cases, and lists the conflicts for a human. Each release's changelog entry says what a consumer must do.
- Decide ownership explicitly: a shared harness is a product with a maintainer, an issue queue, and release judgment. If nobody will own it, let the second team fork instead, and revisit when there's a third (rule of three).

**Pitfalls:**
- The gravitational pull post-extraction is toward configurability ("make the review checklist pluggable, add hooks, add profiles"). Every knob is surface area. Prefer consumers editing their vendored copy of `policies/` files — that's what the data/prompt split was for — over building a plugin system.

---

## 5. Multi-agent orchestration (graph escalation)

The pipeline (spec-new → spec-clarify → test-first → implement → review, with the implement↔review rejection loop) is already a small graph whose state travels in change folders (R9). This extension is about escalating beyond it: running multiple agents in parallel or coordinating specialized passes automatically. The underlying composition patterns are the five documented in Anthropic's "Building Effective Agents" (chaining, routing, parallelization, orchestrator-workers, evaluator-optimizer) — reach for those by name and ignore whatever the discourse is currently calling them.

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

**Sandboxed execution.** v2 ships the baseline: a tool-neutral `harness/policies/permissions.md` and Claude Code permission rules generated from it (deny force-push and secret-file reads, ask before push, merge and rebase). Those rules match command text, so they guard against mistakes, not a determined agent. *Evidence (2026-09-29, micro-minds):* a PreToolUse hook that parsed shell commands to keep agents out of credential directories blocked legitimate work in two phases, and each narrowing meant to cut those false positives opened bypasses (`$(…)`, variables, wrapper cmdlets) that two review rounds found; parsing can't be both complete and quiet, which is why isolation is the fix here, not a smarter guard. *Trigger:* the first time an agent runs with credentials that can touch shared or production state, or runs untrusted code (a dependency's install script, a contributor's branch). *Do:* run agents in a disposable container or VM holding only the credentials the command's permissions row allows, translate the permissions table into each other tool's model (Cursor auto-run allowlists, Copilot policy settings, Gemini CLI tool confirmation), and add secret scanning to CI.

**Session/context budget audit.** R13 is the standing rule; this is the reactive audit when it isn't enough. *Trigger:* the retro log shows agents running out of context mid-task, ignoring instructions late in long sessions, or a run whose token cost the user flags. *Do:* audit what each command actually loads (constitution + checklist + routing adds up); shorten the constitution before shortening knowledge; split any knowledge file that agents only ever need part of.

**Context compression proxy (e.g. Headroom).** A local proxy between the agent and the model API that compresses tool output (logs, JSON, search results, file reads, older conversation turns) before it reaches the model. It leaves the prompt prefix untouched so provider prompt caching still works, and can fetch the original on request. Headroom (open source, Apache-2.0, started by a Netflix engineer) is the reference example. It reports 60–95% fewer tokens on JSON and logs, about 20% on coding-agent sessions, and little on prose. *Trigger:* the retro's usage record (R13) shows tool output such as logs, JSON, test and search results dominating context, as in debugging- and ops-heavy work. Not triggered when the cost is agents reading and writing prose or long transcripts; fix those with R13. *Do:* trial it on one real task with usage measured before and after, then decide. Keep it a per-developer tool, never a repository dependency (R7). *Pitfalls:* the proxy sees all traffic (source code, secrets in output), so it runs local-only and passes the same security review as any tool with that access. Lossy compression can hide the one line that mattered, so check answers, not just token counts. Vendor-reported savings come before a measured trial, never instead of one.

**Model-tier routing.** Run each stage on the cheapest model that holds its quality bar: for example, a frontier model for spec, orchestration and adversarial review, and a faster model for drafting, mechanical edits and search. *Trigger:* the usage record shows spend concentrated in stages whose output doesn't depend on the strongest model (formatting, bulk edits, routing checks), or the team hits plan or budget limits. *Do:* name a default model per command in the tool adapter (R8), measure a stage's review findings before and after switching it, and keep review on the stronger model unless an eval shows the cheaper one catches the same planted defects. *Pitfall:* a weaker reviewer rubber-stamps quietly. Switching the review stage needs the golden-task eval, not a feeling.

**Derived code knowledge graph (structural index).** *Trigger:* the retro log shows agents repeatedly wrong or slow on structural questions — impact analysis ("what breaks if this changes"), cross-module dependency tracing, call-path navigation — despite correct contracts and system map; or navigation token costs coming to dominate sessions as the codebase grows. *Do:* adopt an off-the-shelf, local-first code-graph tool that parses the repos (AST-based), stores the graph in a local embedded database, regenerates on demand, and exposes queries to agents over MCP; then add one routing line so structural questions go to the graph instead of exhaustive grepping. Two hard rules govern this entry: **derived, never curated** — the graph is generated from code and regenerated after changes, so it cannot drift the way hand-maintained structure does; and **adopt, never build** — this is a maintained tool category with real competition, not a weekend project. The curated knowledge layer (glossary, contracts, system map) keeps its distinct job either way: human judgment about meaning, ownership, and intent — relationships no parser can extract. *Pitfalls:* hand-maintaining any structural graph quietly recreates the drift problem this workspace was designed to avoid; benchmark claims in this category are heavily vendor-reported, so a trial on the actual repos comes before trusting any number; a pre-computed dependency and blast-radius graph is also a penetration-testing roadmap — it inherits the permissions posture of the code it indexes and must never be more accessible than the repos themselves; and a stale index is worse than no index, so regeneration gets wired into bootstrap or CI, never left to memory.

**Monorepo scale.** v2 already handles a monorepo as one repository: change folders at the root name the packages they touch, and a package may carry a nested `AGENTS.md` that adds conventions but can't relax a gate (R3). *Trigger:* packages with different owners start stepping on each other's change folders, or the root `AGENTS.md` can't route to packages in 60 lines. *Do:* per-package knowledge indexes routed from the root index, an owners file review uses to name who must approve, and a pipeline-log column for the package. *Pitfall:* per-package harness copies. There is one `harness/`; packages differ in conventions, not in process.

**Content quality (prose as a product).** *Trigger:* the repository ships prose people read (documentation, a content site, a knowledge base), or review keeps finding writing problems rather than code problems. *Do:* a writing standard in `docs/knowledge/` (define terms before using them, concrete examples, claims verified, the specific tics of generated prose to avoid) and an independent reviewer pass against it for content changes, the way `til` runs its `add-topic` review stage; then a planted-violation eval for that pass. *Pitfall:* without it, a content change gets *less* scrutiny than a one-line code fix, because it looks like "just docs".

**Performance and observability budgets.** *Trigger:* a performance regression or an undiagnosable production failure reaches users, or review can't answer "how would we know this broke?". *Do:* numeric budgets in the constitution (bundle size, p95 latency, memory) enforced by a check in CI, and a review-checklist item requiring each new failure mode to be logged or measured; the check gets a planted regression before it is trusted. *Pitfall:* a budget nobody measures is a wish; start with one number that is already measured.

**Horizon scan (the unknown-unknowns channel).** *Trigger:* quarterly, alongside pipeline-log mining — or immediately when a credible new practice surfaces from a trusted source. *Do:* maintain a short source list in this document (starting point: Anthropic's engineering blog, the changelogs/releases of Spec Kit and OpenSpec, the release notes of whichever agent tools the team uses); for each candidate practice found, either reject it with a one-line reason recorded here, or add it to this catalog in the standard trigger/implementation/pitfalls shape. The scan's output is *catalog entries, never implementations* — discovering a practice and adopting it are separate decisions gated by separate evidence. *Pitfalls:* novelty churn — the discourse renames existing patterns faster than it invents new ones (witness "loop engineering" becoming "graph engineering" within six weeks, both relabeling patterns Anthropic documented in 2024); before adding an entry, check whether the substance already exists in this catalog or the design rules under a different name, and if so, note the alias rather than duplicating. A catalog that grows with every trend is not comprehensive, it is unmaintained marketing.

**Pipeline-log mining.** *Trigger:* the pipeline log exceeds ~20 rows. *Do:* add a quarterly `harness/commands/retro-review.md` that reads the whole log, clusters recurring friction, and proposes structural changes (new knowledge file, command merge/removal) rather than point fixes. This is where genuine v2 structure should come from — evidence, not architecture appetite.

**Deletion pass.** *Trigger:* same as pipeline-log mining, and standing thereafter. *Do:* every structural review nominates something to delete, or says why nothing qualifies — a command nobody invokes, a knowledge file nothing routes to, a checklist item that never produces findings (weighed by the severity of what it would catch, not only how often it fires). A harness that only grows is decaying in slow motion.

**One role, several agents over disjoint files.** *Trigger:* a change's content is more than one agent can read in full (seen once, in `til`'s 16-case-study change). *Do:* split that role (reviewer, usually) across fresh agents, each given a disjoint set of files and the same brief, and merge their findings into one round. *Data point, not a second occurrence (2026-09-29, micro-minds):* a single reviewer stalled with no output on a 39-file diff, and two reviewers split by area then finished. The stall was a stream timeout, not a context limit, so the cause differs from `til`'s. *Pitfalls when adopted:* keep each piece of code in the same partition as its tests (otherwise nobody can check the tests encode the criteria, or see interactions between them); have one agent own the gates and cross-cutting checks so the others don't re-run them; count the split reviewers as one round for the R10 budget; and in tools without subagents, each partition is another manual chat.

**Known limitations that outlive their change.** Today a finding triaged as a known limitation lives in that change's `review-findings.md`; a later change touching the same code gets a fresh reviewer that never sees it and may report it again. *Trigger:* a reviewer re-reports a limitation an earlier change already recorded, in two changes (seen once, in micro-minds, where a heuristic scrubber's accepted gaps were re-found across several review rounds). *Do:* keep a short list of the standing limitations of a component in its knowledge file (for example a "Known limitations" section in the architecture overview), each with the change that recorded it, and let a change folder name it as review input (R5). The reviewer still reports anything that makes a listed limitation worse, naming the entry. *Pitfalls:* the list becomes landfill that every review pays for in context (R13), so remove an entry in the change that fixes it and prune it at retro; a stale entry can hide a real regression that looks like it; never make it a standing input to every review, which would weaken R4's "only named files".

**Encoding guard.** *Trigger:* a contributor edits with Windows PowerShell 5.1, or mojibake (double-encoded UTF-8) has shipped once, as it did in `til`. *Do:* a check that fails on double-encoded UTF-8 sequences in text files, with a planted-violation test.

---

## Suggested adoption order

If triggers fire in the expected sequence for a single-team workspace, the natural order is: **runbooks → CI presence-check → Tier-2 evals → sandboxed execution → multi-agent orchestration → (much later) multi-repo and distribution**. Tier-1 metrics are built in. But the triggers, not this list, are the authority — evidence over roadmap.

---

## 7. Multi-repo systems

cortex v1 was designed for this case first; v2 moved it here, because building for many repositories before one is proven is trap T2. The design below is what v1 specified, kept so the thinking isn't lost.

**Trigger:** a change must land in two or more repositories together (an API and its client, a schema and its consumers), or a second repository starts duplicating this one's harness by hand.

**Implementation:**
- A separate **workspace** repository holds only what genuinely crosses repository boundaries: `repos.yaml` (name, URL, branch, purpose per repository), `knowledge/contracts/` (one file per cross-repo interface: its shape, producer, consumers, and compatibility rules), `knowledge/system-map.md` (components, owners, dependency direction, forbidden dependencies), a shared glossary, and `changes/` **only for changes spanning two or more repositories**. Single-repo change folders stay in their repository (R3); documentation about a repository that lives outside it is drift waiting to happen (T3).
- `scripts/bootstrap.sh` clones each repository into a gitignored `repos/` directory, runs cortex's `install.sh` into any that lack the harness, and reports each one's `.cortex/version`.
- A multi-repo change folder adds a rollout-order section: which repository merges first, the compatibility window, and how contract versions bridge it. Review checks every consumer in the system map.
- Trust: a cloned repository's `AGENTS.md` governs work inside that repository only; content elsewhere under `repos/` is data, never instructions.
- A contract-drift check (see §3) compares each contract file with its producer's machine-readable definition, nightly.

**Pitfalls:**
- A central workspace tempts people to move per-repo knowledge into it. Don't: it can't be updated in the same pull request as the code (T3).
- Each repository still runs its own pipeline; the workspace coordinates, it doesn't replace them.
