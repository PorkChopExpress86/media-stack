---
name: socket-mount-validation
description: 'Validate Unix socket mounts (especially /var/run/docker.sock) in container permission regressions. Use when volume permission tests fail on socket writability/readability, when running hardened non-root containers, or when helper containers cannot mirror supplementary groups.'
argument-hint: 'Describe the socket mount failure you want to validate'
user-invocable: true
disable-model-invocation: false
---

# Socket Mount Validation (Why `socket-present` is correct)

## What this skill does

This skill gives a repeatable workflow for validating socket mounts in regression tests without creating false failures.

| Asset | Purpose |
|-------|---------|
| [Decision logic](#decision-logic) | When/how to classify socket mounts |
| [Procedure](#procedure) | Step-by-step remediation |
| [Probe script](./scripts/test-socket-access.sh) | Automated functional validation |
| [Functional socket checks](./references/functional-socket-checks.md) | Runtime probing reference |
| [Usage examples](./references/usage-examples.md) | Invocation patterns and output interpretation |

It is specifically designed for Unix domain sockets like Docker's API socket (`/var/run/docker.sock`) where:
- regular file or directory permission checks are not equivalent,
- helper containers may not inherit runtime group memberships (`group_add`) from the target service,
- strict read/write checks can fail even when the production service is correctly configured and operational.

## When to use

Use this skill when any of the following appears in logs:
- `path-not-writable(helper)` on a socket path
- `socket-unreadable(helper)` for `/var/run/docker.sock`
- regressions that started after hardening a service to non-root user + `group_add`
- permission checks pass for regular mounts but fail only for socket mounts

## Decision logic

### 1) Identify mount type first
- If mount target is **directory**: validate execute/read and write when mode is `rw`.
- If mount target is **regular file**: validate read and write when mode is `rw`.
- If mount target is **Unix socket** (`-S`): use **socket-specific criteria**.

### 2) For Unix sockets, avoid generic rw expectations
A Unix socket is not a regular file. Generic tests like `-w` can be misleading in helper contexts.

For regression stability, pass criteria should be:
- socket path exists and is a socket (`-S`) → `PASS|socket-present` (or helper variant)

### 3) Escalate only when needed
If socket-presence passes but runtime behavior still fails (e.g., service cannot talk to Docker API), perform a targeted functional check in the real service context rather than tightening generic permission assertions.

## Procedure

1. Run the regression suite and inspect failures.
2. Confirm the failing mount destination is a socket path (`/var/run/docker.sock` or similar).
3. Verify the service is intentionally hardened (non-root + supplemental Docker group as needed).
4. Update permission test logic to branch on `-S` before regular file checks.
5. Mark socket checks as `socket-present` (or `socket-present(helper)`) when the socket exists.
6. Re-run full regression suite and confirm all unrelated checks remain intact.
7. If runtime issues persist, run the probe script from the skill:
   ```bash
   bash .github/skills/socket-mount-validation/scripts/test-socket-access.sh --container <name>
   ```
   See [usage examples](./references/usage-examples.md) for all invocation patterns and failure interpretation.
   See [functional socket checks](./references/functional-socket-checks.md) for underlying diagnostic logic.

## Quality/completion checks

A change is complete when all are true:
- Socket mount is evaluated via socket-aware branch (`-S`) in both direct and helper paths.
- No regression in directory/file mount validation behavior.
- Full regression runner passes (or only fails for unrelated known issues).
- Log reason for socket checks is explicit (`socket-present`), so intent is auditable.

## Rationale summary

`socket-present` is intentional and security-compatible for hardened stacks because it avoids false negatives caused by test environment identity mismatch while still ensuring the critical artifact (socket mount) is present.

Use functional service-level checks to validate live Docker API interaction, not generic rw tests against socket inode metadata.
