# media-stack (Media Stack)

A comprehensive Docker Compose setup for a home media server with automated backups, *arr stack, streaming services, and more.

## 📋 Table of Contents

- [Services](#services-included)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Backup & Restore](#backup--restore)
- [Maintenance](#maintenance)

## 🎬 Services Included

**Media:** Nginx Proxy Manager (81), Jellyfin (8096), Audiobookshelf (13378)

***arr Stack:** Prowlarr (9696), Radarr (7878), Sonarr (8989), Bazarr (6767), qBittorrent (8080), Decluttarr

**Other:** Gluetun VPN, Immich (2283), Pinchflat (8945), Actual Budget (5006), DerbyNet (8050), Watchtower



## 🔧 Prerequisites

- Docker Desktop, PowerShell 5.1+, Git
- Windows 10/11 (64-bit), 8GB+ RAM, storage for media

## 🚀 Quick Start

```powershell
git clone https://github.com/PorkChopExpress86/media-stack.git
cd media-stack
Copy-Item .env.example .env
# Edit .env with your paths and credentials
docker compose up -d
```

**Access:** Nginx Proxy Manager (81, default: `admin@example.com`/`changeme`), Jellyfin (8096), Immich (2283), *arr services via VPN ports

## ⚙️ Configuration

Edit `.env` with your paths:
- Media paths: `movies`, `tv_shows`, `audiobooks`, `podcasts`, etc.
- VPN: `vpn_username`, `vpn_password` (PIA)
- Immich: `UPLOAD_LOCATION`, `DB_DATA_LOCATION`, `DB_PASSWORD`
- Optional: Email notifications, timezone (default: `America/Chicago`)

See `.env.example` for full list.



## 💾 Backup & Restore

```powershell
# Backup all volumes
.\scripts\backup-volumes.ps1

# Restore all volumes
.\scripts\restore-volumes.ps1

# Common options: -Force -StopContainersFirst -BackupDir "path" -WhatIf
```

Backups stored in `vol_bkup/` as `.tar.gz`. Schedule regular backups via Task Scheduler.

## 🔄 Maintenance

```powershell
# Update containers (or use Watchtower auto-updates)
.\update-containers.ps1

# Manual commands
docker compose pull && docker compose up -d
docker compose logs -f [service]
docker compose restart [service]
```





## 🔒 Security

Change default passwords, keep `.env` private, use VPN for *arr services, enable firewall.

## 📚 Resources

[Docker](https://docs.docker.com/) • [Immich](https://immich.app/docs) • [Gluetun](https://github.com/qdm12/gluetun/wiki) • [Servarr Wiki](https://wiki.servarr.com/)

---

**Last Updated:** December 2025
