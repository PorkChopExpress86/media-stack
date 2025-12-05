<# Compatibility shim: use `restore-volumes.ps1` instead. #>

param (
    [string]$BackupDir = "$PSScriptRoot\..\vol_bkup",
    [switch]$Force,
    [switch]$WhatIf
)

# Check Docker CLI is available and Docker is running
try {
    docker version > $null 2>&1
}
catch {
    Write-Error "Docker CLI is not available or Docker is not running. Start Docker Desktop and retry."
    exit 1
}

# Resolve backup directory
try {
    $backupDirResolved = (Resolve-Path -Path $BackupDir -ErrorAction Stop).ProviderPath
}
catch {
    Write-Error "Backup directory '$BackupDir' not found. Provide a valid -BackupDir path.";
    exit 1
}

# Find .tar.gz backups
$backups = Get-ChildItem -Path $backupDirResolved -Filter "*.tar.gz" -File -ErrorAction SilentlyContinue
if (-not $backups -or $backups.Count -eq 0) {
    Write-Host "No .tar.gz backups found in '$backupDirResolved'. Nothing to do.";
    exit 0
}

foreach ($backup in $backups) {
    # Strip the full extension .tar.gz to get the original volume name
    $volumeName = ($backup.Name -replace '\.tar\.gz$', '')
    Write-Host "Restoring volume: $volumeName from $($backup.FullName)"

    if ($WhatIf) {
        Write-Host "WhatIf: would ensure volume '$volumeName' exists and restore $($backup.Name)"
        continue
    }

    # Create the volume if it doesn't exist
    $existing = docker volume ls --format "{{.Name}}" | Where-Object { $_ -eq $volumeName }
    if (-not $existing) {
        docker volume create $volumeName | Out-Null
        Write-Host "Created volume: $volumeName"
    }

    # Optionally clear existing contents in the volume before restoring
    if ($Force) {
        Write-Host "Removing existing contents of volume '$volumeName' before restore"
        $rmMount = $volumeName + ':/volume'
        $rmArgs = @('run', '--rm', '-v', $rmMount, 'alpine', 'sh', '-c', 'rm -rf /volume/* || true')
        Write-Host "Running: docker $($rmArgs -join ' ')"
        & docker @rmArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to clear volume $volumeName; proceeding to attempt restore anyway."
        }
    }

    # Forward to consolidated restore script
    Write-Host "Delegating to scripts\restore-volumes.ps1 (use -WhatIf to preview)"
    & "$PSScriptRoot\restore-volumes.ps1" -BackupDir $BackupDir @($(if ($Force) {'-Force'})) @($(if ($WhatIf) {'-WhatIf'}))
    break
}