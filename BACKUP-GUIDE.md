# Backup & Restore Quick Reference Guide

## 🎯 Quick Commands

### Backup Operations

```powershell
# Basic backup of all volumes
.\scripts\backup-volumes.ps1

# Preview what will be backed up
.\scripts\backup-volumes.ps1 -WhatIf

# Backup to custom directory
.\scripts\backup-volumes.ps1 -BackupDir "D:\media-stack-backups"

# Backup only volumes from docker-compose.yaml
.\scripts\backup-volumes.ps1 -ComposeVolumes

# Enhanced backup with verification
.\scripts\backup-volumes-enhanced.ps1 -VerifyBackups

# Timestamped backups with rotation (keep last 7)
.\scripts\backup-volumes-enhanced.ps1 -CreateRotatedBackup -MaxBackupCount 7
```

### Restore Operations

```powershell
# Restore all volumes from backup directory
.\scripts\restore-volumes.ps1

# Preview restore operation
.\scripts\restore-volumes.ps1 -WhatIf

# Force restore (clears existing data first)
.\scripts\restore-volumes.ps1 -Force

# Restore from custom directory
.\scripts\restore-volumes.ps1 -BackupDir "D:\media-stack-backups"

# Selective restore (specific volumes only)
.\scripts\restore-volumes.ps1 -SelectiveRestore @('radarr_data', 'sonarr_data')

# Stop containers first, then restore
.\scripts\restore-volumes.ps1 -StopContainersFirst

# Restore with verification
.\scripts\restore-volumes.ps1 -VerifyAfterRestore

# Restore single volume
.\scripts\restore-volume.ps1
```

## 📋 Best Practices

### Before Backing Up

1. **Check disk space:**
   ```powershell
   Get-PSDrive C | Select-Object Name, @{N="Free(GB)";E={[math]::Round($_.Free/1GB,2)}}
   ```

2. **Check container status:**
   ```powershell
   docker ps -a
   ```

3. **Stop containers for consistency (optional but recommended):**
   ```powershell
   docker compose stop
   ```

### After Backup

1. **Verify backup files exist:**
   ```powershell
   Get-ChildItem .\vol_bkup\*.tar.gz | Select-Object Name, @{N="Size(MB)";E={[math]::Round($_.Length/1MB,2)}}
   ```

2. **Check backup log (if using enhanced script):**
   ```powershell
   Import-Csv .\vol_bkup\backup-log.csv | Format-Table
   ```

3. **Restart containers:**
   ```powershell
   docker compose start
   ```

### Before Restoring

1. **ALWAYS create a backup of current state first!**
   ```powershell
   .\scripts\backup-volumes.ps1 -BackupDir ".\vol_bkup\pre-restore"
   ```

2. **Verify backup files:**
   ```powershell
   # Test archive integrity
   docker run --rm -v ${PWD}/vol_bkup:/backup alpine tar tzf /backup/radarr_data.tar.gz
   ```

3. **Stop containers using the volumes:**
   ```powershell
   docker compose stop
   ```

### After Restore

1. **Verify data is present:**
   ```powershell
   docker run --rm -v radarr_data:/data alpine ls -lah /data
   ```

2. **Start containers:**
   ```powershell
   docker compose start
   ```

3. **Check logs for errors:**
   ```powershell
   docker compose logs -f --tail=50
   ```

## 🔥 Emergency Recovery Procedures

### Complete System Restore

If you need to restore everything from scratch:

```powershell
# 1. Ensure Docker is running
docker version

# 2. Pull all images
docker compose pull

# 3. Create containers (but don't start)
docker compose create

# 4. Restore all volumes
.\scripts\restore-volumes.ps1 -Force

# 5. Start all services
docker compose start

# 6. Verify
docker compose ps
docker compose logs -f
```

### Restore Single Service

To restore just one service (e.g., Radarr):

```powershell
# 1. Stop the container
docker compose stop radarr

# 2. Restore the volume
.\scripts\restore-volumes.ps1 -SelectiveRestore @('radarr_data') -Force

# 3. Start the container
docker compose start radarr

# 4. Check logs
docker compose logs -f radarr
```

### Partial Failure Recovery

If some services won't start after restore:

```powershell
# 1. Check which containers failed
docker compose ps

# 2. View logs for failed container
docker compose logs <container_name>

# 3. Remove and recreate the problematic container
docker compose stop <container_name>
docker compose rm <container_name>
docker compose up -d <container_name>

# 4. If still failing, try restoring its volume again
.\scripts\restore-volumes.ps1 -SelectiveRestore @('<volume_name>') -Force -StopContainersFirst
```

