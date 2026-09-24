# Workspace-AI Workflows — Mental Traps and Best Practices

This document exists to help anyone building or maintaining an AI workspace avoid re-learning, the expensive way, lessons that have already been paid for. It is the "why" layer of the set: the highlights document orients newcomers at a glance, the bootstrap document describes what to build, the extensions document describes what to build later, the operator's field guide trains the running of the feedback loop, and this one describes how to *think* while deciding. It is written for humans making design decisions. Agents are best pointed at it only when explicitly asked to evaluate or change the workspace's structure, never during routine execution — loading philosophy into an implementation session is itself one of the traps described below (T8).

A note about this document, in its own spirit: it earned its existence by having a distinct job no other document performs, and it does not get to grow into a dumping ground for every insight. New entries should be traps that were actually encountered (or demonstrably nearly encountered), written with the standard anatomy below. Wisdom collected speculatively tends to be trivia.

---

## The five principles behind everything

**P1 — Awareness is free; obligation is expensive.** Knowing a practice exists costs a catalog line. Adopting it costs attention, maintenance, credibility, and agent context — forever. The two are best separated ruthlessly: comprehensive *awareness* (a curated catalog with triggers), minimal *adoption* (only what evidence demands). "It's a best practice" describes awareness; on its own, it is never a reason for adoption.

**P2 — Evidence over roadmap.** The retro log outranks architectural appetite. Structure earns its way in through observed friction, not anticipation of it. Corollary: instrument first (a metrics table in markdown is enough), build second.

**P3 — Artifacts over conversations.** Anything a later stage, another agent, or a future human needs must live in a durable file, never in a session's memory. This one principle buys reviewer isolation, crash recovery, parallelism, and honest handoffs — all for the price of writing things down.

**P4 — Canonical content once; everything else points at it.** Duplicated content is drift by construction. Tool adapters, wrappers, and summaries contain delegation, never copies. The moment the same fact is maintained in two files, one of them is already wrong — it just isn't yet clear which.

**P5 — Loops terminate; humans decide.** Every automated iteration has a stop condition, a budget, and an escalation path. Judgment calls — merging, waiving, resolving conflicts, spending a third review round — belong to people. An agent that never gives up is not persistent; it is unaccountable.

---

## The trap catalog

Each trap follows the same anatomy: **the pull** (why capable people fall in), **the cost**, **the tell** (how the trap tends to look from the inside), and **the antidote**.

### T1 — Completeness-as-safety
*The pull:* covering every practice up front feels like protection against future gaps — the reasoning usually sounds like "it will be harder to know what's needed if it never existed in the document."
*The cost:* documents that agents skim and humans perform; twenty mandated practices yield twelve done as theater; the ceremony that was actually needed gets bypassed along with the ceremony that wasn't.
*The tell:* an addition being justified with "all serious projects use this" rather than a condition the project has actually exhibited. The instinct also tends to recur in different clothing — designing extraction before a second team exists, adopting a tool "for all future projects," addressing every practice "for foundation."
*The antidote:* the awareness/obligation split (P1). Record the practice in the catalog with a trigger; build it when the trigger fires. A trigger is a *stronger* answer to the discovery problem than presence in a list — a list says the practice exists; a trigger says what a project looks like when it's time.

### T2 — Premature generalization
*The pull:* designing for future teams or projects feels like foresight; abstraction feels like engineering maturity.
*The cost:* generalizing from one example means guessing wrong about what's actually generic, then paying the abstraction tax on every change in the meantime. A shared harness is a product — versioning, breaking changes, an owner — whether or not anyone signed up to own it.
*The tell:* the word "future" doing load-bearing work in the justification while the consumer count is one.
*The antidote:* the rule of three — extract after the second or third real consumer demonstrates what's generic. In the meantime, buy the *option* cheaply: a clean directory seam and one naming rule (nothing generic may reference anything specific). An option costs a boundary; an abstraction costs a product.

### T3 — Knowledge separated from the code it describes
*The pull:* a central knowledge repo feels organized; one place for everything.
*The cost:* spec updates and code updates can never land in the same PR, so nothing can enforce their sync. This is how wikis die and how "documentation" becomes a synonym for "claims about the previous version."
*The tell:* a document about a repo living *outside* that repo, with no possible CI check that could catch it going stale.
*The antidote:* specs and local conventions travel with code, in-repo, through PRs. The central workspace holds only what is genuinely cross-cutting — contracts, system map, glossary, cross-repo changes — plus an index pointing into the repos.

