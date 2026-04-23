#!/bin/bash
set -euo pipefail

# =============================================================================
# backup-all.sh — Backs up Docker volumes, bind-mounted data, and Postgres DB
#
# Designed to run weekly via cron:
#   0 3 * * 0 /mnt/samsung/Docker/MediaServer/scripts/linux/backup-all.sh \
#     >> /mnt/samsung/Docker/MediaServer/vol_bkup/backup.log 2>&1
#
# Retains the most recent MAX_BACKUPS weekly backup sets and deletes older ones.
# =============================================================================

# --- Configuration -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BKUP_BASE_DIR="${PROJECT_DIR}/vol_bkup"
COMPOSE_DIR="$PROJECT_DIR"
# Weekly backups are scheduled on Sundays; keep 3 sets (~3 weeks).
MAX_BACKUPS=3
# Compression level used by gzip/pigz (1=fastest, 9=smallest).
BACKUP_GZIP_LEVEL="${BACKUP_GZIP_LEVEL:-6}"
# Compression program preference: auto, pigz, or gzip.
BACKUP_COMPRESSOR="${BACKUP_COMPRESSOR:-auto}"

# shellcheck source=media-stack-compose.sh
source "${SCRIPT_DIR}/media-stack-compose.sh"

# Load env files for DB credentials, bind-mount paths, and backup settings.
load_env_file() {
    local env_file="$1"

    [[ -f "$env_file" ]] || return 1

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
    done < "$env_file"
}

ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
    load_env_file "$ENV_FILE"
else
    echo "ERROR: .env file not found at $ENV_FILE"
    exit 1
fi

if [[ "${MEDIA_STACK_MODE:-legacy}" == "modular" ]]; then
    while IFS= read -r stack; do
        [[ -n "$stack" ]] || continue
        load_env_file "${PROJECT_DIR}/${stack}/.env" || true
    done < <(active_stack_names)
fi

# --- Helper functions --------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

format_duration() {
    local total_seconds="$1"
    local hours=$((total_seconds / 3600))
    local minutes=$(((total_seconds % 3600) / 60))
    local seconds=$((total_seconds % 60))
    printf "%02dh:%02dm:%02ds" "$hours" "$minutes" "$seconds"
}

calc_throughput_mb_s() {
    local bytes="$1"
    local duration_seconds="$2"

    if [[ "$duration_seconds" -le 0 ]]; then
        echo "n/a"
        return
    fi

    awk -v b="$bytes" -v s="$duration_seconds" 'BEGIN { printf "%.1f MB/s", (b/1048576)/s }'
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

if [[ ! "$BACKUP_GZIP_LEVEL" =~ ^[1-9]$ ]]; then
    log "WARNING: Invalid BACKUP_GZIP_LEVEL='$BACKUP_GZIP_LEVEL'. Falling back to 6."
    BACKUP_GZIP_LEVEL=6
fi

case "${BACKUP_COMPRESSOR,,}" in
    auto)
        if command -v pigz >/dev/null 2>&1; then
            COMPRESS_CMD=(pigz "-${BACKUP_GZIP_LEVEL}")
        else
            COMPRESS_CMD=(gzip "-${BACKUP_GZIP_LEVEL}")
        fi
        ;;
    pigz)
        if command -v pigz >/dev/null 2>&1; then
            COMPRESS_CMD=(pigz "-${BACKUP_GZIP_LEVEL}")
        else
            log "WARNING: BACKUP_COMPRESSOR='pigz' requested but pigz is not installed. Falling back to gzip."
            COMPRESS_CMD=(gzip "-${BACKUP_GZIP_LEVEL}")
        fi
        ;;
    gzip)
        COMPRESS_CMD=(gzip "-${BACKUP_GZIP_LEVEL}")
        ;;
    *)
        log "WARNING: Invalid BACKUP_COMPRESSOR='$BACKUP_COMPRESSOR'. Falling back to auto."
        if command -v pigz >/dev/null 2>&1; then
            COMPRESS_CMD=(pigz "-${BACKUP_GZIP_LEVEL}")
        else
            COMPRESS_CMD=(gzip "-${BACKUP_GZIP_LEVEL}")
        fi
        ;;
esac

TOTAL_START=$SECONDS
log "Compression: ${COMPRESS_CMD[0]} level ${BACKUP_GZIP_LEVEL}"

BKUP_DIR=$(create_backup_dir)
log "Backup directory: $BKUP_DIR"

