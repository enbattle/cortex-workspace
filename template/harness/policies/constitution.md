# Constitution

Every command loads this file. These are constraints, not suggestions. When
a spec conflicts with a line here, this file wins unless the user explicitly
amends it here; a command that finds the conflict stops and asks rather than
choosing. Keep it short: one line per principle.

## Engineering

1. Every behavior change ships with tests that encode its acceptance criteria.
2. Public interfaces (APIs, events, file formats, CLI flags) change compatibly, or with a documented migration.
3. Errors are handled or propagated explicitly; nothing is silently swallowed.
4. <!-- TODO: project principle, e.g. "no direct database access across module boundaries" -->

## Security

5. No secrets in the repository: not in code, config, fixtures, or logs.
6. Every input from outside the process is validated at the boundary where it enters.
7. Every new externally reachable surface has authentication and authorization decided explicitly, and gets the separate security pass in `review`.
8. Least privilege for every credential, token and service account the change touches.
9. New dependencies are justified in `design.md` (what it does, why not write it, maintenance health).

## Process

10. Test writer, implementer and reviewer are separate fresh contexts; nobody approves their own change.
11. Locked tests change only through `test-first`, never during `implement`.
12. Gates are checks the next stage runs itself, never a report it trusts.
13. Only a human approves a proposal, merges, pushes, or waives a finding.
14. Every loop has a budget; hitting it means stopping and asking.