### T4 — Building what already exists
*The pull:* "these requirements are specific"; building is more fun than evaluating; not-invented-here dressed as diligence.
*The cost:* maintaining alone, forever, a worse version of a tool that has full-time contributors — while the parts only this team could build go unbuilt.
*The tell:* no concrete answer to "what is being built here that the existing tools don't do?" — or an answer that describes their core feature set.
*The antidote:* trial before build (an afternoon of hands-on use beats a week of reading); adopt the machinery, own only the thin differentiating layer — for a workspace, that's the knowledge index, the policies, and the wiring, all of which are markdown a small team can afford to own.

### T5 — Label chasing
*The pull:* new terms ("prompt/context/loop/graph engineering") arrive with viral urgency and the implication that everyone serious has already moved on.
*The cost:* restructuring around vocabulary with a measurable half-life; documents named after trends rot by definition; renaming gets mistaken for progress.
*The tell:* the exciting new practice is younger than the retro log, and it's hard to state what it adds beyond patterns already implemented under older names.
*The antidote:* extract substance, discard branding. "Which durable pattern is this relabeling?" is a better first question than "should this be adopted?" All novelty routes through the horizon scan: catalog entries with triggers, never direct implementations. Six weeks is a fashion cycle, not an engineering signal.

### T6 — Tool coupling
*The pull:* the current agent tool's native features (its context filename, its command format, its subagents) are convenient right now.
*The cost:* every tool-specific assumption baked into canonical content becomes a migration project later, and the tool landscape churns faster than documents do.
*The tell:* a tool's brand name appearing in a file that isn't the README or the adapter script.
*The antidote:* canonical artifacts in tool-neutral form at stable paths; generated one-line adapters per tool (P4); the universal invocation ("read and execute this file") as the floor every tool can stand on. Adapters may be rich for the most-used tool — but adapters, not canon.

### T7 — The missing feedback loop
*The pull:* building the system is the visible work; instrumenting it feels like overhead on top.
*The cost:* a harness that cannot metabolize its own failures decays silently into documentation theater — and without measurement, no one can tell whether any edit helped, so edits become superstition.
*The tell:* a core prompt changed twice for the same recurring problem, with no way to say whether either change did anything.
*The antidote:* the retro habit from day one — friction captured as concrete proposed diffs, logged; metrics as a markdown table long before eval infrastructure; every structural change traceable to logged evidence (P2).

### T8 — Context as landfill
*The pull:* if the agent *might* need it, load it; more context feels like more safety.
*The cost:* attention dilution — instruction-following degrades as instruction volume grows; the practices that matter drown in the practices that might.
*The tell:* any file that says "read all of X"; a router file that has grown content of its own; philosophy documents loaded into implementation sessions.
*The antidote:* progressive disclosure — small single-purpose files behind a one-screen router; commands name exactly what they need; token budgets treated as real budgets. When agents misbehave late in sessions, the first fix is shortening what they load, not adding more instructions about behaving.

### T9 — Contaminated verification
*The pull:* the agent that wrote the code has all the context — surely it reviews fastest.
*The cost:* the reviewer inherits the writer's assumptions and blind spots, producing a rubber stamp with extra steps and the *feeling* of review — which is worse than no review, because it discharges the vigilance.
*The tell:* review happening in the same session as implementation; approvals that never articulate what was probed.
*The antidote:* fresh context, artifact-only inputs (P3), an adversarial mandate ("find the strongest case against before approving"), and approvals that must show their work, so empty ones are visible. The same logic applies one level down: verifiers are locked before generation — tests derived from acceptance criteria get written, confirmed failing, and committed before implementation begins, so the code is graded against a standard it cannot quietly rewrite. An implementer permitted to edit its own tests is a writer reviewing its own work by another name.

