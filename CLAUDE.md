# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

### Start / update all stacks
```bash
bash scripts/linux/update-compose.sh
```

### Operate on a single stack
```bash
cd <stack-dir>          # e.g. arr-stack, monitoring, nginx-proxy …
docker compose up -d
docker compose logs -f [service]
docker compose restart [service]
```

### Run full regression suite
```bash
bash scripts/linux/run-regression-tests.sh
```

Runs six suites in order:
| Suite | Script | Needs containers? |
|---|---|---|
| Compose config validation | `test-compose-config.sh` | No |
| Env var completeness | `test-env-completeness.sh` | No |
| Nginx proxy domain regression | `Dockerfile.tests` container | Yes |
| Volume permission regression | `test-volume-permissions.sh` | Yes |
| VPN namespace/connectivity | `test-vpn-namespace-connectivity.sh` | Yes |
| Container health/reachability | `test-container-health-reachability.sh` | Yes |

Each suite writes a log to the project root (e.g. `compose-config.log`, `env-completeness.log`, `test.log`).

### Run Tier 1 static checks only (no containers required)
```bash
bash scripts/linux/test-compose-config.sh
bash scripts/linux/test-env-completeness.sh
```

### Run nginx proxy regression tests standalone
```bash
# From project root (uses nginx-proxy compose project)
docker compose -f nginx-proxy/compose.yml build tests
docker compose -f nginx-proxy/compose.yml run --rm -T tests

# Single domain only
docker compose -f nginx-proxy/compose.yml run --rm -T -e TEST_DOMAIN=jellyfin.example.com tests
```

### Run a manual backup
```bash
bash scripts/linux/backup-all.sh
```

### Check volume permissions
```bash
bash scripts/linux/test-volume-permissions.sh
```

## Architecture

### Modular Compose stacks
The project is split into seven independent stacks, each with its own `compose.yml` and local `.env`:

| Directory | Contents |
|-----------|----------|
| `nginx-proxy/` | Nginx Proxy Manager + regression test container |
| `jellyfin/` | Jellyfin media server |
| `arr-stack/` | Gluetun VPN, qBittorrent, Prowlarr, Radarr, Sonarr, Bazarr, FlareSolverr, Decluttarr, qBittorrent-metrics |
| `immich/` | Immich server, ML worker, Redis, Postgres |
| `lan-apps/` | Actual Budget, Pinchflat, Plex, Home Assistant |
| `proxied-apps/` | Audiobookshelf, DerbyNet, Minecraft (Survival + Creative) |
| `monitoring/` | Prometheus, Grafana, cAdvisor, node-exporter, Watchtower |

All stacks are enumerated in `scripts/linux/media-stack-compose.sh` (`MODULAR_STACK_NAMES`). That library provides `compose_cmd_for_stack`, `active_stack_names`, and helpers used by every operational script — import it with `source "${SCRIPT_DIR}/media-stack-compose.sh"` rather than rewriting the lookup logic.

### Networking
- `media_proxy` is a pre-existing external Docker network. Every stack that needs NPM reverse-proxy access must join it.
- `monitoring_internal` is an internal-only network inside the `monitoring` stack — exporters are never exposed to the host.
- All `arr-stack` services (qBittorrent, Prowlarr, Radarr, Sonarr, Bazarr, FlareSolverr) share Gluetun's network namespace via `network_mode: "service:vpn"`. Inter-service communication uses `127.0.0.1`.

### Named volumes
All named volumes are declared `external: true` and carry the `media-stack_` prefix (e.g. `media-stack_prowlarr_data`). This prefix comes from the original monolithic `COMPOSE_PROJECT_NAME=media-stack` and must be preserved to avoid data loss. New volumes in modular stacks follow the same pattern.

### Environment files
- Root `.env` / `.env.example` — shared host paths, VPN credentials, API keys, Immich DB settings, Watchtower email, backup tuning.
- Each stack directory also has its own `.env` / `.env.example` for stack-specific overrides. All live `.env` files are gitignored.
- All variable names use `UPPER_SNAKE_CASE` regardless of whether they are stack-defined or app-required.

### Test suite

The full regression suite is run by `scripts/linux/run-regression-tests.sh` and is also executed daily at 03:00 UTC via GitHub Actions (`.github/workflows/ci.yml`).

**Tier 1 — Static (no containers required):**
- `test-compose-config.sh` — validates all `compose.yml` files parse correctly using `docker compose config --no-interpolate`
- `test-env-completeness.sh` — verifies every `${VAR}` referenced in a `compose.yml` is defined in that stack's `.env.example`

**Tier 2 — Live (requires running containers):**
- Nginx proxy domain regression — `Dockerfile.tests` container queries NPM's SQLite database for enabled proxy hosts and probes each via curl; baselines live in `nginx-proxy/config/nginx-proxy-regression-baseline.json`
- Volume permission regression — `test-volume-permissions.sh`
- VPN namespace/connectivity — `test-vpn-namespace-connectivity.sh`
- Container health/reachability — `test-container-health-reachability.sh`

**CI:** Tier 1 runs on `ubuntu-latest` (GitHub-hosted). Tier 2 runs on the `self-hosted` runner at `/mnt/samsung/Docker/MediaServer` where live `.env` files and containers are present. Scheduled runs fire against `main`; the schedule does not activate on feature branches until merged.

### Backup system
`scripts/linux/backup-all.sh` (runs weekly via cron, Sundays 03:00) backs up all named Docker volumes and bind-mounted app data as `.tar.gz` archives under `vol_bkup/YYYYMMDD-NNN/`. Retains the three most recent sets. Immich Postgres is dumped via `pg_dumpall`. Immich photo/video uploads are excluded due to size. Compression is tunable via `BACKUP_GZIP_LEVEL` and `BACKUP_COMPRESSOR` in root `.env`.

## Naming Conventions

| Artifact | Convention | Example |
|----------|-----------|---------|
| All `.env` variables | `UPPER_SNAKE_CASE` | `QBITTORRENT_DOWNLOADS` |
| Service names / `container_name` | `kebab-case` | `minecraft-survival` |
| Named volume keys | `lower_snake_case` + `_data` suffix | `prowlarr_data` |
| Scripts in `scripts/linux/` | `kebab-case` | `backup-all.sh` |
| Backup set directories | `YYYYMMDD-NNN` | `20260419-001` |
