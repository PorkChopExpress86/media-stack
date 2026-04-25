---
name: compose-bind-mount-standard
description: 'Enforce stack-local Docker compose bind-mount conventions and safely migrate data paths. Use when: editing compose bind mounts, fixing nested stack paths, consolidating duplicate data folders, or validating mount sources with docker inspect.'
argument-hint: 'Describe the stack and path issue (e.g., "proxied-apps nested data path", "move mounts to ./data")'
user-invocable: true
disable-model-invocation: false
---

# Compose Bind-Mount Standard Workflow

## Goal

Keep bind mounts predictable and safe across modular compose stacks.

## Standards

- Use `./data/...` for stack-local bind mounts.
- Relative paths resolve from each stack directory.
- Avoid `./<stack>/data/...` inside `<stack>/compose.yml`.
- Keep external media mounts explicit (`${movies}`, `${audiobooks}`, etc.).

## Workflow

1. Render compose config to inspect resolved host paths.
2. If paths are wrong, patch compose file to `./data/...` style.
3. Backup source data under `vol_bkup/`.
4. Stop affected stack.
5. Sync old path data into canonical path.
6. Start stack.
7. Verify runtime bind sources with `docker inspect`.
8. Remove retired directories only after successful verification.

## Required validation

- `docker compose -f <stack>/compose.yml config`
- `docker inspect <container>` mount source checks
- grep check for stale old-path references in active compose files
