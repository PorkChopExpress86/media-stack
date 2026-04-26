#!/bin/bash
set -euo pipefail

# =============================================================================
# recover-qbt-downloads.sh — Recovers qBittorrent downloads from NVMe back
# onto the wd_hdd_1tb drive after it was missing at boot.
#
# Run this once after reconnecting the WD drive. It will:
#   1. Stop qBittorrent
#   2. Stash NVMe data to /tmp
#   3. Mount the drive over /mnt/wd_hdd_1tb
#   4. rsync data onto the drive
#   5. Verify file counts match
#   6. Remove the temp stash
#   7. Restart qBittorrent
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARR_STACK_DIR="$PROJECT_DIR/arr-stack"
MOUNT_POINT="/mnt/wd_hdd_1tb"
QBT_SUBDIR="qbittorrent"
TEMP_STASH="/mnt/qbt_data_recovery"

# --- Helpers -----------------------------------------------------------------
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die()  { log "ERROR: $*" >&2; exit 1; }
confirm() {
    read -r -p "$1 [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

# --- Preflight ---------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "Must be run as root (sudo $0)"

log "=== qBittorrent download recovery ==="

# Verify the drive is detected
if ! lsblk -f | grep -q "wd_hdd_1tb"; then
    die "No device with label 'wd_hdd_1tb' found. Is the drive connected?"
fi

# Check if it's already mounted
if mountpoint -q "$MOUNT_POINT"; then
    log "Drive is already mounted at $MOUNT_POINT."
    # Check if there's stale NVMe data to recover
    if [[ ! -d "$TEMP_STASH" ]]; then
        log "Nothing to recover — drive is mounted and no stash found."
        exit 0
    fi
    log "Found stash at $TEMP_STASH — resuming recovery from step 4."
else
    # Check there's actually data on the NVMe to move
    NVMe_DATA="$MOUNT_POINT/$QBT_SUBDIR"
    if [[ ! -d "$NVMe_DATA" ]] || [[ -z "$(ls -A "$NVMe_DATA" 2>/dev/null)" ]]; then
        log "No data found at $NVMe_DATA — nothing to recover. Mounting drive only."
        mount "$MOUNT_POINT"
        log "Drive mounted. Done."
        exit 0
    fi

    DATA_SIZE=$(du -sh "$NVMe_DATA" 2>/dev/null | cut -f1)
    log "Found $DATA_SIZE of data at $NVMe_DATA (currently on NVMe root drive)."

    confirm "Proceed with recovery?" || { log "Aborted."; exit 0; }

    # --- Step 1: Stop qBittorrent --------------------------------------------
    log "Step 1/7 — Stopping qBittorrent..."
    docker compose -f "$ARR_STACK_DIR/compose.yml" stop qbittorrent
    log "qBittorrent stopped."

    # --- Step 2: Stash NVMe data ---------------------------------------------
    log "Step 2/7 — Moving data to temp stash at $TEMP_STASH..."
    [[ -d "$TEMP_STASH" ]] && die "Stash $TEMP_STASH already exists — remove it manually before retrying."
    mv "$NVMe_DATA" "$TEMP_STASH"
    log "Data stashed."

    # --- Step 3: Mount the drive ---------------------------------------------
    log "Step 3/7 — Mounting $MOUNT_POINT..."
    mount "$MOUNT_POINT"
    log "Drive mounted."
fi

# Check drive has enough space
REQUIRED_KB=$(du -sk "$TEMP_STASH" 2>/dev/null | cut -f1)
AVAILABLE_KB=$(df -k "$MOUNT_POINT" | awk 'NR==2 {print $4}')
if (( REQUIRED_KB > AVAILABLE_KB )); then
    REQUIRED_HR=$(numfmt --to=iec $((REQUIRED_KB * 1024)))
    AVAILABLE_HR=$(numfmt --to=iec $((AVAILABLE_KB * 1024)))
    die "Not enough space on drive: need $REQUIRED_HR, have $AVAILABLE_HR."
fi

# --- Step 4: rsync data onto drive -------------------------------------------
log "Step 4/7 — Copying data to $MOUNT_POINT/$QBT_SUBDIR (this may take a while)..."
mkdir -p "$MOUNT_POINT/$QBT_SUBDIR"
rsync -a --info=progress2 "$TEMP_STASH/" "$MOUNT_POINT/$QBT_SUBDIR/"
log "rsync complete."

# --- Step 5: Verify file counts ----------------------------------------------
log "Step 5/7 — Verifying file counts..."
SRC_COUNT=$(find "$TEMP_STASH" -type f | wc -l)
DST_COUNT=$(find "$MOUNT_POINT/$QBT_SUBDIR" -type f | wc -l)
log "Source: $SRC_COUNT files | Destination: $DST_COUNT files"
if [[ "$SRC_COUNT" -ne "$DST_COUNT" ]]; then
    die "File count mismatch ($SRC_COUNT vs $DST_COUNT). Stash preserved at $TEMP_STASH. Investigate before retrying."
fi
log "File counts match."

# --- Step 6: Remove temp stash -----------------------------------------------
log "Step 6/7 — Removing temp stash..."
rm -rf "$TEMP_STASH"
log "Stash removed."

# --- Step 7: Restart qBittorrent ---------------------------------------------
log "Step 7/7 — Starting qBittorrent..."
docker compose -f "$ARR_STACK_DIR/compose.yml" start qbittorrent
log "qBittorrent started."

log "=== Recovery complete. ==="
df -h "$MOUNT_POINT"
