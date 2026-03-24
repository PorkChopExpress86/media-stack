#!/bin/bash
set -euo pipefail

# =============================================================================
# backup-all.sh — Backs up Docker volumes, bind-mounted data, and Postgres DB
#
# Designed to run weekly via cron:
#   0 3 * * 0 /mnt/samsung/Docker/MediaServer/scripts/linux/backup-all.sh \
#     >> /mnt/samsung/Docker/MediaServer/vol_bkup/backup.log 2>&1
#
# Retains the most recent MAX_BACKUPS backup sets and deletes older ones.
# =============================================================================

# --- Configuration -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BKUP_BASE_DIR="${PROJECT_DIR}/vol_bkup"
COMPOSE_DIR="$PROJECT_DIR"
MAX_BACKUPS=14

# Load .env for DB credentials and bind-mount paths
ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"

        # Skip blank lines and full-line comments
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Parse KEY=VALUE entries without executing shell code
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            # Strip optional surrounding quotes
            if [[ "$value" =~ ^\"(.*)\"$ ]]; then
                value="${BASH_REMATCH[1]}"
            elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi

            export "$key=$value"
        fi
    done < "$ENV_FILE"
else
    echo "ERROR: .env file not found at $ENV_FILE"
    exit 1
fi

# --- Helper functions --------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

create_backup_dir() {
    local date_stamp
    date_stamp=$(date +%Y%m%d)
    local suffix=1

    while true; do
        local formatted
        formatted=$(printf "%03d" $suffix)
        BKUP_DIR="${BKUP_BASE_DIR}/${date_stamp}-${formatted}"
        if [[ ! -d "$BKUP_DIR" ]]; then
            break
        fi
        suffix=$((suffix + 1))
    done

    mkdir -p "$BKUP_DIR"
    echo "$BKUP_DIR"
}

# --- Start backup ------------------------------------------------------------
log "========== Starting full backup =========="

BKUP_DIR=$(create_backup_dir)
log "Backup directory: $BKUP_DIR"

# Initialize report
REPORT_FILE="${BKUP_DIR}/backup_report.txt"
{
    echo "Backup Report - $(date)"
    echo "================================================"
    printf "%-35s | %-10s | %s\n" "Item" "Size" "Type"
    printf "%-35s | %-10s | %s\n" "-----------------------------------" "----------" "------"
} > "$REPORT_FILE"

ERRORS=0

# --- 1. Back up named Docker volumes ----------------------------------------
log "--- Phase 1: Named Docker volumes ---"

cd "$COMPOSE_DIR"
# Always prefer this stack's project name from .env to avoid matching
# unrelated compose projects that may also be running on the same host.
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-media-stack}"
log "Project name: $PROJECT_NAME"

VOL_KEYS=$(docker compose config --volumes 2>/dev/null || true)
if [[ -z "$VOL_KEYS" ]]; then
    log "WARNING: No compose volumes found. Skipping volume backup."
else
    for VOL_KEY in $VOL_KEYS; do
        # Find actual Docker volume name
        VOL_NAME=$(docker volume ls -q \
            --filter "label=com.docker.compose.project=${PROJECT_NAME}" \
            --filter "label=com.docker.compose.volume=${VOL_KEY}" 2>/dev/null | head -1)

        if [[ -z "$VOL_NAME" ]]; then
            VOL_NAME="${PROJECT_NAME}_${VOL_KEY}"
            if ! docker volume inspect "$VOL_NAME" > /dev/null 2>&1; then
                log "  SKIP: Volume not found for key '$VOL_KEY'"
                printf "%-35s | %-10s | %s\n" "$VOL_KEY" "SKIP" "volume" >> "$REPORT_FILE"
                continue
            fi
        fi

        log "  Backing up volume: $VOL_KEY ($VOL_NAME)"
        BKUP_FILE="${BKUP_DIR}/${VOL_KEY}.tar.gz"

        if docker run --rm \
            -v "${VOL_NAME}:/volume:ro" \
            -v "${BKUP_DIR}:/backup" \
            busybox \
            tar czf "/backup/${VOL_KEY}.tar.gz" -C /volume . 2>/dev/null; then
            FILE_SIZE=$(du -h "$BKUP_FILE" | cut -f1)
            printf "%-35s | %-10s | %s\n" "$VOL_KEY" "$FILE_SIZE" "volume" >> "$REPORT_FILE"
        else
            log "  ERROR: Failed to back up volume $VOL_KEY"
            printf "%-35s | %-10s | %s\n" "$VOL_KEY" "FAILED" "volume" >> "$REPORT_FILE"
            ERRORS=$((ERRORS + 1))
        fi
    done
fi

# --- 2. Back up bind-mounted data directories --------------------------------
log "--- Phase 2: Bind-mounted data ---"

declare -A BIND_MOUNTS=(
    ["derbynet"]="${PROJECT_DIR}/data/derbynet"
    ["budget"]="${PROJECT_DIR}/data/budget"
    ["minecraft-survival"]="${PROJECT_DIR}/data/survival"
    ["minecraft-creative"]="${PROJECT_DIR}/data/creative"
)

for MOUNT_NAME in "${!BIND_MOUNTS[@]}"; do
    MOUNT_PATH="${BIND_MOUNTS[$MOUNT_NAME]}"

    if [[ ! -d "$MOUNT_PATH" ]]; then
        log "  SKIP: Bind mount path not found: $MOUNT_PATH"
        printf "%-35s | %-10s | %s\n" "$MOUNT_NAME" "SKIP" "bind" >> "$REPORT_FILE"
        continue
    fi

    log "  Backing up bind mount: $MOUNT_NAME ($MOUNT_PATH)"
    BKUP_FILE="${BKUP_DIR}/bind_${MOUNT_NAME}.tar.gz"

    if tar czf "$BKUP_FILE" -C "$MOUNT_PATH" . 2>/dev/null; then
        FILE_SIZE=$(du -h "$BKUP_FILE" | cut -f1)
        printf "%-35s | %-10s | %s\n" "$MOUNT_NAME" "$FILE_SIZE" "bind" >> "$REPORT_FILE"
    else
        log "  ERROR: Failed to back up bind mount $MOUNT_NAME"
        printf "%-35s | %-10s | %s\n" "$MOUNT_NAME" "FAILED" "bind" >> "$REPORT_FILE"
        ERRORS=$((ERRORS + 1))
    fi
done

# --- 3. Postgres logical dump (Immich database) -----------------------------
log "--- Phase 3: Postgres database dump ---"

DB_CONTAINER="immich_postgres"
PG_DUMP_FILE="${BKUP_DIR}/immich_postgres_dump.sql.gz"

if docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    log "  Dumping Postgres via pg_dumpall..."
    if docker exec -t "$DB_CONTAINER" \
        pg_dumpall -U "${DB_USERNAME:-postgres}" 2>/dev/null \
        | gzip > "$PG_DUMP_FILE"; then
        FILE_SIZE=$(du -h "$PG_DUMP_FILE" | cut -f1)
        printf "%-35s | %-10s | %s\n" "immich_postgres_dump" "$FILE_SIZE" "pgdump" >> "$REPORT_FILE"
        log "  Postgres dump complete: $FILE_SIZE"
    else
        log "  ERROR: Postgres dump failed"
        printf "%-35s | %-10s | %s\n" "immich_postgres_dump" "FAILED" "pgdump" >> "$REPORT_FILE"
        ERRORS=$((ERRORS + 1))
        # Clean up empty/partial dump file
        rm -f "$PG_DUMP_FILE"
    fi
else
    log "  SKIP: Postgres container '$DB_CONTAINER' is not running"
    printf "%-35s | %-10s | %s\n" "immich_postgres_dump" "SKIP" "pgdump" >> "$REPORT_FILE"
fi

# --- 4. Report summary ------------------------------------------------------
{
    echo "================================================"
    echo "Backup completed: $(date)"
    echo "Errors: $ERRORS"
} >> "$REPORT_FILE"

log "Backup report: $REPORT_FILE"

# --- 5. Rotate old backups --------------------------------------------------
log "--- Phase 5: Backup rotation (keep $MAX_BACKUPS) ---"

# List backup directories sorted by name (oldest first), skip non-date dirs
BACKUP_DIRS=()
while IFS= read -r dir; do
    # Only include directories matching the date pattern (YYYYMMDD-NNN)
    if [[ "$(basename "$dir")" =~ ^[0-9]{8}-[0-9]{3}$ ]]; then
        BACKUP_DIRS+=("$dir")
    fi
done < <(find "$BKUP_BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

TOTAL=${#BACKUP_DIRS[@]}
if [[ $TOTAL -gt $MAX_BACKUPS ]]; then
    TO_DELETE=$((TOTAL - MAX_BACKUPS))
    log "  Found $TOTAL backup sets, removing $TO_DELETE oldest..."
    for ((i = 0; i < TO_DELETE; i++)); do
        log "  Deleting: ${BACKUP_DIRS[$i]}"
        rm -rf "${BACKUP_DIRS[$i]}"
    done
else
    log "  $TOTAL backup sets found (limit: $MAX_BACKUPS). No cleanup needed."
fi

# --- Done --------------------------------------------------------------------
if [[ $ERRORS -gt 0 ]]; then
    log "========== Backup finished with $ERRORS error(s) =========="
    exit 1
else
    log "========== Backup completed successfully =========="
    exit 0
fi
