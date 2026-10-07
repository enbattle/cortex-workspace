# Golden task rubric: slugify maxLength, planted defects

Fixture: `fixture.bundle` in this directory (procedure in `README.md`).
Change folder: `changes/20260924-slugify-maxlength/`. Base (merge-base with
`main`): the commit that added the verification recipe, the conventions and
the template's constitution rules (E, S, W), after the cortex install was
merged.

| Tag | What it is | Expected verdict |
| --- | --- | --- |
| `golden-planted` | the approved change plus one commit that breaks a criterion | request changes, naming the plant |
| `golden-quality` | the approved change plus one commit that keeps every result and wastes work | request changes, naming the plant |
| `golden-clean` | the approved change only (control) | approve |

At all three tags `bash scripts/cortex/gates.sh changes/20260924-slugify-maxlength`
prints `gates: ok` and all 26 tests pass.

## Planted defect: correctness (`golden-planted`)

The last commit, "perf(slugify): bound the work done on very long inputs when
maxLength is set", changes `src/slugify.js` so that, when `maxLength` is set,
the input is pre-truncated to `Math.max(256, maxLength * 4)` characters
BEFORE the slug is built:

    const source = String(input);
    const text =
      maxLength === undefined ? source : source.slice(0, Math.max(256, maxLength * 4));

The slug is then built from that prefix, so for long inputs (over 256
characters with enough non-`[a-z0-9]` characters, e.g. padding, punctuation,
or non-Latin text) the result is not derived from the full slug. It violates
AC3/AC4 (not the longest word-boundary prefix of the full slug; a word can be
cut mid-word), AC2 (a shorter or empty slug when the full slug fits), and
AC5 (not a prefix of the full slug in general), and it breaks the proposal's
clarified rule "truncation happens after the full slug is built ... for
inputs of any length" (Open questions, 5).

Reproductions (expected -> actual at `golden-planted`; `golden-clean` gives
the expected values):

- `slugify(' '.repeat(250) + 'helloworld again', { maxLength: 10 })`: `'helloworld'` -> `'hellow'`
- `slugify('Привет '.repeat(40) + 'hello world', { maxLength: 20 })`: `'hello-world'` -> `''`

The locked tests do not catch it: the random sweep uses inputs under 40
characters and `maxLength` 1..42.

## Planted defect: quality (`golden-quality`)

The last commit, "refactor(slugify): truncate by dropping words from the
end", replaces the one-pass truncation with:

    const words = slug.split('-');
    let kept = words.length;
    while (kept > 1 && words.slice(0, kept).join('-').length > maxLength) kept--;

Every result is the same as at `golden-clean` (checked at build time over
1,786,429 inputs and limits, with 0 differences), so every criterion holds
and every test passes. But each step of the loop rebuilds the remaining
words into a string, and the loop runs once per word dropped, so the work
grows with the square of the slug's length. It breaks the review
checklist's "Performance and resources" item (no work quadratic in input
that can grow) and the approved design's "the cost stays linear for inputs
of any length" (`design.md`, Approach), and it takes the split-into-words
approach `design.md` lists as rejected. The commit message argues for it on readability, so a reviewer has to
weigh "the simplest construction" against waste.

Reproduction (`golden-clean` -> `golden-quality`, measured at build time on
Windows, Node 24; a reviewer's machine differs, the ratio is what matters):

- `slugify('word '.repeat(20000), { maxLength: 60 })` (100,000 characters):
  about 1 ms -> about 8 s. At 2,000 words, 0.1 ms -> 65 ms: ten times the
  input costs about a hundred times the time.

## Grading, per run

- **PASS** (`golden-planted`): the verdict is request changes and contains a
  finding that names this defect (the input pre-slice / truncating the input
  before the slug is built / wrong or empty results for long inputs) at
  **medium severity or higher**.
- **PASS** (`golden-quality`): the verdict is request changes and contains a
  finding that names this defect (repeated joining or re-scanning in the
  loop / quadratic or super-linear time / slow on long inputs) at **medium
  severity or higher**. A finding that only calls it "less clear" or a
  style preference doesn't name the defect.
- **FAIL** (either plant): anything else, including naming it only at low
  severity or as non-blocking, and approval with the plant unmentioned.
  Record which of these it was.
- **Control** (`golden-clean`): **PASS** if the verdict approves, or every
  blocking finding is a real defect you can reproduce; **FAIL** if it blocks
  on a finding that isn't real (a false positive). The `map(slugify)` break
  is documented and accepted (AC8, Open questions 6), so blocking on it is
  a false positive and a FAIL. A pre-truncation or quadratic-time finding
  here is impossible and would be a FAIL.

Other findings don't affect a planted run's grade; list them in the results
file with your judgment of each (real, arguable, false positive), since a
reviewer that buries the plant among many invented findings is a problem the
grade alone doesn't show.

Also record, for every run, whether the reviewer left the clone exactly as it
found it (`git status --porcelain -uall` empty, HEAD unchanged). A dirty
clone is noted as an isolation failure, separately from the grade.

The task passes for a `review.md` edit only if every planted run of both
plants is PASS and the control is PASS.
