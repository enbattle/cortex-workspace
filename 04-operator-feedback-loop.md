# The Feedback Loop — Operator's Field Guide

**This document is personal.** It is for the human running the workspace, meant to be re-read regularly — before a work session, after a rough one, at each retro. It is deliberately *not* part of the agent-loaded document set: pointing agents at operator pedagogy is the T8 trap (context as landfill). The bootstrap doc says what to build, the extensions doc says what to build later, the traps doc says how to think about structure — this one trains the skill none of those can encode: *recognizing a signal while it is happening*.

Once the workspace is running, everything changes through this loop. Not through inspiration, not through "while I'm at it," not through another completeness audit. Signal → change. That is the whole discipline.

---

## The anatomy of one cycle

Every cycle has the same six steps, and skipping any of them breaks the loop:

1. **Signal** — something felt wrong or measurably went wrong.
2. **Capture** — it gets written down instead of evaporating. (The agent's retro notes and the log exist for this; so does a two-word jot mid-session.)
3. **Diagnosis** — what root cause explains it. *This is the step most people cut short.* The same symptom often has two possible causes with two different fixes — diagnosing wrong means the friction returns, and the log will show it returned.
4. **Proposed diff** — a specific edit to a specific file. "Docs should be clearer" is a vibe; "add 'settlement' to glossary.md with this definition" is a diff. Vibes don't enter the loop.
5. **Approval** — the human decides. Always.
6. **Verification, later** — did the same friction recur after the fix? The dated log entries are what make this answerable without trusting memory.

Scope reminder: bugs in *code* go through the normal pipeline immediately. The retro loop is for defects in the *process and knowledge* — the harness, the documents, the workflow itself.

---

## The five signal sources

### 1. The human notices (the signals only a person can supply)
- The same thing has been explained to an agent twice.
- **Dread** when invoking a command. Dread is data about ceremony weight, not a mood to push through.
- The temptation to bypass the pipeline "just this once." The temptation itself is the signal — usually of T11 (process heavier than the work).
- Not trusting an output enough to skip checking it. Distrust of a specific step means that step's verification is missing or weak.

The skill to build: treat the *feeling* as a loggable event. Feelings about process are early-warning instruments; by the time the problem is objective, it has already cost more.

### 2. The agent notices, in-session (already wired into the documents)
- "I could not find needed context" — the routing mandate in `AGENTS.md` makes agents say this out loud.
- The retro categories: context not found, instruction ambiguous or ignored, knowledge wrong or stale, step added no value, tool-adapter breakage.
- **Every escalation is the loop knocking**: budget exhaustion, test-lock conflicts, spec-divergence stops. These aren't just interruptions to handle — they're events to capture.

### 3. The artifacts notice (lagging indicators no single session reveals)
- The same *category* of review finding appearing across consecutive changes.
- A change hitting its second rejection round.
- The trivial-change rule (or any escape hatch) being invoked suspiciously often.
- **The highest-severity signal in the system: a defect that shipped after review approved it.**

### 4. The calendar notices (staleness)
- Template-version warnings from bootstrap.
- "Last verified" dates aging on runbooks (once they exist).
- A quarter passing — the horizon scan and retro-review are calendar-triggered on purpose, because some signals never announce themselves.

### 5. The outside world notices
- The horizon scan surfaces a practice missing from the catalog.
- A tool update breaks an adapter.
- A new person's onboarding confusion. Fresh eyes are a gap-detection instrument; their confusion is signal about the docs, not deficiency in them.

---

## The judgment rules

**Log on first occurrence, act on second.** One incident is weather; a repeat is climate. The log is what distinguishes them without trusting memory. Acting on every first occurrence produces churn; ignoring repeats produces rot.

**Two exceptions act immediately:** escaped defects (a bug review approved) and anything security-shaped. These skip the wait-for-a-pattern rule and get a retro now.

**Batch, don't interrupt.** Don't context-switch mid-task to fix process. Jot the signal, finish the work, run retro at session end. The loop is a rhythm, not an interrupt handler.

**Diagnose before diffing.** Same symptom, different causes, different fixes. "Agent asked what a term means" → glossary missing the term (add a line) *or* glossary has it and routing failed (fix the index or the command's file list). Propose the wrong diff and the log will show the friction returning — which is itself useful, but slower.

**Fix the process, not the person.** If discipline keeps slipping, the diff is structural (a lighter template, a clearer gate), never "try harder." Willpower is not a fix; it's a symptom deferral.

**Promote recurring catches upstream.** A control that fires repeatedly downstream (review keeps catching the same class of defect) is working — and signaling that something leaks upstream. Move the check earlier: into the constitution, the repo conventions, the clarify questions. The goal is defects not written, not defects reliably caught.

**Deletions count.** "This step added no value" is a first-class retro finding. A loop that only adds is decaying in slow motion (T14).

---

## Worked examples (worth pattern-matching against)

**Knowledge gap vs routing failure.** Two changes in a row, the implement agent stops to ask what "settlement" means. Two log entries → act. Diagnosis fork: glossary lacks the term (one-line addition) vs glossary has it and the agent never looked (index/routing fix). Resolving the fork comes before proposing the diff.

**Ceremony weight, caught as temptation.** The trivial-change rule keeps getting mentally stretched to cover five-line bugfixes because full spec-new feels like overkill. That temptation is T11 in progress. Structural diff: a micro-change template variant (proposal-only) with defined boundaries — not a resolution to be more disciplined.

**Recurring caught finding.** Three consecutive reviews flag missing input validation on new endpoints. Review is *working* — and signaling an upstream leak. Diff: a constitution line or repo-convention entry the implement agent loads, so the defect stops being written. Promotion, not celebration.

**Escaped defect — the alarm bell.** A concurrency bug ships in an approved change. Immediate retro, no waiting for a pattern. Diagnosis fork: category was on the checklist but the approval paragraph shows it wasn't really probed (strengthen the review prompt) vs category absent for this stack (add the checklist line). This is also the event that starts the post-review-defect metrics row — and if it recurs, it fires the doc-02 trigger for Tier-2 evals with a planted-defect task. Triggers firing look like this: a real event, recognized.

---

## Session self-check (thirty seconds, end of any nontrivial session)

1. Did I explain anything an agent should have found on its own? → knowledge/routing signal.
2. Did anything escalate — budgets, test locks, spec divergence? → capture each one.
3. Did I feel dread, tedium, or the urge to bypass anywhere? → ceremony signal; name where.
4. Did I distrust any output enough to re-check it? → verification-gap signal.
5. Is anything I touched today the *second* occurrence of something? → that's the retro's agenda.

If all five are clean, no retro needed — the loop's silence is also information.

---

## The reminder this document exists for

The pull, forever, will be toward two failure modes: changing things because they *seem* improvable (audit appetite, completeness anxiety — T1 in new clothing), and changing nothing because logging feels like overhead. The loop is the narrow path between them: **evidence in, diffs out, verified later.** When unsure whether something deserves a change, the question is never "would this be better?" — almost anything "would be better." The question is: *which logged signal demands it?* No signal, no change. Two signals, no excuses.
