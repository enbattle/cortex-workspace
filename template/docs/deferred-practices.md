# Deferred practices

Practices this repository has considered and deliberately **not** adopted
yet, each with the condition that would make it worth adopting. `retro`
checks these triggers after every change. When a trigger fires, the practice
is proposed to the user (a large one is its own change folder) and its entry
is updated or removed; an adopted practice is documented where it lives, not
here.

Each entry: **what it is**, **why deferred** (the actual reasoning, not "not
needed"), **revisit when** (a condition that can be checked true or false).
"It's a best practice" is not a trigger.

The entries below are seeded from cortex's extensions catalog; the catalog
(cortex `docs/02-extensions.md`) has how to build each one and its pitfalls.
Delete an entry that can never apply to this repository, with a one-line
reason, rather than keeping it for completeness.

---

**Runbooks.** Fixed-format procedures (steps with a verify line each,
rollback, escalation) for operational tasks. *Deferred:* until a procedure
exists that people repeat. *Revisit when:* the same operational procedure is
explained ad hoc a third time, or one is performed wrong because it lived in
someone's head.

**Golden-task evals for the commands.** Frozen tasks with planted problems
(a diff with a known bug for `review`, an ambiguous proposal for
`spec-clarify`) graded against a rubric. *Deferred:* the pipeline log is the
cheap first measurement. *Revisit when:* a command is about to be edited and
nobody can say whether the edit helps, or an escaped defect appears.

**CI checks for the process.** A pull request touching source must include a
change-folder update or carry a `no-spec` label; `check.sh` runs in CI.
*Deferred:* until the process is stable enough to enforce. *Revisit when:* a
nontrivial change merges without a change folder, or `check.sh` is found
failing on the default branch.

**A deeper security program.** Dependency and secret scanning in CI, threat
models per surface. *Deferred:* `review`'s separate security pass covers each
new surface. *Revisit when:* the system holds sensitive data, has external
users, or a security finding escapes review.

**Multi-repo coordination.** Shared interface contracts, a system map, and
change folders that span repositories. *Deferred:* this is one repository.
*Revisit when:* a change must land in another repository at the same time as
this one.

**Parallel or orchestrated agents.** A script that runs independent tasks in
parallel and joins them. *Deferred:* orchestration amplifies whatever quality
exists. *Revisit when:* latency, not quality, is the recurring complaint in
the pipeline log.
