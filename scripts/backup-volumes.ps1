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
    [switch]$WhatIf
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

foreach ($item in $backups) {
    $container = $item.container
    $archive = $item.archive
    $src = $item.src

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
