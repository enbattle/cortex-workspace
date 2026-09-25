# review

## Purpose

Adversarial review of an implemented change, by a reviewer with no stake in
it. You did not write this code. Your job is to find the strongest case
against the change before approving it.

## Preconditions

- **Isolation (design rule R4, in `.cortex/design-rules.md`).** You are running in a fresh context. Your
  only inputs are: the diff, the change folder, `docs/constitution.md`,
  `harness/policies/review-checklist.md`, and knowledge files the change
  folder names. If this conversation contains the change's planning or
  implementation, refuse and tell the user to start a fresh context. A
  command or skill invoked inside the implementing session is not a fresh
  context.
- `tasks.md` shows every task checked off, and the working tree is clean
  (`implement` commits every task). If tasks are open, stop and tell the user
  to finish `implement`. Missing gate output under `## Gate output` is a
  finding, not a reason to stop: you run the gates yourself anyway.

## Procedure

1. Record the working tree's state before you start
   (`git status --porcelain -uall`). Review never edits anything in the
   repository; any experiment or probe script goes in a scratch directory
   outside it.
2. Find the base, the commit the change branch started from:
   `git merge-base HEAD <default branch>` (in a fresh clone, use
   `origin/<default branch>`). The diff under review is
   `git diff <base>...HEAD`. Because the tree is clean, every new file is
   committed and appears in it (plain `git diff` would miss untracked files).
3. Re-run the gates yourself rather than trusting `tasks.md`:
   `bash scripts/cortex/gates.sh <change-folder>`. A failing gate is a finding.
4. Verify each acceptance criterion is actually met, not that code exists
   that looks related. Check each manual-verify item is listed for the user.
5. Walk `harness/policies/review-checklist.md` item by item.
6. Actively construct failure cases: invalid and hostile input, empty and
   huge input, concurrency and retries, authorization gaps, partial failure.
7. **Security depth.** If the diff adds or changes an external surface (a
   network endpoint, an authentication or authorization boundary, a webhook,
   file upload, deserialization of untrusted data, a new outbound call with
   credentials, a new dependency), a separate security pass is required: a
   second fresh reviewer runs `harness/policies/security-review.md` against
   the same inputs. Its findings join yours.
8. Label every finding as introduced by this diff or already present. Only
   introduced findings block approval; list the rest separately for the user.
   Rate each on this scale:
   - **High**: breaks an acceptance criterion, the constitution, security,
     or existing callers (an incompatible change to a public interface);
     blocks approval.
   - **Medium**: a real defect or gap outside the criteria (an unhandled
     edge case, a missing test for a risky path); blocks approval unless the
     user waives it.
   - **Low**: polish that doesn't change behavior; never blocks.
9. Confirm the working tree is exactly as it was in step 1.

Budget: this review runs once. After two request-changes rounds on the same
change (count the rounds in `review-findings.md`), refuse a third automated
round: repeated rejection means the spec or design is wrong, and the user
must decide how to proceed.

## Output

A verdict, **approve** or **request changes**, with findings ordered by
severity; each has the file and line, why it matters, and a concrete fix. An
approval includes a paragraph on what was probed and found sound, so an
empty approval is visible as one. On request-changes, write the findings to
`review-findings.md` in the change folder with the round number (the folder
carries them to the next `implement`, not this conversation). Each round is
a section headed `## Round <n>`, so the round count is mechanical. If you
are running read-only (an adapter may take away your write tools), return
the findings in that format instead; the session that started the review
writes the file and makes no other change. Either way, `review-findings.md` is
committed on its own, so the next `implement` round starts from a clean tree.

## Autonomy

Runs unattended. Read-only apart from `review-findings.md`, which the
calling session writes if the reviewer has no write access. The verdict is
advisory: merging, waiving a finding, or holding the round-three conference
are the user's decisions.
