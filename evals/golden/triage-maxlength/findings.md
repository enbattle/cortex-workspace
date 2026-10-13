## Round 1

Verdict: request changes at @HEAD@, 2026-10-13.

1. **High** — `src/slugify.js`, the `text` assignment before the slug is
   built. With `maxLength` set, the input is cut to
   `Math.max(256, maxLength * 4)` characters before slugifying, so for long
   inputs the result isn't derived from the full slug (AC3, AC4, AC5; the
   proposal's Open question 5). `slugify(' '.repeat(250) + 'helloworld again', { maxLength: 10 })`
   returns `'hellow'`; the full slug's answer is `'helloworld'`. Fix: build
   the full slug, then truncate.
2. **High** — `src/slugify.js`, the `options` check. A second argument that
   isn't a non-null object now throws, so every existing
   `titles.map(slugify)` call (the index is a number) breaks: an
   incompatible change to a public interface (constitution E2). Fix: ignore
   a non-object second argument, as before.
3. **High** — `src/slugify.js`, the separator test after the length check.
   `slug[maxLength] === '-'` reads one past the limit, so when the
   separator sits at index `maxLength - 1` the slice keeps it:
   `slugify('ab cd', { maxLength: 3 })` returns `'ab-'`, which ends in a
   separator (AC3, AC5). Fix: test `slug[maxLength - 1]`.
