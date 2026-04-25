# Copilot Instructions for MediaServer

These instructions apply to all work in this repository.

## Compose bind-mount standards

- Treat each stack folder as the compose working root:
  - `arr-stack/compose.yml`
  - `immich/compose.yml`
  - `jellyfin/compose.yml`
  - `lan-apps/compose.yml`
  - `monitoring/compose.yml`
  - `nginx-proxy/compose.yml`
  - `proxied-apps/compose.yml`
- For stack-local data mounts, use `./data/...` relative paths.
- Do **not** prefix stack-local paths with the stack name inside that stack compose file (for example, avoid `./proxied-apps/data/...` inside `proxied-apps/compose.yml`).
- Keep external media/library paths explicit and intentional via env vars or absolute host paths (for example `${movies}`, `${audiobooks}`).

## Safety rules for bind-mount path changes

When changing mount source paths:

1. Create a timestamped safety backup in `vol_bkup/` before migration.
2. Stop affected containers before data sync.
3. Sync data to target mount path preserving ownership/permissions.
4. Start containers and verify running bind sources with `docker inspect`.
5. Only then remove retired folders.

## Verification checklist

Before closing a mount migration task:

- `docker compose -f <stack>/compose.yml config` resolves to intended host source paths.
- Runtime `docker inspect <container>` shows expected bind sources.
- No active compose file references remain for retired paths.
- Old path references, if any, are only historical logs/docs.