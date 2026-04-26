#!/bin/bash
set -euo pipefail

# Pre-start guard for the arr-stack. Called by arr-stack.service before
# docker compose up. Fails hard if the WD drive is not mounted and accessible
# with the expected permissions, preventing qBittorrent from writing to the
# NVMe root filesystem.

MOUNT_POINT="/mnt/wd_hdd_1tb"
QBT_DIR="$MOUNT_POINT/qbittorrent"
EXPECTED_UID=1000  # matches PUID in arr-stack compose

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

log "Checking WD drive mount and permissions..."

mountpoint -q "$MOUNT_POINT" \
    || die "$MOUNT_POINT is not mounted. Refusing to start arr-stack."

log "$MOUNT_POINT is mounted: $(df -h "$MOUNT_POINT" | awk 'NR==2')"

# Ensure the qbittorrent downloads directory exists and is writable
mkdir -p "$QBT_DIR"

OWNER_UID=$(stat -c '%u' "$QBT_DIR")
if [[ "$OWNER_UID" -ne "$EXPECTED_UID" ]]; then
    log "Fixing ownership of $QBT_DIR (was UID $OWNER_UID, expected $EXPECTED_UID)..."
    chown -R "${EXPECTED_UID}:${EXPECTED_UID}" "$QBT_DIR"
fi

# Verify write access
PROBE="$QBT_DIR/.mount_check"
touch "$PROBE" 2>/dev/null && rm -f "$PROBE" \
    || die "$QBT_DIR is not writable. Check permissions on $MOUNT_POINT."

log "Mount check passed. $QBT_DIR is ready."
