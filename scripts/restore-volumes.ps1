<#
PowerShell script to restore all Docker volumes from .tar.gz backups (batch restore).
Automatically finds and restores all backup archives in the backup directory.

Usage:
  .\restore-volumes.ps1                     # restore all volumes
  .\restore-volumes.ps1 -WhatIf             # preview only
  .\restore-volumes.ps1 -Force              # clear existing data before restore
  .\restore-volumes.ps1 -BackupDir "D:\backups"
  .\restore-volumes.ps1 -SelectiveRestore @('nginx_data', 'radarr_data')
#>

param (
    [string]$BackupDir = "$PSScriptRoot\..\vol_bkup",
    [switch]$Force,
    [switch]$WhatIf,
    [string[]]$SelectiveRestore = @(),
    [switch]$VerifyAfterRestore,
    [switch]$StopContainersFirst
)

function Test-Docker {
    try {
        docker version > $null 2>&1
        return $true
    }
    catch {
        Write-Error "Docker CLI is not available or Docker is not running. Start Docker Desktop and retry."
        return $false
    }
}

function Get-ContainersUsingVolume {
    param([string]$VolumeName)
    
    try {
        $containers = docker ps --filter volume=$VolumeName --format "{{.Names}}" 2>$null
        if ($containers) {
            return $containers -split "`n" | Where-Object { $_ }
        }
        return @()
    }
    catch {
        return @()
    }
}

function Stop-ContainersUsingVolume {
    param([string]$VolumeName)
    
    $containers = Get-ContainersUsingVolume -VolumeName $VolumeName
    $stopped = @()
    
    foreach ($container in $containers) {
        if ($WhatIf) {
            Write-Host "WhatIf: would stop container '$container'" -ForegroundColor Yellow
            continue
        }
        
        Write-Host "Stopping container: $container" -ForegroundColor Cyan
        docker stop $container | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $stopped += $container
        }
    }
    
    return $stopped
}

function Start-Containers {
    param([string[]]$ContainerNames)
    
    foreach ($container in $ContainerNames) {
        if ($WhatIf) {
            Write-Host "WhatIf: would start container '$container'" -ForegroundColor Yellow
            continue
        }
        
        Write-Host "Starting container: $container" -ForegroundColor Green
        docker start $container | Out-Null
    }
}

function Test-VolumeRestore {
    param([string]$VolumeName)
    
    Write-Host "Verifying volume '$VolumeName'..." -ForegroundColor Cyan
    
    $mountVolume = "${VolumeName}:/volume"
    $testArgs = @('run', '--rm', '-v', $mountVolume, 'alpine', 'sh', '-c', 'ls -la /volume | head -n 20')
    
    $output = & docker @testArgs 2>&1
    
    if ($LASTEXITCODE -eq 0 -and $output) {
        Write-Host "[OK] Volume contains data" -ForegroundColor Green
        return $true
    }
    else {
        Write-Warning "[WARN] Volume appears empty or inaccessible"
        return $false
    }
}

function Resolve-SelectiveRestoreName {
    param([string]$UserSpecifiedName, [string]$BackupVolumeNameFromFile)
    
    # If user specified something like "nginx_data" but the backup is "mediaserver_nginx_data.tar.gz",
    # we should match them intelligently
    
    # If exact match, use it
    if ($UserSpecifiedName -eq $BackupVolumeNameFromFile) {
        return $true
    }
    
    # Check if backup name ends with user-specified name (e.g., mediaserver_nginx_data contains nginx_data)
    if ($BackupVolumeNameFromFile -like "*_$UserSpecifiedName") {
        return $true
    }
    
    # Check if user specified the full prefixed name
    if ($BackupVolumeNameFromFile -like "*$UserSpecifiedName*") {
        return $true
    }
    
    return $false
}

if (-not (Test-Docker)) { exit 1 }

# Resolve backup directory
try {
    $backupDirResolved = (Resolve-Path -Path $BackupDir -ErrorAction Stop).ProviderPath
}
catch {
    Write-Error "Backup directory '$BackupDir' not found. Provide a valid -BackupDir path."
    exit 1
}

# Find .tar.gz backups
$backups = Get-ChildItem -Path $backupDirResolved -Filter "*.tar.gz" -File -ErrorAction SilentlyContinue

if (-not $backups -or $backups.Count -eq 0) {
    Write-Host "No .tar.gz backups found in '$backupDirResolved'. Nothing to restore." -ForegroundColor Yellow
    exit 0
}

Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Docker Volume Restore Utility" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Backup Directory: $backupDirResolved" -ForegroundColor White
Write-Host "Found $($backups.Count) backup archive(s)" -ForegroundColor White
Write-Host ""

if ($WhatIf) {
    Write-Host "PREVIEW MODE - No changes will be made" -ForegroundColor Yellow
    Write-Host ""
}

if ($Force -and -not $WhatIf) {
    Write-Warning "FORCE MODE ENABLED - Existing volume data will be cleared!"
    Write-Host ""
}

# Statistics tracking
$stats = @{
    Total      = $backups.Count
    Successful = 0
    Failed     = 0
    Skipped    = 0
}

$stoppedContainers = @{}

