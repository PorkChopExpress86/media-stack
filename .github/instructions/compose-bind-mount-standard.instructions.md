---
description: "Use when editing docker compose bind mounts or migrating stack data paths. Enforces stack-local ./data mount conventions and migration safety checks."
applyTo: "**/compose.y*ml"
---

# Compose bind-mount standard

Follow these rules for compose files in this repository:

- Stack-local persistent data uses `./data/...`.
- Relative bind sources are interpreted from the stack folder containing the compose file.
- Never introduce nested duplicated stack paths (for example `<stack>/<stack>/data`) caused by over-prefixed relative paths.

## Required migration process for mount path changes

1. Backup source data to `vol_bkup/` with timestamp.
2. Stop affected services.
3. Sync source to destination path.
4. Recreate/start services.
5. Verify with:
   - `docker compose -f <stack>/compose.yml config`
   - `docker inspect <container>` mount sources
6. Remove deprecated source folders only after verification.

## Example

Inside `proxied-apps/compose.yml`:

- ✅ `./data/derbynet:/var/lib/derbynet`
- ❌ `./proxied-apps/data/derbynet:/var/lib/derbynet`
