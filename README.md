# media-stack (Media Stack)

A comprehensive Docker Compose setup for a home media server with automated backups, *arr stack, streaming services, monitoring, and more.

## 📋 Table of Contents

- [Services](#services-included)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
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

## 💾 Backup & Restore

### Automated Weekly Backup

A cron job runs `scripts/linux/backup-all.sh` every Sunday at 3:00 AM. It backs up:
- All named Docker volumes (config data for every service)
- Bind-mounted data (DerbyNet, Actual Budget, Minecraft worlds)
- Immich Postgres database (via `pg_dumpall`)

Backups are stored in `vol_bkup/` as `.tar.gz` archives. The 14 most recent backup sets are retained.

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