foreach ($backup in $backups) {
    # Strip the full extension .tar.gz to get the original volume name
    $volumeName = ($backup.Name -replace '\.tar\.gz$', '')
    
    # Apply selective restore filter if specified
    if ($SelectiveRestore.Count -gt 0) {
        $shouldRestore = $false
        foreach ($userPattern in $SelectiveRestore) {
            if (Resolve-SelectiveRestoreName -UserSpecifiedName $userPattern -BackupVolumeNameFromFile $volumeName) {
                $shouldRestore = $true
                break
            }
        }
        
        if (-not $shouldRestore) {
            Write-Host "[-] Skipping '$volumeName' (not in selective restore list)" -ForegroundColor DarkGray
            $stats.Skipped++
            continue
        }
    }
    
    Write-Host "───────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "[*] Processing volume: $volumeName" -ForegroundColor Cyan
    Write-Host "    Archive: $($backup.Name)" -ForegroundColor Gray
    Write-Host "    Size: $([math]::Round($backup.Length / 1MB, 2)) MB" -ForegroundColor Gray
    
    if ($WhatIf) {
        Write-Host "    WhatIf: would ensure volume '$volumeName' exists and restore $($backup.Name)" -ForegroundColor Yellow
        $stats.Successful++
        continue
    }
    
    # Check for containers using this volume and optionally stop them
    $containersUsing = Get-ContainersUsingVolume -VolumeName $volumeName
    
    if ($containersUsing.Count -gt 0) {
        Write-Host "    [WARNING] Volume in use by: $($containersUsing -join ', ')" -ForegroundColor Yellow
        
        if ($StopContainersFirst) {
            $stopped = Stop-ContainersUsingVolume -VolumeName $volumeName
            if ($stopped.Count -gt 0) {
                $stoppedContainers[$volumeName] = $stopped
            }
        }
        elseif (-not $Force) {
            Write-Warning "    Volume is in use. Consider using -StopContainersFirst or -Force"
            Write-Host "    Proceeding anyway - may cause data inconsistency!" -ForegroundColor Yellow
        }
    }
    
    # Create the volume if it doesn't exist
    $existing = docker volume ls --format "{{.Name}}" | Where-Object { $_ -eq $volumeName }
    if (-not $existing) {
        Write-Host "    Creating volume: $volumeName" -ForegroundColor Green
        docker volume create $volumeName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "    [FAILED] Failed to create volume $volumeName"
            $stats.Failed++
            continue
        }
    }
    else {
        Write-Host "    Volume exists: $volumeName" -ForegroundColor Gray
    }
    
    # Optionally clear existing contents in the volume before restoring
    if ($Force) {
        Write-Host "    Clearing existing contents..." -ForegroundColor Yellow
        $rmMount = $volumeName + ':/volume'
        $rmArgs = @('run', '--rm', '-v', $rmMount, 'alpine', 'sh', '-c', 'rm -rf /volume/* /volume/.* 2>/dev/null || true')
        & docker @rmArgs | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "    Could not clear volume completely; attempting restore anyway"
        }
    }
    
    # Use resolved directory path for the bind mount
    $backupDirForDocker = $backup.DirectoryName
    
    # Restore the backup into the volume
    $mountVolume = $volumeName + ':/volume'
    $mountBackup = $backupDirForDocker + ':/backup'
    $tarCmd = 'cd /volume && tar xzf /backup/' + $backup.Name
    $processArgs = @('run', '--rm', '-v', $mountVolume, '-v', $mountBackup, 'alpine', 'sh', '-c', $tarCmd)
    
    Write-Host "    Restoring data..." -ForegroundColor Cyan
    & docker @processArgs 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    [SUCCESS] Successfully restored $volumeName" -ForegroundColor Green
        $stats.Successful++
        
        # Optionally verify the restore
        if ($VerifyAfterRestore) {
            Test-VolumeRestore -VolumeName $volumeName | Out-Null
        }
    }
    else {
        Write-Error "    [FAILED] Failed to restore $volumeName (exit code $LASTEXITCODE)"
        $stats.Failed++
    }
}

# Restart any containers we stopped
if ($stoppedContainers.Count -gt 0 -and -not $WhatIf) {
    Write-Host ""
    Write-Host "───────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "[*] Restarting stopped containers..." -ForegroundColor Cyan
    
    $allStopped = $stoppedContainers.Values | ForEach-Object { $_ } | Select-Object -Unique
    Start-Containers -ContainerNames $allStopped
}

# Print summary
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Restore Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total archives:     $($stats.Total)" -ForegroundColor White
Write-Host "Successfully restored: $($stats.Successful)" -ForegroundColor Green
Write-Host "Failed:             $($stats.Failed)" -ForegroundColor $(if ($stats.Failed -gt 0) { 'Red' } else { 'Gray' })
Write-Host "Skipped:            $($stats.Skipped)" -ForegroundColor Gray
Write-Host ""

if ($stats.Failed -gt 0) {
    Write-Host "[WARNING] Some restores failed. Check the output above for details." -ForegroundColor Yellow
    exit 1
}
elseif ($WhatIf) {
    Write-Host "Preview completed. Use without -WhatIf to perform actual restore." -ForegroundColor Yellow
}
else {
    Write-Host "All restores completed successfully!" -ForegroundColor Green
}

Write-Host ""