## 📊 Monitoring & Maintenance

### Check Backup Size Trends

```powershell
# Get backup sizes over time
Get-ChildItem .\vol_bkup\*.tar.gz | 
    Select-Object Name, LastWriteTime, @{N="Size(MB)";E={[math]::Round($_.Length/1MB,2)}} | 
    Sort-Object LastWriteTime -Descending | 
    Format-Table
```

### View Backup Log

```powershell
# If using backup-volumes-enhanced.ps1
Import-Csv .\vol_bkup\backup-log.csv | 
    Select-Object Timestamp, Volume, SizeMB, Status, Duration | 
    Sort-Object Timestamp -Descending | 
    Format-Table -AutoSize
```

### Calculate Total Backup Space

```powershell
$totalSize = (Get-ChildItem .\vol_bkup\*.tar.gz | Measure-Object -Property Length -Sum).Sum
[math]::Round($totalSize / 1GB, 2)
```

### Find Old Backups

```powershell
# Find backups older than 30 days
Get-ChildItem .\vol_bkup\*.tar.gz | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | 
    Select-Object Name, LastWriteTime
```

## 🔄 Scheduled Backups

### Using Windows Task Scheduler

1. **Open Task Scheduler:**
   ```powershell
   taskschd.msc
   ```

2. **Create Basic Task:**
   - Name: "media-stack Backup"
   - Trigger: Daily at 3:00 AM
   - Action: Start a program
   - Program: `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`
   - Arguments: `-ExecutionPolicy Bypass -File "C:\Users\Blake\Docker\media-stack\scripts\backup-volumes.ps1"`

3. **Advanced Settings:**
   - Run whether user is logged on or not
   - Run with highest privileges
   - Stop task if runs longer than 3 hours

### Using PowerShell Direct

```powershell
# Register scheduled task via PowerShell
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -File `"$PSScriptRoot\scripts\backup-volumes.ps1`""

$trigger = New-ScheduledTaskTrigger -Daily -At 3am

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd

Register-ScheduledTask -TaskName "media-stack Backup" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -User "SYSTEM" `
    -RunLevel Highest `
    -Description "Daily backup of Docker volumes"
```

## ⚠️ Troubleshooting

### "Container not found" Error

**Problem:** Backup script says container doesn't exist  
**Solution:** Ensure containers are created first:
```powershell
docker compose up -d
docker compose stop  # Optional: for consistency
.\scripts\backup-volumes.ps1
```

### "Permission denied" Error

**Problem:** Can't access volume or backup directory  
**Solution:** 
1. Run PowerShell as Administrator
2. Ensure Docker Desktop has file sharing enabled for the path
3. Check antivirus isn't blocking access

### Backup Files Are Empty or Very Small

**Problem:** Backup completed but file size is unexpectedly small  
**Solution:**
1. Check if volume actually has data:
   ```powershell
   docker run --rm -v <volume_name>:/data alpine du -sh /data
   ```
2. Verify container is using the correct volume:
   ```powershell
   docker inspect <container_name> | Select-String -Pattern "Mounts" -Context 5,10
   ```

### Restore Doesn't Seem to Work

**Problem:** Data not showing up after restore  
**Solution:**
1. Verify volume was actually populated:
   ```powershell
   docker run --rm -v <volume_name>:/data alpine ls -lah /data
   ```
2. Ensure container is using the correct volume name
3. Try recreating the container:
   ```powershell
   docker compose stop <service>
   docker compose rm <service>
   docker compose up -d <service>
   ```

### Out of Disk Space

**Problem:** Not enough space for backups  
**Solution:**
1. Clean up old backups:
   ```powershell
   # Remove backups older than 30 days
   Get-ChildItem .\vol_bkup\*.tar.gz | 
       Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | 
       Remove-Item
   ```
2. Clean up Docker:
   ```powershell
   docker system prune -a
   ```
3. Use external drive for backups:
   ```powershell
   .\scripts\backup-volumes.ps1 -BackupDir "E:\Backups"
   ```

## 📚 Additional Resources

- Main README: [README.md](../README.md)
- Docker Compose Reference: [docker-compose.yaml](../docker-compose.yaml)
- Backup Fix Summary: [BACKUP-FIX-SUMMARY.md](../BACKUP-FIX-SUMMARY.md)
- Restore Fix Summary: [RESTORE-FIX-SUMMARY.md](../RESTORE-FIX-SUMMARY.md)

---

**Last Updated:** October 2025
