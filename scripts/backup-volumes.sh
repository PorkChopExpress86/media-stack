#!/bin/bash

set -euo pipefail

# Backup Docker volumes to timestamped directory
# Creates compressed archives for all named volumes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_ROOT="${PROJECT_DIR}/vol_bkup"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"

echo "Creating backup directory: ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"

backup_volume() {
	local volume_name="$1"   # Docker volume name (e.g., media-stack_nginx_data)
	local mount_path="$2"    # Path inside container where volume is mounted
	local archive_name="$3"  # Backup filename

	if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
		echo "[SKIP] Volume does not exist: $volume_name"
		return 0
	fi

	echo "[BACKUP] $volume_name -> $archive_name"
	docker run --rm \
		-v "$volume_name:$mount_path" \
		-v "$BACKUP_DIR:/backup" \
		ubuntu bash -c "cd '$mount_path' && tar czf '/backup/$archive_name' ."
}

# nginx volumes
backup_volume media-stack_nginx_data        /data            media-stack_nginx_data.tar.gz
backup_volume media-stack_letsencrypt       /etc/letsencrypt media-stack_letsencrypt.tar.gz

# Jellyfin volumes
backup_volume media-stack_jellyfin_config   /config          media-stack_jellyfin_config.tar.gz
backup_volume media-stack_jellyfin_cache    /cache           media-stack_jellyfin_cache.tar.gz

# Plex volume
backup_volume media-stack_plex_data         /config          media-stack_plex_data.tar.gz

# gluetun (vpn) volume
backup_volume media-stack_gluetun_data      /gluetun         media-stack_gluetun_data.tar.gz

# *ARR services
backup_volume media-stack_prowlarr_data     /config          media-stack_prowlarr_data.tar.gz
backup_volume media-stack_radarr_data       /config          media-stack_radarr_data.tar.gz
backup_volume media-stack_sonarr_data       /config          media-stack_sonarr_data.tar.gz
backup_volume media-stack_bazarr_data       /config          media-stack_bazarr_data.tar.gz

# qbittorrent
backup_volume media-stack_qbittorrent_data  /config          media-stack_qbittorrent_data.tar.gz

# decluttarr
backup_volume media-stack_decluttarr_data   /config          media-stack_decluttarr_data.tar.gz

# Audiobookshelf
backup_volume media-stack_audiobookshelf_data /config        media-stack_audiobookshelf_data.tar.gz

# Pinchflat
backup_volume media-stack_pinchflat_data    /config          media-stack_pinchflat_data.tar.gz

# Immich volumes
backup_volume media-stack_model-cache       /cache           media-stack_model-cache.tar.gz
backup_volume media-stack_immich_redis_data /data            media-stack_immich_redis_data.tar.gz
backup_volume media-stack_immich_server_data /data           media-stack_immich_server_data.tar.gz

# Home Assistant
backup_volume media-stack_homeassistant_data /config         media-stack_homeassistant_data.tar.gz

# Watchtower
backup_volume media-stack_watchtower_data   /data            media-stack_watchtower_data.tar.gz

echo ""
echo "Backup completed successfully!"
echo "Location: ${BACKUP_DIR}"
echo ""
echo "To restore these backups, run: ./scripts/restore-volumes.sh ${TIMESTAMP}"