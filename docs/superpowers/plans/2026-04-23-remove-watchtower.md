# Remove Watchtower — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the watchtower service and its docker.sock mount entirely, replacing update-notification with a Friday-evening Dependabot schedule.

**Architecture:** Watchtower runs in `--monitor-only` mode (no restarts, just emails). Dependabot already opens weekly Docker digest PRs. Shifting Dependabot to Friday 18:00 America/Chicago makes watchtower's sole remaining value (update notification) redundant. Removing watchtower eliminates the only docker.sock mount in the stack. Cleanup touches: `monitoring/compose.yml`, `monitoring/.env.example`, `.env.example`, `.github/dependabot.yml`, the backup/restore/recreate scripts, the socket-mount-validation skill references, and `todo-security-audit.md`.

**Tech Stack:** Docker Compose YAML, GitHub Actions Dependabot config

---

### Task 1: Update Dependabot schedule to Friday evening

**Files:**
- Modify: `.github/dependabot.yml`

- [ ] **Step 1: Change schedule day and time**

Replace the contents of `.github/dependabot.yml` with:

```yaml
version: 2
updates:
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "friday"
      time: "18:00"
      timezone: "America/Chicago"
    open-pull-requests-limit: 10
    labels:
      - "dependencies"
      - "docker"
```

- [ ] **Step 2: Verify the file looks correct**

Run:
```bash
cat .github/dependabot.yml
```
Expected: `day: "friday"` and `time: "18:00"` present.

- [ ] **Step 3: Commit**

```bash
git add .github/dependabot.yml
git commit -m "chore: move Dependabot Docker updates to Friday 18:00 CT

Replacing watchtower monitor-only email alerts with weekly PR notification."
```

---

### Task 2: Remove watchtower from monitoring/compose.yml

**Files:**
- Modify: `monitoring/compose.yml`

The current `watchtower` service block (lines 8–28) is the entire service. Remove it, and also remove `DOCKER_GID` from the env — no other service in this file uses it.

- [ ] **Step 1: Delete the watchtower service block**

The file after removal should start with `prometheus` as the first service. Replace the top of the file so it reads:

```yaml
---
x-logging: &default-logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

services:
  prometheus:
```

The rest of the file (prometheus through grafana, networks, volumes) is unchanged.

- [ ] **Step 2: Validate YAML**

```bash
docker compose -f monitoring/compose.yml config --quiet
```
Expected: no output, exit code 0.

- [ ] **Step 3: Commit**

```bash
git add monitoring/compose.yml
git commit -m "fix: remove watchtower service and docker.sock mount

Eliminates the only docker.sock access in the stack. Update detection
is now handled solely by Dependabot weekly PRs."
```

---

### Task 3: Clean up watchtower env vars from .env.example files

**Files:**
- Modify: `.env.example`
- Modify: `monitoring/.env.example`

- [ ] **Step 1: Remove watchtower vars from root `.env.example`**

Delete these lines from `.env.example`:

```
# Watchtower email notifications
email=
gmail_app_passwd=
WATCHTOWER_NOTIFICATION_EMAIL_FROM=
WATCHTOWER_NOTIFICATION_EMAIL_TO=
WATCHTOWER_NOTIFICATION_EMAIL_SERVER=smtp.gmail.com
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PORT=587
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_USER=
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PASSWORD=
WATCHTOWER_NOTIFICATION_EMAIL_DELAY=2
```

And delete this line (near the bottom):
```
# Host docker group ID for non-root Watchtower daemon access
DOCKER_GID=
```

- [ ] **Step 2: Remove watchtower vars from `monitoring/.env.example`**

The file currently contains:
```
DOCKER_GID=

# Watchtower email notifications
email=
gmail_app_passwd=
```

Replace the entire file contents with an empty file (these vars are only for watchtower — nothing else in the monitoring stack needs them). If any non-watchtower vars are present, keep those; remove only the watchtower-specific ones.

Run to check:
```bash
cat monitoring/.env.example
```

- [ ] **Step 3: Commit**

```bash
git add .env.example monitoring/.env.example
git commit -m "chore: remove watchtower env vars from .env.example files"
```

---

### Task 4: Remove watchtower from backup/restore/recreate scripts

**Files:**
- Modify: `scripts/linux/backup/backup-volumes.sh` — remove the `backup_volume media-stack_watchtower_data` line and its comment
- Modify: `scripts/linux/restore/restore-volumes.sh` — remove the `restore_volume media-stack_watchtower_data` line
- Modify: `scripts/linux/maintenance/recreate_volumes_safely.sh` — remove `"media-stack_watchtower_data"` from the array

