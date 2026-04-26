#!/bin/bash
#
# Immich Restore Script for Linux
# Restores Immich database and upload files from Windows backup
# 
# Based on Immich official documentation:
# https://docs.immich.app/administration/backup-and-restore
#
# REQUIREMENTS:
# - Fresh Immich installation (containers created but not started, or DB_SKIP_MIGRATIONS=true)
# - Backup files from backup-immich.ps1
# - Docker and docker compose installed
#
# USAGE:
#   ./restore-immich.sh /path/to/backup/immich_backup_YYYY-MM-DD_HHMMSS
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration (modify these to match your setup)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
IMMICH_COMPOSE_DIR="${IMMICH_COMPOSE_DIR:-${PROJECT_ROOT}/immich}"
DB_CONTAINER="immich_postgres"
DB_USERNAME="${DB_USERNAME:-postgres}"
UPLOAD_LOCATION="${UPLOAD_LOCATION:-/mnt/immich/upload}"

echo -e "${CYAN}========================================"
echo "Immich Restore Script for Linux"
echo -e "========================================${NC}"
echo ""

# Check if backup path is provided
if [ -z "$1" ]; then
    echo -e "${RED}[ERROR] Backup path not provided${NC}"
    echo "Usage: $0 /path/to/backup/immich_backup_YYYY-MM-DD_HHMMSS"
    exit 1
fi

BACKUP_PATH="$1"

# Verify backup path exists
if [ ! -d "$BACKUP_PATH" ]; then
    echo -e "${RED}[ERROR] Backup path does not exist: $BACKUP_PATH${NC}"
    exit 1
fi

# Verify backup contents
if [ ! -d "$BACKUP_PATH/database" ] || [ ! -d "$BACKUP_PATH/uploads" ]; then
    echo -e "${RED}[ERROR] Invalid backup structure. Expected 'database' and 'uploads' folders${NC}"
    exit 1
fi

echo -e "${YELLOW}Backup Path: $BACKUP_PATH${NC}"
echo -e "${YELLOW}Immich Location: $IMMICH_COMPOSE_DIR${NC}"
echo -e "${YELLOW}Upload Location: $UPLOAD_LOCATION${NC}"
echo ""

# Find database backup file
DB_BACKUP_FILE=$(find "$BACKUP_PATH/database" -name "*.sql.gz" -type f | head -n 1)

if [ -z "$DB_BACKUP_FILE" ]; then
    echo -e "${RED}[ERROR] No database backup file found in $BACKUP_PATH/database${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] Found database backup: $(basename "$DB_BACKUP_FILE")${NC}"
echo ""

# Confirm restore operation
echo -e "${RED}WARNING: This will COMPLETELY RESET your Immich installation!${NC}"
echo -e "${RED}All existing data will be lost!${NC}"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}[CANCELLED] Restore operation cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${CYAN}Starting restore process...${NC}"
echo ""

# Step 1: Stop Immich services
echo -e "${CYAN}Step 1: Stopping Immich services...${NC}"
cd "$IMMICH_COMPOSE_DIR"

if docker compose ps | grep -q immich; then
    docker compose down -v  # Stop and remove volumes
    echo -e "${GREEN}[OK] Immich services stopped${NC}"
else
    echo -e "${YELLOW}[INFO] Immich services not running${NC}"
fi

# Step 2: Clear existing data (optional, uncomment if needed)
# WARNING: This will delete all existing Immich data!
# echo -e "${YELLOW}Step 2: Clearing existing data...${NC}"
# if [ -d "$UPLOAD_LOCATION" ]; then
#     echo -e "${YELLOW}Removing existing upload files...${NC}"
#     rm -rf "$UPLOAD_LOCATION"/*
#     echo -e "${GREEN}[OK] Upload files cleared${NC}"
# fi

# Step 3: Create fresh containers
echo ""
echo -e "${CYAN}Step 2: Creating fresh Immich containers...${NC}"
docker compose pull
docker compose create
echo -e "${GREEN}[OK] Containers created${NC}"