# Initialize report
REPORT_FILE="${BKUP_DIR}/backup_report.txt"
{
    echo "Backup Report - $(date)"
    echo "================================================"
    echo "Compression: ${COMPRESS_CMD[0]} level ${BACKUP_GZIP_LEVEL}"
    printf "%-35s | %-10s | %-8s | %-12s | %s\n" "Item" "Size" "Type" "Duration" "Throughput"
    printf "%-35s | %-10s | %-8s | %-12s | %s\n" "-----------------------------------" "----------" "--------" "------------" "------------"
} > "$REPORT_FILE"

ERRORS=0

# --- 1. Back up named Docker volumes ----------------------------------------
log "--- Phase 1: Named Docker volumes ---"
PHASE1_START=$SECONDS

cd "$COMPOSE_DIR"
# Always prefer this stack's project name from .env to avoid matching
# unrelated compose projects that may also be running on the same host.
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-media-stack}"
log "Compose mode: ${MEDIA_STACK_MODE:-legacy}"

VOL_KEYS=$(compose_volume_keys)
if [[ -z "$VOL_KEYS" ]]; then
    log "WARNING: No compose volumes found. Skipping volume backup."
else
    for VOL_KEY in $VOL_KEYS; do
        VOL_NAME="$(compose_volume_name "$VOL_KEY")"

        if ! docker volume inspect "$VOL_NAME" > /dev/null 2>&1; then
            log "  SKIP: Volume not found for key '$VOL_KEY' ($VOL_NAME)"
            printf "%-35s | %-10s | %-8s | %-12s | %s\n" "$VOL_KEY" "SKIP" "volume" "--" "--" >> "$REPORT_FILE"
            continue
        fi

        log "  Backing up volume: $VOL_KEY ($VOL_NAME)"
        BKUP_FILE="${BKUP_DIR}/${VOL_KEY}.tar.gz"
        ITEM_START=$SECONDS

        if docker run --rm \
            -v "${VOL_NAME}:/volume:ro" \
            busybox \
            tar cf - -C /volume . 2>/dev/null | "${COMPRESS_CMD[@]}" > "$BKUP_FILE"; then
            FILE_SIZE=$(du -h "$BKUP_FILE" | cut -f1)
            ITEM_SECONDS=$((SECONDS - ITEM_START))
            ITEM_DURATION=$(format_duration "$ITEM_SECONDS")
            FILE_BYTES=$(stat -c%s "$BKUP_FILE" 2>/dev/null || echo 0)
            ITEM_THROUGHPUT=$(calc_throughput_mb_s "$FILE_BYTES" "$ITEM_SECONDS")
            printf "%-35s | %-10s | %-8s | %-12s | %s\n" "$VOL_KEY" "$FILE_SIZE" "volume" "$ITEM_DURATION" "$ITEM_THROUGHPUT" >> "$REPORT_FILE"
        else
            log "  ERROR: Failed to back up volume $VOL_KEY"
            ITEM_SECONDS=$((SECONDS - ITEM_START))
            ITEM_DURATION=$(format_duration "$ITEM_SECONDS")
            printf "%-35s | %-10s | %-8s | %-12s | %s\n" "$VOL_KEY" "FAILED" "volume" "$ITEM_DURATION" "--" >> "$REPORT_FILE"
            ERRORS=$((ERRORS + 1))
        fi
    done
fi
PHASE1_DURATION=$((SECONDS - PHASE1_START))
log "Phase 1 duration: $(format_duration "$PHASE1_DURATION")"

# --- 2. Back up bind-mounted data directories --------------------------------
log "--- Phase 2: Bind-mounted data ---"
PHASE2_START=$SECONDS

declare -A BIND_MOUNTS=(
    ["derbynet"]="${PROJECT_DIR}/proxied-apps/data/derbynet"
    ["budget"]="${PROJECT_DIR}/lan-apps/data/budget"
    ["minecraft-survival"]="${PROJECT_DIR}/proxied-apps/data/survival"
    ["minecraft-creative"]="${PROJECT_DIR}/proxied-apps/data/creative"
)

