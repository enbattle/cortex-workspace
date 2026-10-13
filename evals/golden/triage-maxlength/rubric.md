# Golden task rubric: triaging three review findings

Fixture: `../review-maxlength/fixture.bundle` at `golden-planted`, with
`findings.md` committed as the change folder's `review-findings.md`
(procedure in `README.md`). The task checks `implement` step 1: each
finding confirmed or disputed against the code and against the change's
recorded decisions.

| Finding | What it is | Expected outcome |
| --- | --- | --- |
| 1 | real: the plant `review-maxlength/rubric.md` describes | **fix** or **fix via test-first** |
| 2 | already decided: the `map(slugify)` break | **disputed**, naming the decision |
| 3 | not real: the claimed output doesn't reproduce | **disputed**, with the failed reproduction |

## Evidence the grades rest on

- Finding 1 reproduces at `golden-planted`: the call returns `'hellow'`
  (`review-maxlength/rubric.md`, Planted defect: correctness).
- Finding 2's fix contradicts the approved proposal: AC8 (the migration
  note), Affected areas (E2 allows the break with that migration) and Open
  question 6 (the user accepted the break; constitution P3 forbids the
  fix). The JSDoc states the migration too.
- Finding 3 doesn't reproduce: `slugify('ab cd', { maxLength: 3 })` returns
  `'ab'` at `golden-planted` (checked when this file was written, Node 24):
  `slug[3]` is `'c'`, so the code cuts at the last separator within the
  limit. Its premise is wrong, so it is a finding with no reproduction, and
  `implement` step 1 makes that disputed (spec
  `docs/specs/2026-10-13-til-ports.md`, D2).

## Grading, per run

- **Finding 1 PASS:** fix, or fix via test-first, with a reproduction (the
  call and its output, or the rubric's input). **FAIL:** disputed, known
  limitation, or no outcome.
- **Finding 2 PASS:** disputed, naming AC8, Open question 6, or the E2
  migration in Affected areas. **FAIL:** fix (it undoes a decision), known
  limitation (a High can't be one), or disputed without naming the
  decision.
- **Finding 3 PASS:** disputed, with the attempt that didn't reproduce it
  (the call and its real output). **FAIL:** fix or fix via test-first (work
  for a defect that isn't there), known limitation (records a defect that
  isn't there), or disputed with no evidence.
- A run is **PASS** only if all three are. Record each finding's outcome
  and reason as returned, and whether the clone was left as found
  (`git status --porcelain -uall` empty, HEAD unchanged) as an isolation
  note apart from the grade.

The task passes for an edit to `implement` step 1 only if both runs are
PASS. A run before the 2026-10-13 spec's D2 sentence is a baseline: it is
graded the same way, and a finding 3 FAIL there is the gap D2 closes.
