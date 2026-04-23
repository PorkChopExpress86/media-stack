# media-stack (Media Stack)

A comprehensive Docker Compose setup for a home media server with automated backups, *arr stack, streaming services, monitoring, and more.

## 📋 Table of Contents

- [Services](#services-included)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Naming Standard](#naming-standard)
- [Project Layout](#project-layout)
- [Backup & Restore](#backup--restore)
- [Maintenance](#maintenance)
- [Monitoring](#monitoring)

## 🎬 Services Included

| Category | Service | Port |
|----------|---------|------|
| **Reverse Proxy** | Nginx Proxy Manager | 80, 443, 81 (admin, localhost only) |
| **Media Streaming** | Jellyfin | 8096 |
| | Plex | 32400 |
| | Audiobookshelf | 13378 |
| | Pinchflat (YouTube) | 8945 |
| **Arr Stack** | Prowlarr | 9696 (via VPN) |
| | Radarr | 7878 (via VPN) |
| | Sonarr | 8989 (via VPN) |
| | Bazarr | 6767 (via VPN) |
| | qBittorrent | 8080 (via VPN) |
| | FlareSolverr | internal only (via VPN namespace) |
| | Decluttarr | — |
| **Photos** | Immich | 2283 |
| **Home Automation** | Home Assistant | 8123 (host network) |
| **Gaming** | Minecraft Bedrock (Survival) | 19132/udp (via NPM) |
| | Minecraft Bedrock (Creative) | 19133/udp (via NPM) |
| **Finance** | Actual Budget | 5006 |
| **Other** | DerbyNet | 8050 |
| **VPN** | Gluetun (PIA) | — |
| **Auto-Updates** | Watchtower | — |
| **Monitoring** | Prometheus | internal only |
| | Grafana | 3000 |
| | cAdvisor | internal only |
| | Node Exporter | internal only |
| | Exportarr (Sonarr, Radarr, Prowlarr) | internal only |

## 🔧 Prerequisites

- Linux host (Ubuntu/Debian recommended), Docker Engine, Docker Compose v2
- 8GB+ RAM, storage for media libraries
- (Optional) GPU with `/dev/dri` for hardware transcoding

## 🚀 Quick Start

```bash
git clone https://github.com/PorkChopExpress86/media-stack.git
cd media-stack
cp .env.example .env
# Edit .env with your paths and credentials
nano .env
docker compose up -d
```

**Access:** Nginx Proxy Manager (`http://localhost:81`, default: `admin@example.com`/`changeme`), Jellyfin (8096), Immich (2283), *arr services via VPN ports

## ⚙️ Configuration

Edit `.env` with your paths and credentials:

| Category | Variables |
|----------|-----------|
| **Media paths** | `movies`, `tv_shows`, `kids_movies`, `kids_tv_shows`, `other_movies`, `other_shows`, `music`, `audiobooks`, `podcasts`, `home_movies` |
| **Downloads** | `qbittorrent_downloads`, `pinchflat_downloads` |
| **VPN** | `vpn_username`, `vpn_password` (PIA) |
| **Immich** | `UPLOAD_LOCATION`, `DB_DATA_LOCATION`, `DB_PASSWORD` |
| **Arr API keys** | `RADARR_API_KEY`, `SONARR_API_KEY`, `PROWLARR_API_KEY` |
| **qBittorrent** | `QBITTORRENT_USER`, `QBITTORRENT_PASS` |
| **Grafana** | `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD` |
| **Notifications** | `email`, `gmail_app_passwd` |
| **Other** | `jellyfin_url`, `plex_claim`, `TZ` |

See `.env.example` for the full list with defaults.

### Naming Standard

Use these naming rules for consistency across `.env`, `docker-compose.yaml`, scripts, and backup artifacts:

- **Stack-defined `.env` variables:** use `lower_snake_case`.
	- Examples: `qbittorrent_downloads`, `kids_tv_shows`, `vpn_username`, `jellyfin_url`
- **Upstream/app-required `.env` variables:** keep `UPPER_SNAKE_CASE` exactly as expected by images/apps.
	- Examples: `COMPOSE_PROJECT_NAME`, `RADARR_API_KEY`, `TZ`, `UPLOAD_LOCATION`, `DB_PASSWORD`
- **Service names and `container_name` values (Compose):** use lowercase; use `kebab-case` for multi-word names.
	- Examples: `minecraft-survival`, `minecraft-creative`, `immich-server`
- **Named volume keys (Compose):** use `lower_snake_case` and prefer `_data` suffix for persistent app data.
	- Examples: `prowlarr_data`, `qbittorrent_data`, `immich_server_data`
	- Keep existing legacy names as-is (for example `model-cache`) unless doing a planned migration.
- **Script filenames:** use `kebab-case` for operational scripts in `scripts/linux/`.
	- Examples: `backup-all.sh`, `restore-volumes.sh`, `qb-port-sync.sh`
- **Documentation filenames in `scripts/`:** use `kebab-case` for project-maintained guides.
	- Examples: `immich-backup-guide.md`, `restore-guide.md`
- **Backup set directories:** use date-plus-sequence format `YYYYMMDD-NNN`.
	- Example: `20260419-001`
- **Compatibility rule:** prefer these standards for all new names; do not rename existing variables/files already wired into Compose or automation unless migration is explicitly planned.

#### Examples

```text
# .env variables
qbittorrent_downloads=/mnt/media/qb
vpn_username=your_user
RADARR_API_KEY=xxxxxxxxxxxxxxxx
WATCHTOWER_NOTIFICATION_EMAIL_SERVER=smtp.gmail.com

# files
scripts/linux/qb-port-sync.sh
scripts/linux/backup-all.sh
scripts/immich-backup-guide.md
scripts/restore-guide.md
vol_bkup/20260419-001/
```

### qBittorrent + Gluetun Port Auto-Sync

This stack uses Gluetun's native port-forward hooks to keep qBittorrent's listening port aligned with the currently forwarded VPN port.

- Gluetun runs up/down hook commands when VPN port forwarding is established or torn down.
- The hook script updates qBittorrent over `http://127.0.0.1:8080/api/v2/app/setPreferences`.
- qBittorrent peer-port host mappings are intentionally **not** fixed in Compose; the VPN-assigned forwarded port is authoritative.

Required qBittorrent setting:

- **Web UI → Authentication → "Bypass authentication for clients on localhost"** must be enabled (`bypass_local_auth=true`).

Other required assumptions:

- qBittorrent Web UI remains enabled on port `8080`.
- qBittorrent and Gluetun share the same network namespace (`network_mode: "service:vpn"`).

Troubleshooting:

- Check Gluetun logs first: `docker compose logs -f vpn`.
- Verify hook output lines prefixed with `[qb-port-sync]` (shows before/after `listen_port` and interface).
- If the hook cannot reach qBittorrent, confirm WebUI is still on `8080` and localhost-auth bypass is enabled.
- On reconnect, the forwarded port can change; this is expected and should be re-applied automatically.
- If needed, restart just the shared namespace pair: `docker compose restart vpn qbittorrent`.

### FlareSolverr + Prowlarr

`flaresolverr` is included for Cloudflare-protected torrent indexers such as `1337x`.

- The container shares Gluetun's network namespace with the *arr stack using `network_mode: "service:vpn"`.
- In Prowlarr, set **Settings → Indexers → FlareSolverr URL** to `http://127.0.0.1:8191`.
- FlareSolverr-compatible indexers (auto-routed when tagged):
	- `1337x` (definition: `1337x`)
	- `EZTV` (definition: `eztv`)
	- `kickasstorrents.ws` (definition: `kickasstorrents-ws`)
- After enabling any FlareSolverr-protected indexer, run **Test** from Prowlarr to confirm connectivity.
- If FlareSolverr or Gluetun is restarted, Prowlarr may need a quick re-test on affected indexers.

## 🗂️ Project Layout

This repository is organized by function so day-to-day operations are easier to navigate:

- `docker-compose.yaml` — primary stack definition.
- `.env` / `.env.example` — runtime secrets and environment configuration template.
- `scripts/linux/` — operational Linux scripts (backup, restore, update, maintenance).
- `scripts/windows/` — PowerShell equivalents for Windows-based operations.
- `scripts/` — shared helper scripts and operational guides.
- `docs/` — project documentation for operational workflows and feature-specific guides.
- `config/` — service-specific static configuration (Prometheus, Grafana, hardware accel snippets).
- `data/` — bind-mounted application data directories.
- `vol_bkup/` — date-stamped backup sets (`YYYYMMDD-NNN`).

Organization conventions:

- New automation scripts should go in `scripts/linux/` or `scripts/windows/`.
- New operations documentation should live in `scripts/` and follow naming standards.
- Keep service-specific static config in `config/<service>/`.

## 💾 Backup & Restore

### Automated Weekly Backup

A cron job runs `scripts/linux/backup-all.sh` every Sunday at 3:00 AM. It backs up:
- All named Docker volumes (config data for every service)
- Bind-mounted data (DerbyNet, Actual Budget, Minecraft worlds)
- Immich Postgres database (via `pg_dumpall`)

Backups are stored in `vol_bkup/` as `.tar.gz` archives. The 3 most recent weekly backup sets are retained (~3 weeks).

Compression and duration tuning:
- `BACKUP_GZIP_LEVEL` controls compression level (`1` = fastest/larger, `9` = slowest/smaller, default `6`).
- `BACKUP_COMPRESSOR` controls compressor choice: `auto` (default), `pigz`, or `gzip`.
- If `BACKUP_COMPRESSOR=auto` and `pigz` is installed on the host, the script auto-uses it for faster multi-core compression.
- `backup_report.txt` now includes per-item durations and throughput (MB/s), plus phase and total runtime summary.

```bash
# Set up the cron job (run once)
(crontab -l 2>/dev/null; echo "0 3 * * 0 /mnt/samsung/Docker/MediaServer/scripts/linux/backup-all.sh >> /mnt/samsung/Docker/MediaServer/vol_bkup/backup.log 2>&1") | crontab -

# Run a manual backup
bash scripts/linux/backup-all.sh

# Restore volumes from a backup
bash scripts/linux/restore-volumes.sh
```

> **Note:** Immich photo/video uploads (`UPLOAD_LOCATION`) are excluded from automated backup due to size. Back those up separately with rsync or your preferred tool.

### Legacy Windows Scripts

Windows PowerShell scripts are available in `scripts/windows/` for environments still running on Windows.

## 🔄 Maintenance

```bash
# Update containers manually
bash scripts/linux/update-compose.sh

# Or use individual docker compose commands
docker compose pull && docker compose up -d
docker compose logs -f [service]
docker compose restart [service]
```

### Regression test suite

A single script runs all regression checks in sequence and reports a combined pass/fail result.

```bash
bash scripts/linux/run-regression-tests.sh
```

To automate weekly runs, install the bundled systemd timer (runs every Sunday at 02:00):

```bash
sudo bash scripts/linux/install-regression-timer.sh
```

Check the timer status:

```bash
systemctl status media-stack-regression.timer
journalctl -u media-stack-regression.service --no-pager -n 50
```

Remove the timer:

```bash
sudo bash scripts/linux/install-regression-timer.sh uninstall
```

Unit files live in `scripts/linux/systemd/`. Both individual suites can still be run independently — see the sections below.

### Nginx proxy regression checks

Use the test service to verify enabled Nginx Proxy Manager domains still respond through the proxy after changes.

What it checks:

- Discovers enabled proxy hosts directly from Nginx Proxy Manager's `database.sqlite`
- Sends requests through the `nginx` container using the configured domain as the host/SNI value
- Treats only HTTP `200` and `401` as passing
- Treats checked-in baseline `302` redirects as passing when they match known-good login/app redirect targets
- Fails any response taking longer than 10 seconds
- Appends results to root-level `test.log`

Run the checks manually:

```bash
docker compose build tests
docker compose run --rm -T tests
```

Run a single domain only:

```bash
docker compose run --rm -T -e TEST_DOMAIN=jellyfin.ohmygoshwhatever.com tests
```

Run the scheduled wrapper manually:

```bash
bash scripts/linux/run-tests-scheduled.sh
```

`test.log` is ignored by git via the existing `*.log` rule in `.gitignore`.

Known-good redirect baselines are stored in `config/nginx-proxy-regression-baseline.json`.

### Volume permission regression check

Use the host-side volume permission regression script to confirm running containers can access their bind mounts and named Docker volumes with the expected read/write mode.

What it checks:

- inspects running compose-managed containers
- checks bind mounts and named Docker volumes only
- verifies the mount path exists inside the container
- verifies readable access for read-only mounts
- verifies readable and writable access for read-write mounts
- falls back to a helper container for shell-less images when the container user can be inferred numerically
- writes results to root-level `volume-permissions.log`

Run it manually:

```bash
bash scripts/linux/test-volume-permissions.sh
```

Watchtower checks for image updates every 6 hours and sends email notifications.

## 📊 Monitoring

Grafana dashboards are available at `http://<host>:3000` (login required — credentials set via `GRAFANA_ADMIN_USER`/`GRAFANA_ADMIN_PASSWORD` in `.env`).

Dashboards include:
- Container CPU & memory usage
- System memory & disk usage (per mount point)
- Container restart counts
- Network traffic (RX/TX)
- Sonarr/Radarr/Prowlarr stats and queue sizes

Prometheus retention is set to 15 days. Exporters and cAdvisor run on internal-only ports (not exposed to the host).

## 🔒 Security

- Change all default passwords (NPM, Grafana, Postgres)
- Keep `.env` private — it's excluded from git via `.gitignore`
- *arr services and qBittorrent route through Gluetun VPN
- NPM admin port (81) is bound to localhost only
- Grafana anonymous access is disabled
- Monitoring exporter ports are not exposed to the host network
- All containers have log rotation configured (10 MB × 3 files)

## 📚 Resources

[Docker](https://docs.docker.com/) • [Immich](https://immich.app/docs) • [Gluetun](https://github.com/qdm12/gluetun/wiki) • [Servarr Wiki](https://wiki.servarr.com/) • [Home Assistant](https://www.home-assistant.io/docs/)

---

**Last Updated:** February 2026
