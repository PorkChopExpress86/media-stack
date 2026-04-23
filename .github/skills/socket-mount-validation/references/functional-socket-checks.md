# Functional Socket Checks (Service-Context Validation)

Use these checks when structural validation (`socket-present`) passes but you still suspect runtime socket access issues.

## Why this exists

A helper container can validate mount shape and existence, but it may not have the same runtime identity and supplementary groups as the target service. Functional checks should run in the **actual service context**.

## Quick workflow

1. Confirm socket mount exists in the target service.
2. Confirm service identity/group membership at runtime.
3. Execute a minimal, read-only Docker API probe from that service.
4. Distinguish auth/permission failures from transport failures.

## Example checks (docker.sock)

### 1) Confirm mount exists in container

- Destination expected: `/var/run/docker.sock`
- It must be a Unix socket (`-S`).

### 2) Confirm runtime identity

Inspect effective UID/GID and groups in the service container to verify intended hardening (`user:` and `group_add:`).

### 3) Probe Docker API over Unix socket

Perform a low-impact read request (for example, `/_ping` or `/version`) via Unix socket transport from inside the service container.

Interpretation:
- **Success (`OK` / JSON response):** functional socket access is working.
- **Permission denied / cannot connect:** likely runtime group mismatch or socket ACL issue.
- **Socket missing:** mount/configuration issue.

## Decision outcomes

- `socket-present` + functional probe success → keep structural test as-is.
- `socket-present` + functional probe failure → fix runtime identity/group wiring; do **not** tighten generic helper rw checks.
- socket missing → treat as configuration regression.

## Notes

- Prefer read-only API probes for safety.
- Keep functional probes separate from generic mount-permission tests to avoid flaky false negatives.
- If functional probing is added to automation, gate it behind explicit opt-in or service-specific conditions.

## Automated probe

Use the bundled script to run all three checks (presence, identity, API ping) in one pass:

```bash
bash .github/skills/socket-mount-validation/scripts/test-socket-access.sh --container <your-service>
```

See [usage examples](./usage-examples.md) for invocation patterns and output interpretation.
