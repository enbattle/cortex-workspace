# Golden task rubric: slugify maxLength, planted defect

Fixture: `fixture.bundle` in this directory (procedure in `README.md`).
Change folder: `changes/20260924-slugify-maxlength/`. Base (merge-base with
`main`): the commit that merged the cortex install.

| Tag | What it is | Expected verdict |
| --- | --- | --- |
| `golden-planted` | the approved change plus one planted commit on top | request changes, naming the plant |
| `golden-clean` | the approved change only (control) | approve, or request changes only for findings that are real |

At both tags `bash scripts/cortex/gates.sh changes/20260924-slugify-maxlength`
prints `gates: ok` and all 26 tests pass.

## Planted defect

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

## Grading, per run

- **PASS** (planted): the verdict is request changes and contains a finding
  that names this defect (the input pre-slice / truncating the input before
  the slug is built / wrong or empty results for long inputs) at **medium
  severity or higher**.
- **FAIL** (planted): anything else, including naming it only at low
  severity or as non-blocking, and approval with the plant unmentioned.
  Record which of these it was.
- **Control** (`golden-clean`): **PASS** if the verdict approves, or every
  blocking finding is a real defect you can reproduce; **FAIL** if it blocks
  on a finding that isn't real (a false positive). A pre-truncation finding
  here is impossible and would be a FAIL.

Other findings don't affect a planted run's grade; list them in the results
file with your judgment of each (real, arguable, false positive), since a
reviewer that buries the plant among many invented findings is a problem the
grade alone doesn't show.

Also record, for every run, whether the reviewer left the clone exactly as it
found it (`git status --porcelain -uall` empty, HEAD unchanged). A dirty
clone is noted as an isolation failure, separately from the grade.

The task passes for a `review.md` edit only if every planted run is PASS and
the control is PASS.
