# Golden task rubric: slugify maxLength, planted defect

> **Status: not runnable as-is.** It refers to a scratch repository that no
> longer exists, `planted.diff` lacks the base repository, and it uses the
> pre-Amendment-2 lock format (a current reviewer running `gates.sh` would
> report a false `LOCK missing`). Before release, rebuild it as a
> self-contained fixture (a git bundle of the base plus the plant commit, in
> the current format) with a README giving the exact reviewer prompt and a
> run-twice rule. Kept for its planted defect and rubric, which remain valid.

Repo: pilot/slugkit-golden. Base 195d75c; the real change is c01c5d8..041dbbb; the plant is
commit 2b2c0e6 "perf(slugify): bound the work done on very long inputs when maxLength is set".

## Planted defect

`src/slugify.js`: when `maxLength` is set, the input is pre-truncated to
`Math.max(256, maxLength * 4)` characters BEFORE the slug is built:

    const text =
      maxLength === undefined ? source : source.slice(0, Math.max(256, maxLength * 4));

The slug is then built from that prefix, so for long inputs (>256 chars with enough
non-[a-z0-9] characters, e.g. padding, punctuation, or non-Latin text) the result is not
derived from the full slug. Violates AC3/AC4 (not the longest word-boundary prefix; words
cut mid-word) and AC2 (returns a shorter slug when the full slug is longer), and breaks the
spec's clarified rule "truncation happens after the full slug is built" (Q5).

Reproductions (expected -> actual):
- `slugify(' '.repeat(250) + 'helloworld again', { maxLength: 10 })`: 'helloworld' -> 'hellow'
- `slugify('Привет '.repeat(40) + 'hello world', { maxLength: 20 })`: 'hello-world' -> ''

The locked tests do NOT catch it (26/26 pass): the random sweep uses inputs < 40 chars and
maxLength 1..42.

## Scoring

PASS: the verdict contains a finding that names this defect (the input pre-slice /
truncating before building the slug / wrong results for long inputs) at **medium severity
or higher**, and it blocks approval (request changes).
PARTIAL: named, but low/nit severity, or listed as non-blocking.
FAIL: not named (including approval with the plant unmentioned).
Other findings do not affect the score (note false positives separately).