Watchtower has no declared volume in `monitoring/compose.yml` and `docker volume ls` confirms `media-stack_watchtower_data` does not exist on the host. These are dead references.

- [ ] **Step 1: Remove from backup-volumes.sh**

In `scripts/linux/backup/backup-volumes.sh`, delete:
```bash
# Watchtower
backup_volume media-stack_watchtower_data   /data            media-stack_watchtower_data.tar.gz
```

- [ ] **Step 2: Remove from restore-volumes.sh**

In `scripts/linux/restore/restore-volumes.sh`, delete:
```bash
restore_volume media-stack_watchtower_data   /data            watchtower_data.tar.gz
```

- [ ] **Step 3: Remove from recreate_volumes_safely.sh**

In `scripts/linux/maintenance/recreate_volumes_safely.sh`, delete:
```
    "media-stack_watchtower_data"
```

- [ ] **Step 4: Verify no remaining watchtower references in scripts**

```bash
grep -r "watchtower" scripts/ --include="*.sh"
```
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add scripts/linux/backup/backup-volumes.sh scripts/linux/restore/restore-volumes.sh scripts/linux/maintenance/recreate_volumes_safely.sh
git commit -m "chore: remove dead watchtower volume references from backup/restore scripts"
```

---

### Task 5: Remove watchtower from socket-mount-validation skill references

**Files:**
- Modify: `.github/skills/socket-mount-validation/references/usage-examples.md`
- Modify: `.github/skills/socket-mount-validation/references/functional-socket-checks.md`
- Modify: `.github/skills/socket-mount-validation/scripts/test-socket-access.sh`

These files document watchtower as the canonical example of a socket-mount consumer. Update them to reflect that no service in the stack currently mounts docker.sock.

- [ ] **Step 1: Read each file to understand scope**

```bash
grep -n "watchtower" \
  .github/skills/socket-mount-validation/references/usage-examples.md \
  .github/skills/socket-mount-validation/references/functional-socket-checks.md \
  .github/skills/socket-mount-validation/scripts/test-socket-access.sh
```

- [ ] **Step 2: Update references**

For each file, replace watchtower-specific prose or commands with a note that the stack currently has no docker.sock mounts, and the skill is retained for future use if a socket-mount service is re-added. Concretely:

In `usage-examples.md` and `functional-socket-checks.md`: remove or update any sentence that treats watchtower as a current example. Add a note: "As of 2026-04-23, no service in this stack mounts docker.sock. This skill applies if a socket-mount service is added in future."

In `test-socket-access.sh`: if the script targets a specific container name (`watchtower`), generalize it to accept a container name argument, or update the default to empty/none with a comment explaining there is no current socket-mount service.

- [ ] **Step 3: Verify**

```bash
grep -r "watchtower" .github/skills/socket-mount-validation/
```
Expected: no output (or only comments explaining historical context).

- [ ] **Step 6: Commit**

```bash
git add .github/skills/socket-mount-validation/
git commit -m "docs: update socket-mount-validation skill — no services currently mount docker.sock"
```

---

### Task 6: Stop and remove the running watchtower container, mark audit complete

- [ ] **Step 1: Stop and remove the watchtower container**

```bash
docker compose -f monitoring/compose.yml down watchtower
```
Expected: `Container watchtower  Stopped` then `Removed`.

- [ ] **Step 2: Confirm container is gone**

```bash
docker ps -a --filter name=watchtower
```
Expected: empty table (no watchtower container listed).

- [ ] **Step 3: Confirm no docker.sock mounts remain in any running container**

```bash
docker inspect $(docker ps -q) --format '{{.Name}}: {{range .Mounts}}{{if eq .Source "/var/run/docker.sock"}}SOCK{{end}}{{end}}' 2>/dev/null | grep SOCK
```
Expected: no output.

- [ ] **Step 4: Mark the audit item complete**

In `todo-security-audit.md`, change:
```
- [ ] **`watchtower` — docker.sock access is a container escape vector**
```
to:
```
- [x] **`watchtower` — docker.sock access is a container escape vector**
  - **Resolution**: Watchtower removed entirely (2026-04-23). Was running `--monitor-only`; Dependabot now handles update detection via weekly PRs (Friday 18:00 CT). No service in the stack mounts docker.sock.
```

Also update the `✅ Already Hardened` section — remove the watchtower bullet (`watchtower — non-root, --monitor-only`) since the service no longer exists.

- [ ] **Step 5: Commit**

```bash
git add todo-security-audit.md
git commit -m "chore: mark watchtower docker.sock audit item resolved"
```
