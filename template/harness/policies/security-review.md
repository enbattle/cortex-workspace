# Security review

A separate pass `review` runs, in its own fresh context, when a diff adds or
changes an external surface: a network endpoint, an authentication or
authorization boundary, a webhook, a file upload, deserialization of
untrusted data, an outbound call that carries credentials, or a new
dependency. Same inputs as `review`; this checklist instead of the general
one. Report findings in the same format, each labeled introduced or already
present.

## Threat model (write it down, a few lines)

- What can reach this surface, and what does each caller control?
- What does the surface let a caller read, change, or trigger?
- What is the worst realistic outcome if the checks here are wrong?

## Checks

- [ ] **Authentication:** every path requires the identity it should; no unauthenticated fallback or debug path.
- [ ] **Authorization:** checked per object, on the server, for every operation (reading someone else's resource by changing an ID must fail).
- [ ] **Input:** type, size, and format validated before use; limits on request size, counts, and rates where abuse is cheap.
- [ ] **Injection:** no string-built queries, shell commands, paths, or templates from caller input.
- [ ] **Output:** errors reveal nothing internal (stack traces, other users' data, whether an account exists).
- [ ] **Secrets:** none in code, config, logs, or error messages; credentials have the least privilege that works.
- [ ] **Data in transit and at rest:** sensitive data is encrypted where it travels and where it is stored, per the constitution.
- [ ] **Dependencies:** a new package is maintained, pinned, and from a trusted source; its install doesn't run unexpected code.
- [ ] **Abuse:** replay, enumeration, and resource exhaustion considered; idempotency where requests repeat.
- [ ] **Logging:** security-relevant events (auth failures, permission denials) are logged without logging secrets.
