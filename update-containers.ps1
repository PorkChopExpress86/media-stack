function Update-Compose {
    Set-Location -Path $PSScriptRoot

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logFilePath = Join-Path -Path $PSScriptRoot -ChildPath "file.log"
    $pullOutput = docker compose pull 2>&1

    Write-Host "$timestamp - Pulling latest images..." -ForegroundColor Cyan
    $pullOutput | ForEach-Object {
        Write-Host $_
        Add-Content -Path $logFilePath -Value $_
    }

    Add-Content -Path $logFilePath -Value "$timestamp - Docker compose pull completed."

    # Extract updated services
    $updated = $pullOutput | Where-Object {
        $_ -match "Downloaded newer image|Pull complete|Status: Downloaded"
    }

    if ($updated.Count -gt 0) {
        Write-Host "`n$timestamp - New images detected for the following containers:" -ForegroundColor Green
        Add-Content -Path $logFilePath -Value "$timestamp - New images pulled:"
        foreach ($line in $updated) {
            Write-Host "  → $line" -ForegroundColor Yellow
            Add-Content -Path $logFilePath -Value "  → $line"
        }

        Write-Host "`nRestarting containers..." -ForegroundColor Cyan
        Add-Content -Path $logFilePath -Value "$timestamp - Restarting containers."
        docker compose down
        docker compose up -d
        docker image prune -af
    }
    else {
        Write-Host "`n$timestamp - No new images found. Skipping container restart." -ForegroundColor Gray
        Add-Content -Path $logFilePath -Value "$timestamp - No new images. Containers not restarted."
    }
}

function Initialize-Log {
    $logFilePath = Join-Path -Path $PSScriptRoot -ChildPath "file.log"
    if (!(Test-Path $logFilePath)) {
        New-Item -ItemType File -Path $logFilePath
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp - Starting update check..." -ForegroundColor Cyan
    Add-Content -Path $logFilePath -Value "$timestamp - Starting update check."
}

Initialize-Log
Update-Compose
