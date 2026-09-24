# Golden task spec: slugify maxLength (approved acceptance criteria)

Source: slugkit changes/20260923-slugify-maxlength/proposal.md (Approved-by: Pilot Operator, 2026-09-23). Base commit 195d75c.

## Desired outcome

`slugify(input, { maxLength })` returns a slug no longer than `maxLength`,
cut only at a separator where possible, so it never ends in a `-` and never
ends in a partial word unless the first word alone is too long. Calls without
the option behave exactly as today.

Terms (slug, word, separator) are as defined in `docs/knowledge/glossary.md`.
"The full slug" below means what `slugify(input)` returns today, before any
truncation.

## Acceptance criteria

- [ ] AC1 (automatable): Without the option (`slugify(s)`, `slugify(s, undefined)`, `slugify(s, {})`, `slugify(s, { maxLength: undefined })`) the result is identical to today's for every input.
- [ ] AC2 (automatable): If the full slug's length is <= `maxLength`, it is returned unchanged. This includes a full slug of exactly `maxLength` characters, and the empty slug (`slugify('', { maxLength: 3 })` and `slugify('!!!', { maxLength: 3 })` are `''`).
- [ ] AC3 (automatable): Otherwise, if the first word of the full slug is <= `maxLength` characters, the result is the longest prefix of the full slug that ends at the end of a word and has length <= `maxLength`. Examples: `slugify('Hello big World', { maxLength: 9 })` is `'hello-big'`; with `maxLength: 8` it is `'hello'`; `slugify('hello world', { maxLength: 6 })` is `'hello'` (not `'hello-'`).
- [ ] AC4 (automatable): If the first word alone is longer than `maxLength`, the result is the first `maxLength` characters of that word. This is the only case in which a word is cut. Example: `slugify('Supercalifragilistic day', { maxLength: 5 })` is `'super'`.
- [ ] AC5 (automatable): For every valid `maxLength` and every input, the result has length <= `maxLength`, does not start or end with `-`, and is a prefix of the full slug.
- [ ] AC6 (automatable): `maxLength` must be an integer >= 1 when present. Any other value that is not `undefined` (`0`, `-1`, `1.5`, `NaN`, `Infinity`, `'10'`, `null`) throws a `TypeError` whose message contains `maxLength` (constitution 6).
- [ ] AC7 (automatable): `options`, when not `undefined`, must be a non-null object; `null`, a number, or a string throws a `TypeError` whose message contains `options`.

## Non-goals

- Truncating by bytes or grapheme clusters: slugs are ASCII, so length is `String.prototype.length`.
- Any other new option. Unknown option keys are ignored, as today (today any second argument is ignored).
- The behavior for arrays or functions passed as `options` is unspecified.
- Changing today's handling of a non-string `input` (`String(input)`), although it predates constitution 6; that is a separate change.

