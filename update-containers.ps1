
function Update-Compose{
    Set-Location -Path "C:\Users\Blake\OneDrive\Desktop\Docker"
    docker compose pull; docker compose down; docker compose up -d
}

function Log-Run {
    $logFilePath = "C:\Users\Blake\OneDrive\Desktop\Docker\file.log"
    if(!(Test-Path $logFilePath)) {
        New-Item -ItemType File -Path $logFilePath
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFilePath -Value "$timestamp - Update Compose has been run."
}

Log-Run
Update-Compose

