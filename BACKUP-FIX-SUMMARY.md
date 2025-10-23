# Backup Script Fix - Volume Name Resolution

**Date:** October 5, 2025  
**Issue:** backup-volumes.ps1 was backing up empty/placeholder volumes instead of actual data  
**Status:** ✅ FIXED

---

## Problem Description

When using `backup-volumes.ps1 -ComposeVolumes`, the script backed up volumes like `nginx_data`, `radarr_data`, etc., which resulted in nearly empty backup files (104 bytes each).

### Root Cause

Docker Compose automatically prefixes volume names with the project name (directory name). For example:
- `docker-compose.yaml` defines: `nginx_data`
- Docker creates: `mediaserver_nginx_data`

The script was backing up the volumes as named in the compose file, but Docker had created **both** versions:
1. `mediaserver_nginx_data` ← **Contains actual data** (used by running containers)
2. `nginx_data` ← **Empty placeholder** (created when backup script referenced it)

---

## Solution Implemented

Added a new function `Get-ActualVolumeName` that:

1. **First:** Checks for project-prefixed version (e.g., `mediaserver_nginx_data`)
2. **Second:** Looks for any prefixed version (e.g., `*_nginx_data`)
3. **Third:** Falls back to unprefixed version if no prefixed exists
4. **Warns:** If using unprefixed version that might be empty

### Code Added

```powershell
function Get-ActualVolumeName {
    param([string]$ComposeName)
    
    # Docker Compose prefixes volume names with the project name
    $allVolumes = docker volume ls --format "{{.Name}}" 2>$null
    
    # FIRST: Try project-prefixed version (most likely in use)
    try {
        $projectName = (Get-Item (Split-Path -Parent $PSScriptRoot)).Name.ToLower()
        $withProject = "${projectName}_${ComposeName}"
        if ($allVolumes | Where-Object { $_ -eq $withProject }) { 
            return $withProject 
        }
    }
    catch { }
    
    # SECOND: Look for any prefixed version
    $prefixed = $allVolumes | Where-Object { $_ -like "*_$ComposeName" }
    if ($prefixed) { return $prefixed }
    
    # THIRD: Use exact match with warning
    if ($allVolumes | Where-Object { $_ -eq $ComposeName }) {
        Write-Warning "Found unprefixed volume '$ComposeName' - may be empty"
        return $ComposeName
    }
    
    return $ComposeName
}
```

---

## Test Results

### Before Fix
```
nginx_data.tar.gz          0.0001 MB (104 bytes)
radarr_data.tar.gz         0.0001 MB (104 bytes)
sonarr_data.tar.gz         0.0001 MB (104 bytes)
```

### After Fix
```
mediaserver_nginx_data.tar.gz        2.69 MB
mediaserver_radarr_data.tar.gz     556.08 MB
mediaserver_sonarr_data.tar.gz     109.76 MB
mediaserver_model-cache.tar.gz     611.05 MB
```

### Full Backup Results

| Volume | Original Size | Backup Size | Compression |
|--------|--------------|-------------|-------------|
| bazarr_data | 15.4 MB | 4.31 MB | 3.57x |
| focalboard_data | 1.3 MB | 0.60 MB | 2.17x |
| gluetun_data | 7.0 MB | 0.34 MB | 20.59x |
| letsencrypt | 0.69 MB | 0.04 MB | 17.25x |
| model-cache | 847.5 MB | 611.05 MB | 1.39x |
| nginx_data | 46.8 MB | 2.69 MB | 17.73x |
| pinchflat_data | 86.9 MB | 31.48 MB | 2.90x |
| prowlarr_data | 101.7 MB | 9.61 MB | 10.73x |
| qbittorrent_data | 7.5 MB | 3.72 MB | 2.03x |
| radarr_data | 656.8 MB | 556.08 MB | 1.18x |
| reddis_data | 1.1 MB | 0.55 MB | 2.00x |
| sonarr_data | 270.2 MB | 109.76 MB | 2.48x |

**Total:** 2,042.89 MB → 1,330.23 MB (35% space saved)

---

## Verification

The script now correctly:
1. ✅ Resolves volume names to their actual Docker names
2. ✅ Shows mapping during backup (e.g., `nginx_data -> mediaserver_nginx_data`)
3. ✅ Backs up volumes with actual data
4. ✅ Warns when unprefixed volumes are used
5. ✅ Creates properly sized backup archives

### Example Output

```
Resolving actual volume names from docker-compose.yaml volumes: nginx_data, letsencrypt, ...

  nginx_data -> mediaserver_nginx_data
  letsencrypt -> mediaserver_letsencrypt
  prowlarr_data -> mediaserver_prowlarr_data
  ...

Backing up ':/data' -> vol_bkup\mediaserver_nginx_data.tar.gz
Saved: vol_bkup\mediaserver_nginx_data.tar.gz (2.69 MB)
```

---

## Usage

The fixed script now works correctly with `-ComposeVolumes` flag:

```powershell
# Preview
.\scripts\backup-volumes.ps1 -ComposeVolumes -WhatIf

# Backup all compose volumes
.\scripts\backup-volumes.ps1 -ComposeVolumes

# Backup to custom location
.\scripts\backup-volumes.ps1 -ComposeVolumes -BackupDir "D:\Backups"
```

---

## Notes

- **audiobookshelf_data** and **vpn_data** don't have prefixed versions (likely bind mounts or legacy volumes)
- The script shows warnings for these but backs them up correctly
- Sonarr backup may show warnings about changed files (normal for running containers)
- qBittorrent backup shows "socket ignored" warning (normal, sockets can't be archived)

---

## Recommendations

1. **Stop containers before backup** for consistency:
   ```powershell
   docker compose stop
   .\scripts\backup-volumes.ps1 -ComposeVolumes
   docker compose start
   ```

2. **Clean up old empty volumes** (optional):
   ```powershell
   docker volume rm nginx_data radarr_data sonarr_data # etc.
   ```

3. **Schedule regular backups** using Windows Task Scheduler (see BACKUP-GUIDE.md)

---

**Status: ✅ RESOLVED**  
The backup script now correctly identifies and backs up actual Docker volumes with data!