### T10 — Unbounded loops
*The pull:* retrying feels like diligence; the agent is so close; one more attempt.
*The cost:* doom loops — the same failure met with the same fix, indefinitely, burning budget and (worse) mutating code along the way; rejection cycles that hammer at a spec problem with code changes.
*The tell:* attempt three looking like attempt one; a change on its third review round.
*The antidote:* declared budgets, observable stop conditions, and escalation paths in every iterating step (P5). Hardcoding the numbers in v1 is reasonable — a configurable budget nobody has evidence to tune is just a knob, and the point is that *a* limit exists, not that it's optimal. Repeated failure is information: escalate it rather than absorb it.

### T11 — Ceremony without exits (and exits without eyes)
*The pull:* strict process feels rigorous; enforcement feels like quality.
*The cost:* process heavier than the work teaches people to route around it, and routing-around becomes the habit that skips the process that *was* needed. The opposite failure is real too: escape hatches nobody monitors become the default path.
*The tell:* trivial changes requiring full ceremony; or the bypass label on a third of PRs with nobody noticing.
*The antidote:* mandatory escape hatches with visible usage metrics. When bypass rates climb, the fix is the process weight, not tighter enforcement. CI enforces only what is mechanical — presence, freshness, consistency; judgment stays with review.

### T12 — Taxonomy before need
*The pull:* an "ontology" or elaborate classification feels like deep understanding; structure feels like rigor.
*The cost:* an elaborate scheme nobody maintains and no agent reads, standing in for the three plain files that would have answered every actual question.
*The tell:* difficulty naming three concrete queries the structure answers that simpler files couldn't.
*The antidote:* start with the artifacts that answer real questions — glossary, system map, contracts. Formalize only when a real retrieval failure demands it, with the failure as the spec.

### T13 — Trusting generation
*The pull:* the agent (or the expert, or the author) produced it confidently; verifying feels like distrust.
*The cost:* stale references, broken seams, and hallucinated claims ship inside otherwise-good work — including work produced by whoever wrote the surrounding documents.
*The tell:* no mechanical check exists for a property being relied on; "it looked right" is the whole verification story.
*The antidote:* make invariants greppable and check them (naming rules, tool-name bans, budget declarations); read generated core prompts critically before trusting the machinery; run one real change through any new pipeline before believing in it. The stale references in an earlier version of this document set were caught only by grepping — that is best treated as the norm, not the anecdote.

### T14 — Growth as the only direction
*The pull:* additions are visible contributions; deletions feel like admitting mistakes.
*The cost:* a workspace that only accretes is decaying in slow motion — every unused command, unrouted file, and never-firing checklist item is context spent and credibility eroded.
*The tell:* nothing deleted since creation; a catalog that has grown every quarter.
*The antidote:* deletion discipline — every structural review nominates at least one removal; retro treats "this step added no value" as a first-class finding; aliases over duplicates when novelty turns out to be renaming.

---

## The pre-addition checklist

Before adding *anything* — a practice, a document, a command, a knowledge file, a tool — a recommended discipline is to answer these six questions in writing (two sentences each is plenty):

1. **What observed condition demands this?** (Cite the retro log or a concrete incident. "Best practice" and "future-proofing" are not conditions — see T1, T2.)
2. **Does it already exist** — in the workspace under another name, or in a maintained external tool? (T4, T5)
3. **Who or what will read it, and when?** If the answer is "agents, always," it is probably landfill (T8). If the answer is "nobody, specifically," that answers the larger question too.
4. **What keeps it true?** Name the mechanism — CI check, retro category, stamped version, greppable invariant — or accept that the addition will silently rot (T3, T13).
5. **What could be removed to make room?** Not always literally — but if the answer is never anything, that is a T14 signal.
6. **What is the exit cost?** Under uncertainty, options (seams, boundaries, catalog entries) beat commitments (abstractions, frameworks, obligations) — see T2.

An addition that clears all six can go in without guilt. The discipline is not minimalism for its own sake — it is ensuring that everything present is load-bearing, because that is what lets agents and humans trust that everything present *matters*.

---

## One last trap: this document

Meta-discipline for this file itself: entries enter only with the full anatomy and a real incident behind them; the horizon scan may propose entries, but the bar stays "someone actually fell in"; and if this document ever exceeds roughly twice its current length, the next structural review should consolidate it rather than extend it. A traps document that becomes exhausting to read has fallen into T1, T8, and T14 simultaneously — and will be skipped precisely by the reader mid-fall who needed it most.
