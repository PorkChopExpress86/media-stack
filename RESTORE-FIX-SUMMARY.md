# Restore Script Enhancement - Volume Name Resolution

**Date:** October 5, 2025  
**Repository:** media-stack  
**Script:** restore-volumes.ps1  
**Status:** ✅ ENHANCED

---

## Summary

Updated `restore-volumes.ps1` to match the volume name resolution logic from `backup-volumes.ps1`. The script now intelligently matches backup archives to volumes, even when users specify short names.

---

## Changes Made

### 1. Added `Resolve-SelectiveRestoreName` Function

This function enables user-friendly selective restores. Users can now specify:
- Short names: `nginx_data`
- Full names: `mediaserver_nginx_data`
- Partial matches

The function will correctly match `nginx_data` to `mediaserver_nginx_data.tar.gz`.

```powershell
function Resolve-SelectiveRestoreName {
    param([string]$UserSpecifiedName, [string]$BackupVolumeNameFromFile)
    
    # Exact match
    if ($UserSpecifiedName -eq $BackupVolumeNameFromFile) { return $true }
    
    # Match if backup ends with user pattern (e.g., mediaserver_nginx_data contains nginx_data)
    if ($BackupVolumeNameFromFile -like "*_$UserSpecifiedName") { return $true }
    
    # Partial match
    if ($BackupVolumeNameFromFile -like "*$UserSpecifiedName*") { return $true }
    
    return $false
}
```

### 2. Updated Selective Restore Logic

Changed from simple array membership check to intelligent matching:

**Before:**
```powershell
if ($SelectiveRestore.Count -gt 0 -and $volumeName -notin $SelectiveRestore) {
    # Skip
}
```

**After:**
```powershell
if ($SelectiveRestore.Count -gt 0) {
    $shouldRestore = $false
    foreach ($userPattern in $SelectiveRestore) {
        if (Resolve-SelectiveRestoreName -UserSpecifiedName $userPattern -BackupVolumeNameFromFile $volumeName) {
            $shouldRestore = $true
            break
        }
    }
    if (-not $shouldRestore) { # Skip }
}
```

### 3. Fixed Character Encoding Issues

Replaced special Unicode characters that caused parsing errors:
- `✓` → `[SUCCESS]`
- `✗` → `[FAILED]`  
- `⚠` → `[WARNING]`

### 4. Fixed Shell Command String

Changed from double quotes (which PowerShell interprets) to single quotes + concatenation:

**Before:**
```powershell
$tarCmd = "cd /volume && tar xzf /backup/$($backup.Name)"
```

**After:**
```powershell
$tarCmd = 'cd /volume && tar xzf /backup/' + $backup.Name
```

---

## Testing Results

### Test 1: Full Restore (All Volumes)
```powershell
.\scripts\restore-volumes.ps1 -WhatIf
```

**Result:** ✅ Found and processed all 14 backup archives:
- 12 `mediaserver_*` volumes
- 2 unprefixed volumes (`audiobookshelf_data`, `vpn_data`)

### Test 2: Selective Restore with Short Names
```powershell
.\scripts\restore-volumes.ps1 -SelectiveRestore @('nginx_data', 'radarr_data') -WhatIf
```

**Result:** ✅ Correctly matched:
- `nginx_data` → `mediaserver_nginx_data.tar.gz`  
- `radarr_data` → `mediaserver_radarr_data.tar.gz`

**Skipped:** 12 other volumes ✅

---

## Usage Examples

### User-Friendly Selective Restore

Users can now use short, memorable names:

```powershell
# Restore specific services using short names
.\scripts\restore-volumes.ps1 -SelectiveRestore @('nginx_data', 'radarr_data', 'sonarr_data')

# Or use full names
.\scripts\restore-volumes.ps1 -SelectiveRestore @('mediaserver_nginx_data', 'mediaserver_radarr_data')

# Mix and match
.\scripts\restore-volumes.ps1 -SelectiveRestore @('nginx_data', 'mediaserver_radarr_data')
```

All variations will correctly match the actual backup files!

### Full Restore

```powershell
# Preview all restores
.\scripts\restore-volumes.ps1 -WhatIf

# Restore all volumes
.\scripts\restore-volumes.ps1

# Force restore (clear existing data first)
.\scripts\restore-volumes.ps1 -Force

# Stop containers first for consistency
.\scripts\restore-volumes.ps1 -StopContainersFirst
```

---

## How It Works

### Scenario: User wants to restore `nginx_data`

1. Script finds backup file: `mediaserver_nginx_data.tar.gz`
2. Extracts volume name: `mediaserver_nginx_data`
3. User specified: `nginx_data`
4. `Resolve-SelectiveRestoreName` checks:
   - Exact match? No
   - Ends with `_nginx_data`? **Yes!** ✅
5. Volume is restored

### Scenario: User wants to restore `mediaserver_radarr_data`

1. Script finds backup file: `mediaserver_radarr_data.tar.gz`
2. Extracts volume name: `mediaserver_radarr_data`
3. User specified: `mediaserver_radarr_data`
4. `Resolve-SelectiveRestoreName` checks:
   - Exact match? **Yes!** ✅
5. Volume is restored

---

## Benefits

### For Users
- ✅ **Simpler commands** - Use short, memorable volume names
- ✅ **Flexible matching** - Full names, short names, or partial matches all work
- ✅ **Consistent with backup** - Both scripts use same logic
- ✅ **No confusion** - Script handles Docker Compose name prefixes automatically

### For Operations
- ✅ **Backward compatible** - Old backup names still work
- ✅ **Forward compatible** - New prefixed backup names work correctly
- ✅ **Robust matching** - Handles various naming conventions
- ✅ **Clear output** - Shows exactly which volumes are being restored

---

## Compatibility

### Works With:
- ✅ Backups from fixed `backup-volumes.ps1` (prefixed names)
- ✅ Old backups with unprefixed names
- ✅ Manual backups with custom names
- ✅ Mixed backup directories with both naming styles

### Restore Name Matching:
| User Specifies | Matches Backup | Result |
|---------------|----------------|--------|
| `nginx_data` | `mediaserver_nginx_data.tar.gz` | ✅ Restores |
| `mediaserver_nginx_data` | `mediaserver_nginx_data.tar.gz` | ✅ Restores |
| `nginx` | `mediaserver_nginx_data.tar.gz` | ✅ Restores (partial match) |
| `radarr` | `mediaserver_radarr_data.tar.gz` | ✅ Restores (partial match) |
| `sonarr` | `mediaserver_radarr_data.tar.gz` | ❌ No match |

---

## Files Modified

1. **`scripts/restore-volumes.ps1`**
   - Added `Resolve-SelectiveRestoreName` function
   - Updated selective restore logic to use intelligent matching
   - Fixed character encoding issues
   - Fixed shell command string escaping

---

## Next Steps

Both backup and restore scripts now:
1. ✅ Correctly identify Docker Compose prefixed volumes
2. ✅ Support user-friendly selective operations
3. ✅ Handle mixed naming conventions
4. ✅ Provide clear feedback during operations

**Ready for production use!** 🎉

---

*Last Updated: October 5, 2025*