for MOUNT_NAME in "${!BIND_MOUNTS[@]}"; do
    MOUNT_PATH="${BIND_MOUNTS[$MOUNT_NAME]}"

    if [[ ! -d "$MOUNT_PATH" ]]; then
        log "  SKIP: Bind mount path not found: $MOUNT_PATH"
        printf "%-35s | %-10s | %-8s | %-12s | %s\n" "$MOUNT_NAME" "SKIP" "bind" "--" "--" >> "$REPORT_FILE"
        continue
    fi

    log "  Backing up bind mount: $MOUNT_NAME ($MOUNT_PATH)"
    BKUP_FILE="${BKUP_DIR}/bind_${MOUNT_NAME}.tar.gz"
    ITEM_START=$SECONDS

    if tar cf - -C "$MOUNT_PATH" . 2>/dev/null | "${COMPRESS_CMD[@]}" > "$BKUP_FILE"; then
        FILE_SIZE=$(du -h "$BKUP_FILE" | cut -f1)
        ITEM_SECONDS=$((SECONDS - ITEM_START))
        ITEM_DURATION=$(format_duration "$ITEM_SECONDS")
        FILE_BYTES=$(stat -c%s "$BKUP_FILE" 2>/dev/null || echo 0)
        ITEM_THROUGHPUT=$(calc_throughput_mb_s "$FILE_BYTES" "$ITEM_SECONDS")
        printf "%-35s | %-10s | %-8s | %-12s | %s\n" "$MOUNT_NAME" "$FILE_SIZE" "bind" "$ITEM_DURATION" "$ITEM_THROUGHPUT" >> "$REPORT_FILE"
    else
        log "  ERROR: Failed to back up bind mount $MOUNT_NAME"
        ITEM_SECONDS=$((SECONDS - ITEM_START))
        ITEM_DURATION=$(format_duration "$ITEM_SECONDS")
        printf "%-35s | %-10s | %-8s | %-12s | %s\n" "$MOUNT_NAME" "FAILED" "bind" "$ITEM_DURATION" "--" >> "$REPORT_FILE"
        ERRORS=$((ERRORS + 1))
    fi
done
PHASE2_DURATION=$((SECONDS - PHASE2_START))
log "Phase 2 duration: $(format_duration "$PHASE2_DURATION")"

# --- 3. Postgres logical dump (Immich database) -----------------------------
log "--- Phase 3: Postgres database dump ---"
PHASE3_START=$SECONDS

DB_CONTAINER="immich_postgres"
PG_DUMP_FILE="${BKUP_DIR}/immich_postgres_dump.sql.gz"

if docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    log "  Dumping Postgres via pg_dumpall..."
    ITEM_START=$SECONDS
    if docker exec -t "$DB_CONTAINER" \
        pg_dumpall -U "${DB_USERNAME:-postgres}" 2>/dev/null \
        | "${COMPRESS_CMD[@]}" > "$PG_DUMP_FILE"; then
        FILE_SIZE=$(du -h "$PG_DUMP_FILE" | cut -f1)
        ITEM_SECONDS=$((SECONDS - ITEM_START))
        ITEM_DURATION=$(format_duration "$ITEM_SECONDS")
        FILE_BYTES=$(stat -c%s "$PG_DUMP_FILE" 2>/dev/null || echo 0)
        ITEM_THROUGHPUT=$(calc_throughput_mb_s "$FILE_BYTES" "$ITEM_SECONDS")
        printf "%-35s | %-10s | %-8s | %-12s | %s\n" "immich_postgres_dump" "$FILE_SIZE" "pgdump" "$ITEM_DURATION" "$ITEM_THROUGHPUT" >> "$REPORT_FILE"
        log "  Postgres dump complete: $FILE_SIZE"
    else
        log "  ERROR: Postgres dump failed"
        ITEM_SECONDS=$((SECONDS - ITEM_START))
        ITEM_DURATION=$(format_duration "$ITEM_SECONDS")
        printf "%-35s | %-10s | %-8s | %-12s | %s\n" "immich_postgres_dump" "FAILED" "pgdump" "$ITEM_DURATION" "--" >> "$REPORT_FILE"
        ERRORS=$((ERRORS + 1))
        # Clean up empty/partial dump file
        rm -f "$PG_DUMP_FILE"
    fi
else
    log "  SKIP: Postgres container '$DB_CONTAINER' is not running"
    printf "%-35s | %-10s | %-8s | %-12s | %s\n" "immich_postgres_dump" "SKIP" "pgdump" "--" "--" >> "$REPORT_FILE"
fi
PHASE3_DURATION=$((SECONDS - PHASE3_START))
log "Phase 3 duration: $(format_duration "$PHASE3_DURATION")"

# --- 4. Report summary ------------------------------------------------------
TOTAL_DURATION=$((SECONDS - TOTAL_START))
{
    echo "================================================"
    echo "Backup completed: $(date)"
    echo "Errors: $ERRORS"
    echo ""
    echo "Duration Summary"
    echo "- Phase 1 (volumes): $(format_duration "$PHASE1_DURATION")"
    echo "- Phase 2 (bind mounts): $(format_duration "$PHASE2_DURATION")"
    echo "- Phase 3 (Postgres dump): $(format_duration "$PHASE3_DURATION")"
    echo "- Total: $(format_duration "$TOTAL_DURATION")"
} >> "$REPORT_FILE"

log "Backup report: $REPORT_FILE"
log "Total duration: $(format_duration "$TOTAL_DURATION")"

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