# Step 4: Start Postgres only
echo ""
echo -e "${CYAN}Step 3: Starting PostgreSQL database...${NC}"
docker start $DB_CONTAINER
echo -e "${YELLOW}Waiting for PostgreSQL to be ready...${NC}"
sleep 10

# Verify Postgres is running
if ! docker ps | grep -q $DB_CONTAINER; then
    echo -e "${RED}[ERROR] Failed to start PostgreSQL container${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] PostgreSQL is running${NC}"

# Step 5: Restore database
echo ""
echo -e "${CYAN}Step 4: Restoring database...${NC}"
echo -e "${YELLOW}This may take several minutes...${NC}"

# Use sed to fix search_path issue (per Immich documentation)
gunzip --stdout "$DB_BACKUP_FILE" | \
    sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" | \
    docker exec -i $DB_CONTAINER psql --dbname=postgres --username=$DB_USERNAME

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] Database restored successfully${NC}"
else
    echo -e "${RED}[ERROR] Database restore failed${NC}"
    exit 1
fi

# Step 6: Restore upload files
echo ""
echo -e "${CYAN}Step 5: Restoring upload files...${NC}"

# Create upload location if it doesn't exist
mkdir -p "$UPLOAD_LOCATION"

# Restore critical folders
for folder in library upload profile backups; do
    SOURCE_PATH="$BACKUP_PATH/uploads/$folder"
    
    if [ -d "$SOURCE_PATH" ]; then
        echo -e "${YELLOW}  - Restoring $folder...${NC}"
        
        # Create destination folder
        mkdir -p "$UPLOAD_LOCATION/$folder"
        
        # Copy files (with progress)
        rsync -ah --info=progress2 "$SOURCE_PATH/" "$UPLOAD_LOCATION/$folder/"
        
        if [ $? -eq 0 ]; then
            FOLDER_SIZE=$(du -sh "$UPLOAD_LOCATION/$folder" | cut -f1)
            echo -e "${GREEN}    [OK] $folder restored ($FOLDER_SIZE)${NC}"
        else
            echo -e "${RED}    [ERROR] Failed to restore $folder${NC}"
        fi
    else
        echo -e "${YELLOW}    [SKIP] $folder not found in backup${NC}"
    fi
done

# Set proper permissions for Immich
echo ""
echo -e "${CYAN}Step 6: Setting permissions...${NC}"
# Adjust UID:GID as needed for your Immich setup (usually 1000:1000)
chown -R 1000:1000 "$UPLOAD_LOCATION"
chmod -R 755 "$UPLOAD_LOCATION"
echo -e "${GREEN}[OK] Permissions set${NC}"

# Step 7: Start all Immich services
echo ""
echo -e "${CYAN}Step 7: Starting Immich services...${NC}"
cd "$IMMICH_COMPOSE_DIR"
docker compose up -d

echo -e "${YELLOW}Waiting for services to start...${NC}"
sleep 15

# Verify services are running
if docker compose ps | grep -q "immich"; then
    echo -e "${GREEN}[OK] Immich services started${NC}"
else
    echo -e "${RED}[WARNING] Some services may not have started properly${NC}"
fi

# Step 8: Post-restore instructions
echo ""
echo -e "${CYAN}========================================"
echo "Restore Complete!"
echo -e "========================================${NC}"
echo ""
echo -e "${GREEN}[OK] Database restored${NC}"
echo -e "${GREEN}[OK] Upload files restored${NC}"
echo -e "${GREEN}[OK] Services started${NC}"
echo ""
echo -e "${YELLOW}Post-Restore Steps:${NC}"
echo "1. Wait a few minutes for Immich to fully start"
echo "2. Access Immich web interface"
echo "3. Verify your photos and albums are visible"
echo "4. Run Jobs -> Generate Thumbnails (if thumbs were not restored)"
echo "5. Run Jobs -> Transcode Videos (if encoded-video was not restored)"
echo ""
echo -e "${YELLOW}Check logs if needed:${NC}"
echo "  docker compose logs -f immich-server"
echo ""
echo -e "${YELLOW}Backup info can be found at:${NC}"
echo "  $BACKUP_PATH/BACKUP_INFO.txt"
echo ""
echo -e "${GREEN}Enjoy your restored Immich installation!${NC}"
echo ""
