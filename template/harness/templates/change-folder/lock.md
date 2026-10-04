<!-- Written by test-first, in its own commit directly after the commit that
adds the tests; read by scripts/cortex/tests-locked.sh. The listed files,
every file matching TEST_GLOBS as of the named commit, and .cortex/config
itself are locked. Never edited afterward, except by a re-lock: test-first
re-runs, commits the corrected tests, then rewrites this file naming that
commit, with the user's sign-off below (design rule R6 governs who writes
it). Any other later commit or uncommitted edit fails the lock. -->

Tests-locked-at: <full sha of the commit that added the tests>

## Locked tests

- <path of each test or fixture file that commit created or changed>

<!-- On a re-lock only, the user's sign-off: -->
Re-lock signed off by:
