<#
PowerShell script to back up Docker volumes (gzipped tar archives).
Creates archives in ../vol_bkup by default.

Usage:
  .\backup-volumes.ps1            # run backups
  .\backup-volumes.ps1 -WhatIf    # preview only
  .\backup-volumes.ps1 -BackupDir "D:\backups" -WhatIf
#>

param (
    [string]$BackupDir = "$PSScriptRoot\..\vol_bkup",
    [switch]$WhatIf,
    [switch]$AllMounts,
    [switch]$StopContainers,
    [switch]$ComposeVolumes
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

if (-not (Test-Docker)) { exit 1 }

try {
    $backupDirResolved = (Resolve-Path -Path $BackupDir -ErrorAction Stop).ProviderPath
}
catch {
    Write-Host "Backup directory '$BackupDir' not found. Creating it..."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $backupDirResolved = (Resolve-Path -Path $BackupDir).ProviderPath
}

# Define backups: container, archiveName, sourcePath
$backups = @(
    @{ container = 'nginx'; archive = 'mediaserver_nginx_data.tar.gz'; src = '/data' },
    @{ container = 'nginx'; archive = 'mediaserver_letsencrypt.tar.gz'; src = '/etc/letsencrypt' },
    @{ container = 'derbynet'; archive = 'derbynet_data.tar.gz'; src = '/var/lib/derbynet' },
    @{ container = 'jellyfin'; archive = 'jellyfin_data.tar.gz'; src = '/config' },
    @{ container = 'jellyfin'; archive = 'jellyfin_cache.tar.gz'; src = '/cache' },
    @{ container = 'plex'; archive = 'plex_data.tar.gz'; src = '/config' },
    @{ container = 'vpn'; archive = 'vpn_data.tar.gz'; src = '/pia' },
    @{ container = 'vpn'; archive = 'gluetun_data.tar.gz'; src = '/gluetun' },
    @{ container = 'prowlarr'; archive = 'mediaserver_prowlarr_data.tar.gz'; src = '/config' },
    @{ container = 'radarr'; archive = 'mediaserver_radarr_data.tar.gz'; src = '/config' },
    @{ container = 'sonarr'; archive = 'mediaserver_sonarr_data.tar.gz'; src = '/config' },
    @{ container = 'lidarr'; archive = 'lidarr_data.tar.gz'; src = '/config' },
    @{ container = 'readarr'; archive = 'readarr_data.tar.gz'; src = '/config' },
    @{ container = 'bazarr'; archive = 'mediaserver_bazarr_data.tar.gz'; src = '/config' },
    @{ container = 'qbittorrent'; archive = 'mediaserver_qbittorrent_data.tar.gz'; src = '/config' },
    @{ container = 'audiobookshelf'; archive = 'audiobookshelf_data.tar.gz'; src = '/config' },
    @{ container = 'immich_machine_learning'; archive = 'mediaserver_model-cache.tar.gz'; src = '/cache' },
    @{ container = 'pinchflat'; archive = 'mediaserver_pinchflat_data.tar.gz'; src = '/config' },
    @{ container = 'scrypted'; archive = 'scrypted_scrypted-data.tar.gz'; src = '/data' }
)

# Containers to stop during backup for consistency (adjust as you like)
$ContainersToStop = @('immich_postgres', 'immich_redis', 'taxprotest-postgres', 'immich_server', 'postgres')

# Helper to stop and later restart containers safely
$containersStopped = @()
function Safe-StopContainer($name) {
    $exists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $name }
    if (-not $exists) { return }
    $status = docker inspect -f '{{.State.Status}}' $name
    if ($status -eq 'running') {
        if ($WhatIf) { Write-Host "WhatIf: would stop container '$name'"; $containersStopped += $name; return }
        Write-Host "Stopping container: $name"
        docker stop $name | Out-Null
        $containersStopped += $name
    }
}

function Safe-RestartStopped() {
    foreach ($n in $containersStopped) {
        # Only restart if container exists and is not running
        $exists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $n }
        if (-not $exists) { continue }
        $status = docker inspect -f '{{.State.Status}}' $n
        if ($status -ne 'running') {
            if ($WhatIf) { Write-Host "WhatIf: would start container '$n'"; continue }
            Write-Host "Starting container: $n"
            docker start $n | Out-Null
        }
    }
    $containersStopped = @()
}

function Normalize-ArchiveName($container, $dest) {
    # Create a filesystem-safe archive name from container and destination
    # Example: nginx + /etc/letsencrypt -> nginx__etc_letsencrypt.tar.gz
    if (-not $dest) { $dest = '/' }
    $clean = $dest -replace '^/+', '' -replace '/+', '_' -replace '[^0-9A-Za-z_.-]', ''
    if ($clean -eq '') { $clean = 'root' }
    return "${container}_${clean}.tar.gz"
}

# If requested, auto-discover mounts for all containers and add them to the backup list.
if ($AllMounts) {
    Write-Host "Auto-discovery: adding all container mounts to backup list (skips duplicates)"
    $allContainers = docker ps -a --format "{{.Names}}" 2>$null
    foreach ($c in $allContainers) {
        if (-not $c) { continue }
        $mountsJson = docker inspect -f '{{json .Mounts}}' $c 2>$null
        if (-not $mountsJson) { continue }
        try {
            $mounts = $mountsJson | ConvertFrom-Json
        }
        catch { continue }
        foreach ($m in $mounts) {
            if (-not $m.Destination) { continue }
            $destPath = $m.Destination
            # Check if this container+dest is already covered by explicit $backups
            $exists = $false
            foreach ($b in $backups) {
                if ($b.container -eq $c -and ($b.src -eq $destPath -or $b.src -like "$destPath/*" -or $destPath -like "$($b.src)/*")) { $exists = $true; break }
            }
            if ($exists) { continue }
            $archiveName = Normalize-ArchiveName $c $destPath
            $backups += @{ container = $c; archive = $archiveName; src = $destPath }
        }
    }
}

# If requested, parse docker-compose.yaml and back up only the named volumes defined there.
function Get-ComposeVolumes($composePath) {
    if (-not (Test-Path $composePath)) { return @() }
    $lines = Get-Content $composePath -ErrorAction SilentlyContinue
    $inVolumes = $false
    $vols = @()
    foreach ($line in $lines) {
        # Detect top-level 'volumes:' (no indentation)
        if ($line -match '^(\s*)volumes:\s*$') {
            $indent = $matches[1].Length
            if ($indent -eq 0) { $inVolumes = $true; continue }
        }
        if ($inVolumes) {
            # stop if we hit another top-level key (no leading spaces)
            if ($line -match '^\S') { break }
            # match entries like '  nginx_data:' or '  name:'
            if ($line -match '^\s+([A-Za-z0-9_.-]+):\s*$') {
                $vols += $matches[1]
            }
        }
    }
    return $vols | Select-Object -Unique
}

if ($ComposeVolumes) {
    # Default compose file path in repo root
    $composeFile = Join-Path -Path $PSScriptRoot -ChildPath "..\docker-compose.yaml"
    $composeFile = (Resolve-Path $composeFile -ErrorAction SilentlyContinue).ProviderPath
    $composeVolumeNames = Get-ComposeVolumes $composeFile
    if (-not $composeVolumeNames -or $composeVolumeNames.Count -eq 0) {
        Write-Warning "No named volumes found in docker-compose.yaml at $composeFile"
    }
    else {
        Write-Host "Backing up named volumes from docker-compose.yaml: $($composeVolumeNames -join ', ')"
        # Replace backups list with volumes from compose
        $backups = @()
        foreach ($v in $composeVolumeNames) {
            $archive = "${v}.tar.gz"
            # mark these entries as volume-backed so the main loop uses -v <volume>:/data
            $backups += @{ container = ''; archive = $archive; src = '/data'; volume = $v }
        }
    }
}

foreach ($item in $backups) {
    $container = $item.container
    $archive = $item.archive
    $src = $item.src
    $volumeName = $null
    if ($item.ContainsKey('volume')) { $volumeName = $item.volume }

    if ($volumeName) {
        # For named volumes from compose, run a temporary container mounting the volume to /data
        $dest = Join-Path -Path $backupDirResolved -ChildPath $archive
        $mount = $backupDirResolved + ':/backup'
        $dockerCmd = @('run', '--rm', '-v', ($volumeName + ':/data'), '-v', $mount, 'ubuntu', 'sh', '-c', ("tar czf /backup/$archive -C /data ."))
    }
    else {
        # check if the container exists (either running or stopped)
        $exists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $container }
        if (-not $exists) {
            Write-Warning "Container '$container' not found - skipping backup for $archive"
            continue
        }

        # Inspect container mounts and ensure the requested src path is present as a mount
        $mountsJson = docker inspect -f '{{json .Mounts}}' $container 2>$null
        $mounts = @()
        if ($mountsJson) {
            try {
                $mounts = $mountsJson | ConvertFrom-Json
            }
            catch {
                $mounts = @()
            }
        }

        $matched = $false
        foreach ($m in $mounts) {
            if ($null -eq $m.Destination) { continue }
            if ($m.Destination -eq $src -or $m.Destination -like "$src/*" -or $src -like "${m.Destination}/*") {
                $matched = $true
                break
            }
        }

        if (-not $matched) {
            Write-Warning "No mount matching '$src' found in container '$container' - skipping backup for $archive"
            continue
        }

        $dest = Join-Path -Path $backupDirResolved -ChildPath $archive
        $mount = $backupDirResolved + ':/backup'
        $dockerCmd = @('run', '--rm', '--volumes-from', $container, '-v', $mount, 'ubuntu', 'sh', '-c', "tar czf /backup/$archive -C $src .")
    }

    if ($WhatIf) {
        Write-Host ([string]::Format("WhatIf: would back up '{0}:{1}' -> {2}", $container, $src, $dest))
        continue
    }

    Write-Host ([string]::Format("Backing up '{0}:{1}' -> {2}", $container, $src, $dest))
    Write-Host "Running: docker $($dockerCmd -join ' ')"
    & docker @dockerCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Backup failed for $container (archive: $archive)"
    }
    else {
        Write-Host "Saved: $dest"
    }
}

Write-Host "Backup completed. Archives stored in: $backupDirResolved"
