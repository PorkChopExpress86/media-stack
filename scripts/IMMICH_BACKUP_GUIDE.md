# Immich Backup and Restore Guide

This guide provides scripts and instructions for backing up Immich on Windows and restoring it on Linux.

## 📋 Overview

Based on [Immich's official backup documentation](https://docs.immich.app/administration/backup-and-restore), these scripts implement the recommended 3-2-1 backup strategy:

- **Backup Script (PowerShell)**: Runs on Windows, backs up database + uploads to external drive
- **Restore Script (Bash)**: Runs on Linux, restores database + uploads to fresh Immich installation

## 🔑 Key Concepts

### What Gets Backed Up

1. **Database (PostgreSQL)**
   - All metadata, albums, user data, face recognition data
   - File paths and organization
   - **Critical**: Without the database, your photos are just unorganized files

2. **Upload Files** (Critical)
   - `upload/` - Original photos and videos uploaded via mobile/web
   - `profile/` - User profile images  
   - `library/` - External library assets (if Storage Template enabled)
   - `backups/` - Immich's automatic database dumps

3. **Generated Content** (Optional - can be regenerated)
   - `thumbs/` - Thumbnails and preview images
   - `encoded-video/` - Re-encoded videos for compatibility

### What's NOT Backed Up

- Docker volumes (database is dumped instead)
- Container state
- Generated thumbnails and transcoded videos (saves space, can be regenerated)

## 🪟 Windows Backup Script

### Usage

```powershell
# Basic usage (default paths from your docker-compose)
.\scripts\backup-immich.ps1

# Custom paths
.\scripts\backup-immich.ps1 `
    -BackupDestination "G:\Immich_Backups" `
    -UploadLocation "S:\Immich\upload" `
    -DatabaseContainer "immich_postgres" `
    -DatabaseUsername "postgres"

# Stop server during backup for consistency (recommended)
.\scripts\backup-immich.ps1 -StopServer $true
```

### What It Does

1. ✅ Creates timestamped backup directory
2. ✅ Dumps PostgreSQL database using `pg_dumpall`
3. ✅ Copies critical upload folders (library, upload, profile, backups)
4. ✅ Skips generated content to save space (thumbs, encoded-video)
5. ✅ Creates backup summary file
6. ✅ Optionally stops/starts server for consistent backup

### Output Structure

```
G:\Immich_Backups\
└── immich_backup_2026-01-23_174752\
    ├── database\
    │   └── immich-db-backup-2026-01-23_174752.sql.gz
    ├── uploads\
    │   ├── library\      # If using storage template
    │   ├── upload\       # Original photos/videos
    │   ├── profile\      # Profile pictures
    │   └── backups\      # Immich auto-backups
    └── BACKUP_INFO.txt   # Summary and instructions
```

### Requirements

- Docker Desktop for Windows
- PowerShell 5.1 or later
- Sufficient space on backup drive
- `gzip` available in PowerShell (install via `choco install gzip` if needed)

## 🐧 Linux Restore Script

### Prerequisites

Before running the restore:

1. **Fresh Immich Installation**
   - Install Docker and Docker Compose
   - Download Immich docker-compose.yml
   - Set environment variables in `.env`
   - Create containers but DON'T start them yet

2. **Copy Backup to Linux**
   ```bash
   # Example: copy from external drive
   cp -r /mnt/backup_drive/immich_backup_2026-01-23_174752 /tmp/
   ```

3. **Update Script Configuration**
   Edit the script variables to match your setup:
   ```bash
   IMMICH_COMPOSE_DIR="/opt/immich"           # Your docker-compose location
   UPLOAD_LOCATION="/mnt/immich/upload"       # Your UPLOAD_LOCATION from .env
   DB_CONTAINER="immich_postgres"             # Database container name
   DB_USERNAME="postgres"                     # Database username
   ```

### Usage

```bash
# Make script executable
chmod +x restore-immich.sh

# Run restore
sudo ./restore-immich.sh /path/to/immich_backup_2026-01-23_174752
```

### What It Does

1. ✅ Validates backup structure
2. ✅ Stops existing Immich services
3. ✅ Creates fresh Docker containers
4. ✅ Starts PostgreSQL only
5. ✅ Restores database dump (with search_path fix)
6. ✅ Restores upload files with rsync
7. ✅ Sets proper file permissions
8. ✅ Starts all Immich services

### Post-Restore Steps

After restore completes:

1. **Wait 2-3 minutes** for services to fully start
2. **Access Immich** web interface (http://your-server:2283)
3. **Verify data**:
   - Check that your photos are visible
   - Verify albums and shared links
   - Check user accounts

4. **Regenerate thumbnails** (since they weren't backed up):
   - Go to Administration → Jobs
   - Run "Generate Thumbnails" for all assets
   - Run "Transcode Videos" if needed

5. **Monitor logs** for any issues:
   ```bash
   cd /opt/immich
   docker compose logs -f immich-server
   ```

## 📝 Important Notes

### Backup Order (Per Immich Docs)

If you **cannot** stop the server:
1. Backup database **FIRST**
2. Backup filesystem **SECOND**

This ensures the worst case is orphaned files (which can be re-uploaded) rather than broken database references.

**Best practice**: Stop the server during backup using `-StopServer $true`

### Migration Checklist

When moving from Windows to Linux:

- [ ] Backup on Windows using `backup-immich.ps1`
- [ ] Verify backup completed successfully
- [ ] Copy backup to Linux server (external drive, network, etc.)
- [ ] Install fresh Immich on Linux
- [ ] Update `.env` with correct paths
- [ ] Run `restore-immich.sh`
- [ ] Verify photos and albums
- [ ] Regenerate thumbnails and transcoded videos
- [ ] Test uploads from mobile app
- [ ] Update mobile app server URL
- [ ] Decommission Windows server

### Database Compatibility

The backup uses `pg_dumpall` which is version-independent. You can restore to:
- Same PostgreSQL version
- Newer PostgreSQL version  
- Different Immich version (database will auto-migrate)

### File Permissions

The restore script sets ownership to `1000:1000` (default Immich user). If your setup uses different UIDs, modify:

```bash
chown -R 1000:1000 "$UPLOAD_LOCATION"
```

## 🚨 Troubleshooting

### "relation already exists" errors during restore

The database wasn't fresh. Solution:
```bash
cd /opt/immich
docker compose down -v
# Delete DB data location
rm -rf /path/to/DB_DATA_LOCATION
# Run restore again
```

### Server starts but photos don't appear

1. Check file permissions: `ls -la /mnt/immich/upload`
2. Check Immich logs: `docker compose logs -f`
3. Verify database restored: `docker exec -it immich_postgres psql -U postgres -c "\dt"`

### Backup takes forever

Large libraries can take hours. Consider:
- Using faster backup drive (SSD vs HDD)
- Increasing robocopy threads: `/MT:32`
- Running during off-hours
- Backing up to NAS over gigabit network

### Restore fails with "Invalid Parameter"

Check that paths don't have trailing slashes and exist:
```bash
# Good
/opt/immich

# Bad  
/opt/immich/
```

## 🔄 Regular Backup Schedule

### Recommended Schedule

- **Daily**: Automated database dumps (built into Immich)
- **Weekly**: Full backup to external drive
- **Monthly**: Test restore on separate system
- **Before updates**: Always backup before upgrading

### Automation Example

```powershell
# Windows Task Scheduler - Weekly backup
# Create scheduled task that runs:
powershell.exe -ExecutionPolicy Bypass -File "C:\Users\Blake\Docker\MediaServer\scripts\backup-immich.ps1" -StopServer $true
```

```bash
# Linux cron - Weekly backup (after migration)
0 2 * * 0 /opt/immich/scripts/backup-immich.sh > /var/log/immich-backup.log 2>&1
```

## 📚 References

- [Immich Backup Documentation](https://docs.immich.app/administration/backup-and-restore)
- [3-2-1 Backup Strategy](https://www.backblaze.com/blog/the-3-2-1-backup-strategy/)
- [PostgreSQL Backup Guide](https://www.postgresql.org/docs/current/backup.html)

## 💡 Tips

1. **Test your backups** - Restore to a test system periodically
2. **Multiple backup locations** - Keep copies on different drives/locations
3. **Monitor backup size** - Growing backups may indicate issues
4. **Keep old backups** - Don't immediately delete after new backup
5. **Document your setup** - Save `.env` and `docker-compose.yml` configs

---

**Current Setup (from your docker-compose.yaml):**
- Upload Location: `S:\Immich\upload`
- Database Container: `immich_postgres`
- Backup Destination: `G:\Immich_Backups`
