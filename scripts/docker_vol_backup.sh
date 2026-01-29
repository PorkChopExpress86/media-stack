#!/bin/bash

# Configuration
COMPOSE_FILE="../docker-compose.yaml"
BKUP_BASE_DIR="../vol_bkup"

# 1. Detect project name
PROJECT_NAME=$(docker compose ls --format json | grep -oP '"Name":"\K[^"]+' | head -1)
if [ -z "$PROJECT_NAME" ]; then
    echo "Error: Could not detect project name. Are you in the project directory?"
    exit 1
fi

# 2. Create base backup directory
mkdir -p "$BKUP_BASE_DIR"

# 3. Generate timestamped directory name with incrementing suffix
DATE=$(date +%Y%m%d)
SUFFIX=1
while true; do
    # Format suffix as 00x (3 digits)
    FORMATTED_SUFFIX=$(printf "%03d" $SUFFIX)
    BKUP_DIR="${BKUP_BASE_DIR}/${DATE}-${FORMATTED_SUFFIX}"
    if [ ! -d "$BKUP_DIR" ]; then
        break
    fi
    SUFFIX=$((SUFFIX + 1))
done

mkdir -p "$BKUP_DIR"
echo "Starting backup to $BKUP_DIR for project $PROJECT_NAME..."

# 4. Get volumes listed in the compose file
# This returns the keys from the 'volumes:' section
VOL_KEYS=$(docker compose config --volumes)

if [ -z "$VOL_KEYS" ]; then
    echo "No volumes found in $COMPOSE_FILE to back up."
    exit 0
fi

# 5. Initialize report
REPORT_FILE="${BKUP_DIR}/backup_report.txt"
echo "Backup Report - $(date)" > "$REPORT_FILE"
echo "Project: $PROJECT_NAME" >> "$REPORT_FILE"
echo "------------------------------------------------" >> "$REPORT_FILE"
printf "%-30s | %s\n" "Volume Key" "Size" >> "$REPORT_FILE"
printf "%-30s | %s\n" "------------------------------" "----------" >> "$REPORT_FILE"

for VOL_KEY in $VOL_KEYS; do
    # Find the actual volume name using project label and volume label
    VOL_NAME=$(docker volume ls -q --filter "label=com.docker.compose.project=${PROJECT_NAME}" --filter "label=com.docker.compose.volume=${VOL_KEY}")
    
    if [ -z "$VOL_NAME" ]; then
        # Fallback: try prepending project name if label search fails
        VOL_NAME="${PROJECT_NAME}_${VOL_KEY}"
        if ! docker volume inspect "$VOL_NAME" > /dev/null 2>&1; then
            echo "Warning: Could not find volume for key $VOL_KEY"
            continue
        fi
    fi

    echo "Backing up volume: $VOL_NAME ($VOL_KEY)"
    
    # Back up using a temporary container
    BKUP_FILE="${BKUP_DIR}/${VOL_KEY}.tar.gz"
    docker run --rm \
        -v "${VOL_NAME}:/volume" \
        -v "$(pwd)/${BKUP_DIR}:/backup" \
        busybox \
        tar czf "/backup/${VOL_KEY}.tar.gz" -C /volume .

    # Add to report
    if [ -f "$BKUP_FILE" ]; then
        FILE_SIZE=$(du -h "$BKUP_FILE" | cut -f1)
        printf "%-30s | %s\n" "$VOL_KEY" "$FILE_SIZE" >> "$REPORT_FILE"
    else
        printf "%-30s | %s\n" "$VOL_KEY" "FAILED" >> "$REPORT_FILE"
    fi
done

echo "------------------------------------------------"
echo "Backup complete. Files saved to $BKUP_DIR"
echo "Report generated: $REPORT_FILE"

