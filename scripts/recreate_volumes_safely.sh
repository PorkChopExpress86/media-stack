#!/bin/bash
set -euo pipefail

# Script to safely backup, remove, and recreate Docker volumes to fix "already exists" warnings
# Usage: sudo ./recreate_volumes_safely.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_ROOT="${PROJECT_DIR}/vol_bkup/safety_recreate_$(date +"%Y%m%d_%H%M%S")"

echo "========================================================"
echo "Safety Recreate Volume Script"
echo "Backup Location: $BACKUP_ROOT"
echo "========================================================"
echo ""

mkdir -p "$BACKUP_ROOT"

# List of volumes to process (must match docker-compose.yml service definitions)
# Format: VOLUME_NAME
VOLUMES=(
    "media-stack_nginx_data"
    "media-stack_letsencrypt"
    "media-stack_prowlarr_data"
    "media-stack_radarr_data"
    "media-stack_sonarr_data"
    "media-stack_gluetun_data"
    "media-stack_bazarr_data"
    "media-stack_pinchflat_data"
    "media-stack_decluttarr_data"
    "media-stack_immich_server_data"
    "media-stack_immich_redis_data" # Added specifically
    "media-stack_plex_data"
    "media-stack_audiobookshelf_data"
    "media-stack_jellyfin_cache"
    "media-stack_jellyfin_config" # Added specifically usually needed
    "media-stack_qbittorrent_data"
    "media-stack_prometheus_data"
    "media-stack_grafana_data"
    "media-stack_homeassistant_data"
    "media-stack_model-cache"
    "media-stack_watchtower_data"
    "media-stack_vpn_data"       # In case it exists
)

# 1. Stop Containers
echo "Step 1: Stopping containers..."
cd "$PROJECT_DIR"
docker compose down

echo ""
echo "Step 2: Processing volumes..."

process_volume() {
    local vol_name="$1"
    local archive_name="${vol_name}.tar.gz"
    
    # Check if volume exists
    if ! docker volume inspect "$vol_name" >/dev/null 2>&1; then
        echo "[SKIP] Volume $vol_name does not exist."
        return
    fi
    
    echo "------------------------------------------------"
    echo "Processing $vol_name"
    
    # BACKUP
    echo "  -> Backing up..."
    docker run --rm \
        -v "$vol_name:/volume_data" \
        -v "$BACKUP_ROOT:/backup" \
        ubuntu bash -c "cd /volume_data && tar czf /backup/$archive_name ."
        
    if [[ ! -s "$BACKUP_ROOT/$archive_name" ]]; then
        echo "  [ERROR] Backup failed or empty for $vol_name. Aborting this volume."
        return
    fi
    echo "  -> Backup verified: $(ls -lh "$BACKUP_ROOT/$archive_name" | awk '{print $5}')"
    
    # REMOVE
    echo "  -> Removing old volume..."
    docker volume rm "$vol_name"
    
    # RECREATE (We will do bulk recreate later via 'up', but for now we essentially cleared relevant ones)
    # Actually, to be safe and atomic, we rely on 'docker compose up' creating it correctly.
    # But to restore NOW, we need it to exist.
    
    echo "  -> Re-creating volume via docker volume create (placeholder)..."
    # We create it manually to ensure we can restore to it immediately.
    # When docker compose up runs later, it will see this volume exists. 
    # CRITICAL: We don't want the warning again. 
    # WAIT. The warning usually comes because the label `com.docker.compose.project` is missing.
    # If we manually create it, it might still lack labels unless we use complex flags.
    # BETTER APPROACH:
    # 1. Backup all.
    # 2. Remove all.
    # 3. 'docker compose create' (or up --no-start) to let COMPOSE create them with correct labels.
    # 4. Restore all.
}

# --- MODIFIED LOGIC: SEPARATE PHASES ---

# Phase 1: Backup All relevant volumes
FAILED_BACKUPS=0
for vol in "${VOLUMES[@]}"; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        echo "Backing up $vol..."
        docker run --rm \
            -v "$vol:/volume_data" \
            -v "$BACKUP_ROOT:/backup" \
            ubuntu bash -c "cd /volume_data && tar czf /backup/$vol.tar.gz ."
            
        if [[ ! -s "$BACKUP_ROOT/$vol.tar.gz" ]]; then
            echo "  [ERROR] Backup failed for $vol"
            FAILED_BACKUPS=1
        fi
    fi
done

if [[ "$FAILED_BACKUPS" -eq 1 ]]; then
    echo "One or more backups failed. Aborting script before deletion."
    exit 1
fi

echo ""
echo "All backups successful. Proceeding to removal."
echo ""

# Phase 2: Remove Volumes
for vol in "${VOLUMES[@]}"; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        echo "Removing $vol..."
        docker volume rm "$vol"
    fi
done

echo ""
echo "Phase 3: Recreating volumes via Docker Compose..."
# This command ensures volumes are created with the correct project labels
docker compose up --no-start

echo ""
echo "Phase 4: Restoring Data..."

for vol in "${VOLUMES[@]}"; do
    archive="$BACKUP_ROOT/$vol.tar.gz"
    if [[ -f "$archive" ]]; then
        # Check if volume was actually created by compose (it might not be if service was disabled or removed)
        if docker volume inspect "$vol" >/dev/null 2>&1; then
            echo "Restoring $vol..."
             docker run --rm \
                -v "$vol:/volume_data" \
                -v "$BACKUP_ROOT:/backup" \
                ubuntu bash -c "rm -rf /volume_data/* && cd /volume_data && tar xzf /backup/$vol.tar.gz"
        else
            echo "[WARN] Volume $vol was backed up but does not exist after 'docker compose up'. Skipping restore."
        fi
    fi
done

echo ""
echo "------------------------------------------------"
echo "Operation Complete."
echo "You can now start your stack with: docker compose up -d"
echo "------------------------------------------------"
