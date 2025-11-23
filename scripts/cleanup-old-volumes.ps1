<#
.SYNOPSIS
  Remove old mediaserver_* volumes after successful migration to media-stack_*
.DESCRIPTION
  This script removes the original mediaserver_* prefixed volumes that remain after
  migrating to media-stack_*. Only run this after verifying all services work correctly
  with the new volumes.

  By default, this script runs in WhatIf mode for safety. Use -Force to actually delete.

.PARAMETER Force
  Actually delete the volumes (otherwise just shows what would be deleted)
.PARAMETER Prefix
  The old prefix to remove (default: mediaserver)
.EXAMPLE
  .\cleanup-old-volumes.ps1
  # Shows what would be deleted (dry run)
.EXAMPLE
  .\cleanup-old-volumes.ps1 -Force
  # Actually deletes the old mediaserver_* volumes
.NOTES
  CAUTION: This operation cannot be undone! Ensure your new volumes work correctly first.
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$Prefix = "mediaserver"
)

function Get-OldVolumes {
    param([string]$Prefix)
    docker volume ls --format '{{.Name}}' 2>$null | Where-Object { $_ -like "${Prefix}_*" }
}

function Get-VolumeSize {
    param([string]$VolumeName)
    $bytes = docker run --rm -v "${VolumeName}:/data" alpine:latest sh -c "du -sb /data | cut -f1" 2>$null
    if ($bytes) {
        $mb = [math]::Round($bytes / 1MB, 2)
        return "${mb} MB"
    }
    return "unknown"
}

# Main
$oldVolumes = Get-OldVolumes -Prefix $Prefix

if (-not $oldVolumes) {
    Write-Host "No volumes found with prefix '${Prefix}_'" -ForegroundColor Green
    exit 0
}

Write-Host "`nFound old volumes to remove:" -ForegroundColor Cyan
$totalSize = 0
foreach ($vol in $oldVolumes) {
    $size = Get-VolumeSize -VolumeName $vol
    Write-Host "  $vol ($size)" -ForegroundColor Gray
}

Write-Host "`nThese volumes are no longer used after migration to media-stack_*" -ForegroundColor Yellow

if (-not $Force) {
    Write-Host "`n[DRY RUN] No volumes deleted. Use -Force to actually remove them." -ForegroundColor Magenta
    Write-Host "Command that would be executed:" -ForegroundColor Gray
    Write-Host "  docker volume rm $($oldVolumes -join ' ')" -ForegroundColor DarkGray
    exit 0
}

Write-Host "`nWARNING: About to delete $($oldVolumes.Count) volumes. This cannot be undone!" -ForegroundColor Red
$confirmation = Read-Host "Type 'DELETE' to confirm"

if ($confirmation -ne 'DELETE') {
    Write-Host "Aborted. No volumes deleted." -ForegroundColor Yellow
    exit 1
}

Write-Host "`nDeleting volumes..." -ForegroundColor Cyan
$success = 0
$failed = 0

foreach ($vol in $oldVolumes) {
    try {
        docker volume rm $vol 2>&1 | Out-Null
        Write-Host "  ✓ Deleted: $vol" -ForegroundColor Green
        $success++
    }
    catch {
        Write-Host "  ✗ Failed: $vol ($_)" -ForegroundColor Red
        $failed++
    }
}

Write-Host "`nCleanup complete:" -ForegroundColor Cyan
Write-Host "  Deleted: $success volumes" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "  Failed: $failed volumes" -ForegroundColor Red
}

$remaining = Get-OldVolumes -Prefix $Prefix
if ($remaining) {
    Write-Host "`nRemaining ${Prefix}_ volumes:" -ForegroundColor Yellow
    $remaining | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
}
else {
    Write-Host "`nAll ${Prefix}_ volumes removed successfully!" -ForegroundColor Green
}
