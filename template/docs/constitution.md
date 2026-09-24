# Constitution

Every command loads this file. These are constraints, not suggestions. When
a spec conflicts with a line here, this file wins unless the user explicitly
amends it here; a command that finds the conflict stops and asks rather than
choosing. Keep it short: one line per principle.

This file belongs to the project, not the harness: it lives outside
`harness/` so a harness upgrade never touches it. Edit freely; cite a
principle as E2, S3, P1, and so on.

## Engineering

- E1. Every behavior change ships with tests that encode its acceptance criteria.
- E2. Public interfaces (APIs, events, file formats, CLI flags) change compatibly, or with a documented migration.
- E3. Errors are handled or propagated explicitly; nothing is silently swallowed.

## Security

- S1. No secrets in the repository: not in code, config, fixtures, or logs.
- S2. Every input from outside the process is validated at the boundary where it enters.
- S3. Every new externally reachable surface has authentication and authorization decided explicitly, and gets the separate security pass in `review`.
- S4. Least privilege for every credential, token and service account the change touches.
- S5. New dependencies are justified in `design.md` (what it does, why not write it, maintenance health).

## Process

- R1. Test writer, implementer and reviewer are separate fresh contexts; nobody approves their own change.
- R2. Locked tests change only through `test-first`, never during `implement`.
- R3. Gates are checks the next stage runs itself (`scripts/cortex/gates.sh`), never a report it trusts.
- R4. Only a human approves a proposal, merges, pushes, or waives a finding.
- R5. Every loop has a budget; hitting it means stopping and asking.

## Project

<!-- TODO: this project's own principles, as many as it needs, one line
each: P1, P2, ... For example "P1. No database access across module
boundaries" or "P2. The public API stays backward compatible within a major
version". -->
