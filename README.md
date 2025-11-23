# media-stack (Media Stack)

A comprehensive Docker Compose setup for a home media server with automated backups, *arr stack, streaming services, and more.

## 📋 Table of Contents

- [Services Included](#services-included)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Backup & Restore](#backup--restore)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)

## 🎬 Services Included

### Media Management
- **Nginx Proxy Manager** - Reverse proxy with SSL management (Port 81)
- **Jellyfin/Plex** - Media streaming servers
- **Audiobookshelf** - Audiobook and podcast server (Port 13378)

### Download Automation (*arr Stack)
- **Prowlarr** - Indexer manager (Port 9696)
- **Radarr** - Movie management (Port 7878)
- **Sonarr** - TV show management (Port 8989)
- **Bazarr** - Subtitle management (Port 6767)
- **qBittorrent** - Torrent client (Port 8080)
- **Decluttarr** - Queue cleanup (see details below)

### Additional Services
- **Gluetun VPN** - VPN container for *arr services
- **Immich** - Photo management (Port 2283)
- **Pinchflat** - YouTube downloader (Port 8945)
- **Focalboard** - Project management (Port 8046)
- **Actual Budget** - Budget tracking (Port 5006)
- **DerbyNet** - Pinewood derby race management (Port 8050)
- **Watchtower** - Automatic container updates



## 🔧 Prerequisites

### Required Software
- **Docker Desktop** - [Download for Windows](https://www.docker.com/products/docker-desktop/)
- **PowerShell 5.1+** - Included with Windows 10/11
- **Git** - [Download](https://git-scm.com/downloads)

### System Requirements
- Windows 10/11 (64-bit)
- Minimum 8GB RAM (16GB+ recommended)
- Sufficient storage for media files and Docker volumes

## 🚀 Quick Start

### 1. Clone the Repository

```powershell
git clone https://github.com/PorkChopExpress86/media-stack.git
cd media-stack
```

### 2. Create Environment File

Copy the example environment file and configure your settings:

```powershell
Copy-Item .env.example .env
notepad .env
```

### 3. Configure Environment Variables

Edit `.env` with your specific paths and credentials. See [Configuration](#configuration) for details.

### 4. Start Services

```powershell
docker compose up -d
```

### 5. Access Services

- **Nginx Proxy Manager**: http://localhost:81
  - Default credentials: `admin@example.com` / `changeme`
- **Audiobookshelf**: http://localhost:13378
- **Immich**: http://localhost:2283
- **Pinchflat**: http://localhost:8945
- **Actual Budget**: http://localhost:5006
- **Focalboard**: http://localhost:8046
- **DerbyNet**: http://localhost:8050

*arr services are accessible through VPN container ports (Prowlarr: 9696, Radarr: 7878, Sonarr: 8989, etc.)

## ⚙️ Configuration

### Required Environment Variables

Create a `.env` file based on `.env.example` with the following variables:

#### Media Paths
```bash
movies=/path/to/movies
tv_shows=/path/to/tv_shows
other_movies=/path/to/other_movies
other_shows=/path/to/other_shows
kids_movies=/path/to/kids_movies
kids_tv_shows=/path/to/kids_tv_shows
music=/path/to/music
books=/path/to/books
podcasts=/path/to/podcasts
audiobooks=/path/to/audiobooks
qbittorrent_downloads=/path/to/downloads
pinchflat_downloads=/path/to/youtube_downloads
```

#### VPN Configuration
```bash
vpn_username=your_pia_username
vpn_password=your_pia_password
```

#### Immich Configuration
```bash
UPLOAD_LOCATION=/path/to/immich/uploads
DB_DATA_LOCATION=/path/to/immich/postgres
DB_PASSWORD=secure_random_password
IMMICH_VERSION=release
```

#### Watchtower Email Notifications
```bash
email=your@email.com
gmail_app_passwd=your_gmail_app_password
```

#### Optional
```bash
plex_claim=claim-xxxxxxxxxxxx
local_ip=192.168.1.xxx
```

### Timezone Configuration

The compose file uses `TZ=America/Chicago`. Update this in `docker-compose.yaml` to match your timezone:

```yaml
environment:
  - TZ=America/New_York  # Use IANA timezone format
```

Find your timezone: [List of TZ Database Time Zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)

## 🛠 Development: Git hooks (optional but recommended)

Add the repository git hooks path so commits will run a quick `yamllint` check
for `docker-compose.yaml` before committing. This helps avoid syntax/style
errors that would break deployments.

Enable hooks locally with:

```powershell
git config core.hooksPath .githooks
```

What the hook does:
- If `docker-compose.yaml` is staged for commit, the pre-commit script runs
   `yamllint` (via Docker) and aborts the commit if linting fails.

Notes:
- This is optional; enabling the hooks is a local step (not enforced by GitHub).
- On Windows PowerShell you may need Git Bash or a POSIX-compatible shell for
   the hook to run as written. Alternatively, run the yamllint container manually:

```powershell
docker run --rm -v "${PWD}:/work" -w /work cytopia/yamllint:latest docker-compose.yaml
```


## Decluttarr (details)

Decluttarr is an automated cleanup tool for the *arr stack that removes stalled,
failed or slow downloads and optionally triggers re-searches in Radarr/Sonarr.

Recommended: use Decluttarr V2 config (supports multiple instances and improved
settings). You can supply settings via a `config.yaml` mounted into the
container or inline in `docker-compose.yml` using the V2 multiline format.

Minimal inline snippet (V2 style):

```yaml
decluttarr:
   image: ghcr.io/manimatter/decluttarr:latest
   environment:
      RADARR: >
         - base_url: "http://vpn:7878"
            api_key: "${RADARR_API_KEY}"
      SONARR: >
         - base_url: "http://vpn:8989"
            api_key: "${SONARR_API_KEY}"
      QBITTORRENT: >
         - base_url: "http://vpn:8080"
            username: "${QBITTORRENT_USER}"
            password: "${QBITTORRENT_PASS}"
```

Put API keys and qBittorrent credentials in your `.env` (`RADARR_API_KEY`,
`SONARR_API_KEY`, `PROWLARR_API_KEY`, `QBITTORRENT_USER`, `QBITTORRENT_PASS`).

Check activity and troubleshooting with:

```powershell
docker logs decluttarr -f
```

Note: If you enable `detect_deletions`, mount the same media paths into
Decluttarr so it can access them; otherwise that job will warn and be skipped.

## 💾 Backup & Restore

### Automated Backups

#### Create a Backup

Back up all Docker volumes to compressed archives:

```powershell
.\scripts\backup-volumes.ps1
```

**Options:**
- `-BackupDir "D:\backups"` - Specify custom backup location
- `-WhatIf` - Preview without executing
- `-ComposeVolumes` - Back up only volumes defined in docker-compose.yaml

**Example:**
```powershell
# Full backup to custom directory
.\scripts\backup-volumes.ps1 -BackupDir "D:\media-stack-backups"

# Preview backup operation
.\scripts\backup-volumes.ps1 -WhatIf

# Backup only compose volumes
.\scripts\backup-volumes.ps1 -ComposeVolumes
```

Backups are stored as `.tar.gz` files in `vol_bkup/` by default.

#### Restore Single Volume

Restore a specific volume from backup:

```powershell
.\scripts\restore-volume.ps1
```

**Options:**
- `-BackupDir "D:\backups"` - Specify backup location
- `-Force` - Clear existing volume data before restore
- `-WhatIf` - Preview without executing

**Example:**
```powershell
# Restore all volumes
.\scripts\restore-volumes.ps1

# Force restore (clears existing data)
.\scripts\restore-volumes.ps1 -Force

# Preview restore
.\scripts\restore-volumes.ps1 -WhatIf
```

⚠️ **Warning:** Use `-Force` carefully as it will delete existing data!

#### Restore All Volumes

Restore all volumes from backup directory:

```powershell
.\scripts\restore-volumes.ps1
```

This script will:
1. Find all `.tar.gz` backups in the backup directory
2. Create volumes if they don't exist
3. Restore data from archives
4. Report success/failure for each volume

### Backup Best Practices

1. **Stop Containers First** (recommended for database-heavy services):
   ```powershell
   docker compose stop
   .\scripts\backup-volumes.ps1
   docker compose start
   ```

2. **Schedule Regular Backups** using Windows Task Scheduler:
   - Open Task Scheduler
   - Create Basic Task
   - Set trigger (e.g., daily at 3 AM)
   - Action: Start a program
   - Program: `powershell.exe`
   - Arguments: `-File "C:\Users\Blake\Docker\media-stack\scripts\backup-volumes.ps1"`

3. **Store Backups Off-Site** - Copy `vol_bkup/` to external drive or cloud storage

4. **Test Restores Regularly** - Verify backups work before you need them

## 🔄 Maintenance

### Update Containers

Update all containers to latest versions:

```powershell
.\update-containers.ps1
```

This script will:
1. Pull latest images
2. Restart only containers with updates
3. Remove old images
4. Log all actions to `file.log`

**Watchtower** also runs automatic updates every 6 hours.

### Manual Update

```powershell
# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d

# Clean up old images
docker image prune -af
```

### View Logs

```powershell
# All services
docker compose logs -f

# Specific service
docker compose logs -f radarr

# Last 100 lines
docker compose logs --tail=100 sonarr
```

### Restart Services

```powershell
# All services
docker compose restart

# Specific service
docker compose restart immich_server
```

### Stop/Start Services

```powershell
# Stop all
docker compose stop

# Start all
docker compose start

# Stop specific service
docker compose stop vpn
```

## 🐛 Troubleshooting

### Container Won't Start

1. Check logs:
   ```powershell
   docker compose logs <container_name>
   ```

2. Verify environment variables:
   ```powershell
   docker compose config
   ```

3. Check volume mounts exist:
   ```powershell
   docker volume ls
   docker volume inspect <volume_name>
   ```

### VPN Issues

If *arr services can't connect:

1. Check VPN container is running:
   ```powershell
   docker compose logs vpn
   ```

2. Verify VPN credentials in `.env`

3. Check forwarded port:
   ```powershell
   docker exec vpn cat /gluetun/piaportforward.json
   ```

### Port Conflicts

If ports are already in use:

1. Find process using port:
   ```powershell
   netstat -ano | findstr :<port>
   ```

2. Either stop that process or change port in `docker-compose.yaml`

### Immich Database Issues

If Immich won't start:

1. Check postgres logs:
   ```powershell
   docker compose logs database
   ```

2. Verify database password in `.env`

3. Try recreating database container:
   ```powershell
   docker compose stop database
   docker compose rm database
   docker compose up -d database
   ```

### Backup/Restore Issues

**Problem:** "Container not found" during backup

**Solution:** Container must exist (running or stopped):
```powershell
docker compose up -d
docker compose stop  # Optional: stop for consistency
.\scripts\backup-volumes.ps1
```

**Problem:** Restore fails with "Permission denied"

**Solution:** Run PowerShell as Administrator or ensure Docker Desktop has proper permissions

### Out of Disk Space

Check Docker disk usage:

```powershell
docker system df

# Clean up
docker system prune -a --volumes
```

⚠️ **Warning:** This removes all unused containers, images, and volumes!

## 📁 Project Structure

```
media-stack/
├── docker-compose.yaml      # Main compose file
├── .env                      # Environment variables (not in git)
├── .env.example             # Template for .env
├── update-containers.ps1    # Container update script
├── file.log                 # Update log file
├── hwaccel.*.yml            # Hardware acceleration configs
├── scripts/                 # Utility scripts
│   ├── backup-volumes.ps1   # Backup script
│   ├── restore-volume.ps1   # Single restore script
│   ├── restore-volumes.ps1  # Batch restore script
│   └── *.sh                 # Legacy bash scripts
├── vol_bkup/               # Backup archives
├── audiobookshelf_data/    # Bind mount directories
├── budget_data/
└── derbynet_data/
```

## 🔒 Security Considerations

1. **Never commit `.env` file** - Contains sensitive credentials
2. **Change default passwords** - Especially Nginx Proxy Manager, Immich
3. **Use VPN** - Already configured for *arr services
4. **Regular updates** - Watchtower handles this automatically
5. **Firewall** - Only expose necessary ports to external network
6. **Backups** - Store encrypted backups off-site

## 📚 Additional Resources

- [Docker Documentation](https://docs.docker.com/)
- [Immich Documentation](https://immich.app/docs)
- [Gluetun VPN Wiki](https://github.com/qdm12/gluetun/wiki)
- [Audiobookshelf Docs](https://www.audiobookshelf.org/docs)
- [Servarr Wiki](https://wiki.servarr.com/)

## 📝 License

This configuration is provided as-is for personal use.

## 🤝 Contributing

Contributions welcome! Please open an issue or pull request.

## 📧 Support

For issues or questions, please open a GitHub issue.

---

**Last Updated:** October 2025
