# Permissions

What each command may do, in tool-neutral terms. This table is canonical;
each agent tool's permission settings are generated from it
(`.cortex/adapters/`), the same way instruction adapters are. If a tool can't
enforce a row, the row still binds and review checks it.

| Command | Reads | Writes | Runs | Never |
| --- | --- | --- | --- | --- |
| `spec-new`, `spec-clarify` | code, knowledge, policies | the change folder | read-only commands | code, tests, the approval line |
| `test-first` | the change folder, code under test | test and fixture files; `tasks.md`; commits on the change branch | the test command | implementation files |
| `implement` | the change folder, code, knowledge | code, docs, `tasks.md`; commits on the change branch | build, test, lint, the cortex scripts | locked tests, new test files |
| `review` | the diff, the change folder, policies | `review-findings.md` only | tests, the cortex scripts | anything else |
| `retro` | the change folder, the pipeline log | approved edits only; the pipeline log | read-only commands | unapproved edits |
| `onboard` | knowledge | nothing | nothing | anything |

**No command ever:** pushes, merges, force-pushes, rewrites published
history, commits to the default branch, writes an approval line, reads
secret files (`.env` and similar), or runs a destructive or irreversible
operation without the user's go-ahead in that moment. Any step that would do
one of these is marked `HUMAN-GATE:` and stops there.

Tool permission rules match command text, so they are a guardrail against
mistakes, not a security boundary: a determined or confused agent can reach
the same effect another way. The real boundaries are server-side (branch
protection, required checks, deploy gates) and belong in the repository's
hosting settings.
