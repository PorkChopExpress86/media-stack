# Immich Backup Script - Simplified
param(
    [string]$BackupDestination = "E:\Immich_Backups",
    [string]$UploadLocation = "S:\Immich\upload",
    [string]$DatabaseContainer = "immich_postgres"
)

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$backupPath = Join-Path $BackupDestination "immich_backup_$timestamp"

Write-Host "Immich Backup - $timestamp" -ForegroundColor Cyan
Write-Host "Destination: $backupPath" -ForegroundColor Yellow
Write-Host ""

$appContainers = @(
    "immich_server",
    "immich_microservices",
    "immich_machine_learning",
    "immich_web",
    "immich_redis"
)
$dbContainer = $DatabaseContainer

function Stop-Containers($names) {
    foreach ($n in $names) {
        Write-Host "Stopping $n ..." -ForegroundColor Yellow
        docker stop $n 2>$null | Out-Null
    }
}

function Start-Containers($names) {
    foreach ($n in $names) {
        Write-Host "Starting $n ..." -ForegroundColor Yellow
        docker start $n 2>$null | Out-Null
    }
}

# Create backup directories
New-Item -ItemType Directory -Path "$backupPath\database" -Force | Out-Null
New-Item -ItemType Directory -Path "$backupPath\uploads" -Force | Out-Null

Write-Host "Stopping Immich containers..." -ForegroundColor Yellow
Stop-Containers ($appContainers + $dbContainer)

try {
    # Start DB for dump
    Write-Host "Starting database for dump..." -ForegroundColor Yellow
    Start-Containers @($dbContainer)

    # Step 1: Database backup
    Write-Host "Step 1: Backing up database..." -ForegroundColor Yellow
    $dbFile = "$backupPath\database\dump.sql"
    docker exec -t $dbContainer pg_dumpall --clean --if-exists --username=postgres | Out-File -FilePath $dbFile -Encoding utf8
    if (Test-Path $dbFile) {
        $sizeMB = [math]::Round((Get-Item $dbFile).Length / 1MB, 2)
        Write-Host "Done! Database: $sizeMB MB" -ForegroundColor Green
    }

    # Stop DB after dump
    Write-Host "Stopping database after dump..." -ForegroundColor Yellow
    Stop-Containers @($dbContainer)

    # Step 2: Copy uploads  
    Write-Host ""
    Write-Host "Step 2: Copying uploads..." -ForegroundColor Yellow
    Write-Host "Source: $UploadLocation" -ForegroundColor Gray
    Write-Host "Destination: $backupPath\uploads" -ForegroundColor Gray

    # Gather rough totals for progress context (single pass)
    $srcStats = Get-ChildItem -Path $UploadLocation -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
    $totalFiles = $srcStats.Count
    $totalGB = [math]::Round(($srcStats.Sum / 1GB), 2)
    Write-Host "Planned copy: $totalFiles files (~$totalGB GB)" -ForegroundColor Gray

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    robocopy "$UploadLocation" "$backupPath\uploads" /E /R:3 /W:5 /MT:16 /ETA /TEE /NFL /NDL
    $copyExit = $LASTEXITCODE
    $sw.Stop()

    if ($copyExit -le 7) {
        $destStats = Get-ChildItem -Path "$backupPath\uploads" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
        $destFiles = $destStats.Count
        $destGB = [math]::Round(($destStats.Sum / 1GB), 2)
        Write-Host "Done! Copied $destFiles files ($destGB GB) in $([math]::Round($sw.Elapsed.TotalMinutes,2)) min" -ForegroundColor Green
    } else {
        Write-Host "Copy reported issues (exit code: $copyExit). Check robocopy output above." -ForegroundColor Red
    }
}
finally {
    Write-Host "Restarting Immich containers..." -ForegroundColor Yellow
    Start-Containers ($appContainers + $dbContainer)
}

Write-Host ""
Write-Host "Backup saved to: $backupPath" -ForegroundColor Cyan
