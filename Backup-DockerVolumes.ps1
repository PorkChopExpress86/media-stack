param(
    [string]$ComposeFile = ".\docker-compose.yaml",
    [string]$BackupRoot = "C:\Users\Blake\OneDrive\DockerBackup"
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupPath = Join-Path $BackupRoot "backup_$timestamp"
New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null

Write-Output ""
Write-Output "Backing up ALL Docker volumes..."

# Stage 1: Backup all volumes via temporary container
$allVolumes = docker volume ls -q
foreach ($vol in $allVolumes) {
    $tempContainer = "backup_temp_$vol"
    $tempFolder = Join-Path $env:TEMP "$vol"

    if (Test-Path $tempFolder) { Remove-Item $tempFolder -Recurse -Force }
    New-Item -ItemType Directory -Path $tempFolder | Out-Null

    # Start temporary container with the volume mounted
    docker run --rm -d --name $tempContainer -v "${vol}:/data" alpine sleep 10 > $null
    docker cp "${tempContainer}:/data" "$tempFolder"
    docker rm -f $tempContainer > $null

    # Compress the contents
    $outFile = Join-Path $BackupPath "${vol}_volume.tar.gz"
    tar -czf $outFile -C "$tempFolder\data" .

    Write-Output "Backed up volume: $vol to $outFile"

    Remove-Item $tempFolder -Recurse -Force
}

# Stage 2: Bind mount backups (same as before)
Write-Output ""
Write-Output "Parsing bind mounts from $ComposeFile..."

$services = & yq e '.services | keys | .[]' $ComposeFile

foreach ($service in $services) {
    $mounts = & yq e ".services.$service.volumes[]" $ComposeFile

    foreach ($mount in $mounts) {
        $cleanMount = $mount.Trim('"')
        $parts = $cleanMount -split ":", 2

        if ($parts.Count -lt 2) {
            Write-Warning "Skipping malformed mount: $cleanMount"
            continue
        }

        $src = $parts[0]
        $dst = $parts[1]

        if ($src -like "*/" -or $src -like "*:\" -or $src.StartsWith(".")) {
            $mountName = Split-Path -Path $dst -Leaf
            $fullSrcPath = Resolve-Path $src
            $outFile = Join-Path $BackupPath "${service}_${mountName}_bind.tar.gz"
            Write-Output "Backing up bind mount: $fullSrcPath to $outFile"
            tar -czf $outFile -C $fullSrcPath .
        }
    }
}

Write-Output ""
Write-Output "Backup complete. Files saved to: $BackupPath"
