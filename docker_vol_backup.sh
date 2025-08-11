#!/bin/bash

set -e

BKUP_DIR="./vol_bkup"
mkdir -p "$BKUP_DIR"

echo "Finding all docker volumes not bind-mounted..."

# List all volumes
VOLUMES=$(docker volume ls -q)

# Loop through volumes
for VOL in $VOLUMES; do
    # Check if the volume is actually used as a named volume (not a bind mount)
    # We use 'docker inspect' to check if the mountpoint is under /var/lib/docker/volumes (standard for named volumes)
    MOUNTPOINT=$(docker volume inspect --format '{{.Mountpoint}}' "$VOL")
    if [[ "$MOUNTPOINT" =~ /var/lib/docker/volumes ]]; then
        echo "Backing up volume: $VOL"
        # Export volume using a temporary container
        docker run --rm -v "$VOL":/volume -v "$BKUP_DIR":/backup busybox \
            tar czf "/backup/${VOL}.tar.gz" -C /volume . 
    else
        echo "Skipping volume $VOL, looks like a bind mount"
    fi
done

echo "Backup complete. Files saved to $BKUP_DIR"
