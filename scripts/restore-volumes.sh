#!/bin/bash

set -euo pipefail

# Restore Docker named volumes from compressed backups
# Usage: ./restore-volumes.sh [timestamp]
#   If timestamp is provided, restores from ./vol_bkup/[timestamp]/
#   Otherwise, prompts to choose from available backups or uses latest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_ROOT="${PROJECT_DIR}/vol_bkup"

# Function to list available backups
list_backups() {
	echo "Available backups:"
	local i=1
	local backups=()
	
	# Check for timestamped directories
	if ls -d "${BACKUP_ROOT}"/*/ &>/dev/null; then
		while IFS= read -r dir; do
			local timestamp=$(basename "$dir")
			# Skip if it's just files in vol_bkup root
			if [[ "$timestamp" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
				backups+=("$timestamp")
				echo "  $i) $timestamp"
				((i++))
			fi
		done < <(ls -dt "${BACKUP_ROOT}"/*/ 2>/dev/null || true)
	fi
	
	# Also check for files in root
	if ls "${BACKUP_ROOT}"/*.tar.gz &>/dev/null; then
		backups+=("root")
		echo "  $i) root (legacy backups in vol_bkup/)"
	fi
	
	echo "${backups[@]}"
}

# Determine backup directory
if [[ $# -eq 1 ]]; then
	TIMESTAMP="$1"
	if [[ "$TIMESTAMP" == "root" ]]; then
		BACKUP_DIR="$BACKUP_ROOT"
	else
		BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
	fi
else
	# Interactive selection
	backups_str=$(list_backups)
	if [[ -z "$backups_str" ]] || [[ "$backups_str" == "Available backups:" ]]; then
		echo "No backups found in $BACKUP_ROOT" >&2
		exit 1
	fi
	
	# Convert to array
	read -ra backups_array <<< "${backups_str#*$'\n'}"
	
	if [[ ${#backups_array[@]} -eq 1 ]]; then
		# Only one backup, use it
		BACKUP_DIR="${BACKUP_ROOT}/${backups_array[0]}"
		echo "Using only available backup: ${backups_array[0]}"
	else
		# Multiple backups, prompt user
		echo ""
		read -p "Enter number to restore (or press Enter for most recent): " choice
		
		if [[ -z "$choice" ]]; then
			# Use most recent (first in list)
			BACKUP_DIR="${BACKUP_ROOT}/${backups_array[0]}"
			echo "Using most recent backup: ${backups_array[0]}"
		else
			idx=$((choice - 1))
			if [[ $idx -ge 0 ]] && [[ $idx -lt ${#backups_array[@]} ]]; then
				selected="${backups_array[$idx]}"
				if [[ "$selected" == "root" ]]; then
					BACKUP_DIR="$BACKUP_ROOT"
				else
					BACKUP_DIR="${BACKUP_ROOT}/${selected}"
				fi
				echo "Using backup: $selected"
			else
				echo "Invalid selection" >&2
				exit 1
			fi
		fi
	fi
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
	echo "Backup directory not found: $BACKUP_DIR" >&2
	exit 1
fi

echo "Restoring from: $BACKUP_DIR"
echo ""

restore_volume() {
	local volume_name="$1"   # full docker volume name (e.g., media-stack_radarr_data)
	local mount_path="$2"    # path inside temporary ubuntu container to mount the volume
	local archive_name="$3"  # backup archive filename

	local archive_path="$BACKUP_DIR/$archive_name"

	if [[ ! -f "$archive_path" ]]; then
		echo "[SKIP] Missing backup: $archive_name"
		return 0
	fi

	# Create volume if missing
	if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
		echo "[INFO] Creating missing volume: $volume_name"
		docker volume create "$volume_name" >/dev/null
	fi

	echo "[RESTORE] $volume_name <- $archive_name"
	docker run --rm \
		-v "$volume_name:$mount_path" \
		-v "$BACKUP_DIR:/backup" \
		ubuntu bash -c "rm -rf '$mount_path'/* '$mount_path'/.[!.]* 2>/dev/null || true; cd '$mount_path' && tar xzf '/backup/$archive_name'"
}

# nginx volumes
# restore_volume media-stack_nginx_data        /data            nginx_data.tar.gz
# restore_volume media-stack_letsencrypt       /etc/letsencrypt letsencrypt.tar.gz

# Jellyfin volumes
# restore_volume media-stack_jellyfin_config   /config          jellyfin_config.tar.gz
# restore_volume media-stack_jellyfin_cache    /cache           jellyfin_cache.tar.gz

# Plex volume
# restore_volume media-stack_plex_data         /config          plex_data.tar.gz

# gluetun (vpn) volume
restore_volume media-stack_gluetun_data      /gluetun         gluetun_data.tar.gz

# *ARR services
restore_volume media-stack_prowlarr_data     /config          prowlarr_data.tar.gz
restore_volume media-stack_radarr_data       /config          radarr_data.tar.gz
restore_volume media-stack_sonarr_data       /config          sonarr_data.tar.gz
restore_volume media-stack_bazarr_data       /config          bazarr_data.tar.gz

# qbittorrent
restore_volume media-stack_qbittorrent_data  /config          qbittorrent_data.tar.gz

# decluttarr
restore_volume media-stack_decluttarr_data   /config          decluttarr_data.tar.gz

# Audiobookshelf
restore_volume media-stack_audiobookshelf_data /config        audiobookshelf_data.tar.gz

# Pinchflat
restore_volume media-stack_pinchflat_data    /config          pinchflat_data.tar.gz

# Immich volumes
restore_volume media-stack_model-cache       /cache           model-cache.tar.gz
restore_volume media-stack_immich_redis_data /data            immich_redis_data.tar.gz
restore_volume media-stack_immich_server_data /data           immich_server_data.tar.gz

# Home Assistant
restore_volume media-stack_homeassistant_data /config         homeassistant_data.tar.gz

# Watchtower
restore_volume media-stack_watchtower_data   /data            watchtower_data.tar.gz

echo ""
echo "Restore complete! You can start services with: docker compose up -d"