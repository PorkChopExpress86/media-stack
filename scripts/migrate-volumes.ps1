<#!
.SYNOPSIS
  Migrate/duplicate Docker named volumes from one prefix to another (e.g. mediaserver_ -> media-stack_)
.DESCRIPTION
  Docker does not support in-place renaming of volumes. To "rename" volumes you must:
    1. Create a new volume
    2. Copy all data from the old volume to the new volume via a temporary container
    3. Update your compose project name / references
    4. Verify sizes & spot-check contents
    5. (Optional) Remove old volumes after successful validation

  This script automates steps 1–4. It LEAVES original volumes in place for rollback.

.PARAMETER OldPrefix
  Existing volume name prefix (e.g. mediaserver)
.PARAMETER NewPrefix
  Desired new volume name prefix (e.g. media-stack)
.PARAMETER DryRun
  Show planned operations without executing copy/create
.PARAMETER Force
  Overwrite (remove + recreate) target volumes if they already exist
.PARAMETER Verify
  After copy, compute size of source vs target (du -sb) and report differences
.PARAMETER IncludeWatchtower
  Include watchtower volume if present (watchtower volumes sometimes transient)
.EXAMPLE
  ./migrate-volumes.ps1 -OldPrefix mediaserver -NewPrefix media-stack -Verify
.EXAMPLE
  ./migrate-volumes.ps1 -OldPrefix mediaserver -NewPrefix media-stack -DryRun
.NOTES
  Requires Docker, PowerShell 5+, and alpine image (will be pulled automatically if missing).
#>
[CmdletBinding()]param(
    [Parameter(Mandatory = $true)][string]$OldPrefix,
    [Parameter(Mandatory = $true)][string]$NewPrefix,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Verify,
    [switch]$IncludeWatchtower
)

function Get-VolumesByPrefix {
    param([string]$Prefix)
    docker volume ls --format '{{.Name}}' 2>$null | Where-Object { $_ -like "${Prefix}_*" }
}

function Ensure-AlpineImage {
    if (-not (docker image ls --format '{{.Repository}}:{{.Tag}}' | Where-Object { $_ -eq 'alpine:latest' })) {
        Write-Host "Pulling alpine:latest ..." -ForegroundColor Cyan
        docker pull alpine:latest | Out-Null
    }
}

function New-VolumeIfNeeded {
    param([string]$Name)
    $exists = docker volume ls --format '{{.Name}}' | Where-Object { $_ -eq $Name }
    if ($exists) {
        if ($Force) {
            Write-Warning "Target volume '$Name' already exists. Removing due to -Force."
            docker volume rm $Name | Out-Null
        }
        else {
            Write-Host "Target volume '$Name' exists (skip create)." -ForegroundColor Yellow
            return
        }
    }
    if (-not $DryRun) {
        docker volume create $Name | Out-Null
    }
    Write-Host "Created target volume: $Name" -ForegroundColor Green
}

function Copy-VolumeData {
    param([string]$Source, [string]$Target)
    if ($DryRun) {
        Write-Host "[DRYRUN] Would copy data: $Source -> $Target" -ForegroundColor DarkGray
        return
    }
    # Use tar to preserve permissions & symlinks
    docker run --rm -v "${Source}:/from" -v "${Target}:/to" alpine:latest sh -c 'cd /from && tar cf - . | (cd /to && tar xpf -)' | Out-Null
    Write-Host "Copied data: $Source -> $Target" -ForegroundColor Green
}

function Get-VolumeSizeBytes {
    param([string]$Name)
    docker run --rm -v "${Name}:/data" alpine:latest sh -c "du -sb /data | cut -f1" 2>$null
}

# MAIN
$sourceVolumes = Get-VolumesByPrefix -Prefix $OldPrefix
if (-not $IncludeWatchtower) {
    $sourceVolumes = $sourceVolumes | Where-Object { $_ -notlike "${OldPrefix}_watchtower*" }
}
if (-not $sourceVolumes) { Write-Error "No volumes found with prefix '$OldPrefix_'"; exit 1 }

Write-Host "Discovered source volumes:" -ForegroundColor Cyan
$sourceVolumes | ForEach-Object { Write-Host "  $_" }

$mapping = @()
foreach ($src in $sourceVolumes) {
    $suffix = $src.Substring($OldPrefix.Length + 1) # remove prefix + underscore
    $dest = "${NewPrefix}_$suffix"
    $mapping += [pscustomobject]@{Source = $src; Target = $dest }
}

Write-Host "Planned mapping:" -ForegroundColor Cyan
$mapping | ForEach-Object { Write-Host "  $($_.Source) -> $($_.Target)" }

if ($DryRun) { Write-Host "Dry run complete."; exit 0 }

Ensure-AlpineImage

# Create & copy
foreach ($m in $mapping) {
    New-VolumeIfNeeded -Name $m.Target
    Copy-VolumeData -Source $m.Source -Target $m.Target
    if ($Verify) {
        $srcSize = Get-VolumeSizeBytes -Name $m.Source
        $dstSize = Get-VolumeSizeBytes -Name $m.Target
        $status = if ($srcSize -eq $dstSize) { '[OK]' } else { '[SIZE MISMATCH]' }
        $color = if ($status -eq '[OK]') { 'Green' } else { 'Yellow' }
        Write-Host "Verify $($m.Source) ($srcSize bytes) vs $($m.Target) ($dstSize bytes) => $status" -ForegroundColor $color
    }
}

Write-Host "Migration complete. Next steps:" -ForegroundColor Cyan
Write-Host "1. Update COMPOSE_PROJECT_NAME in .env (or remove it) to '$NewPrefix'" -ForegroundColor Gray
Write-Host "2. Run: docker compose down" -ForegroundColor Gray
Write-Host "3. Run: docker compose up -d (will use new volumes)" -ForegroundColor Gray
Write-Host "4. Validate containers function as expected" -ForegroundColor Gray
Write-Host "5. Remove old volumes when satisfied: docker volume rm $($sourceVolumes -join ' ')" -ForegroundColor Gray
Write-Host "Rollback: Keep COMPOSE_PROJECT_NAME as '$OldPrefix' and restart services to revert instantly." -ForegroundColor Gray
