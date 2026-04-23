#!/bin/bash
#
# Immich Restore Script for Linux
# Restores Immich database and upload files from backup
# 
# Based on Immich official documentation:
# https://docs.immich.app/administration/backup-and-restore
#
# REQUIREMENTS:
# - Database dump file (.sql or .sql.gz)
# - Upload files backup (if available)
# - Docker and docker compose installed
# - Immich containers defined in immich/compose.yml
#
# USAGE:
#   ./restore-immich-linux.sh [database_dump_file]
#   
# EXAMPLES:
#   # Restore database from SQL dump
#   ./restore-immich-linux.sh immich-db-backup-20260124T020000-v2.4.1-pg14.19.sql
#   
#   # Restore database from compressed SQL dump
#   ./restore-immich-linux.sh dump.sql.gz
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$COMPOSE_DIR/.env"

# Load environment variables from .env
if [ -f "$ENV_FILE" ]; then
    source <(grep -v '^#' "$ENV_FILE" | sed -E 's/^(.*)=(.*)$/export \1="\2"/')
    echo -e "${GREEN}[OK] Loaded configuration from .env${NC}"
else
    echo -e "${RED}[ERROR] .env file not found at $ENV_FILE${NC}"
    exit 1
fi

# Set defaults from .env or use fallbacks
DB_CONTAINER="${DB_CONTAINER:-immich_postgres}"
DB_USERNAME="${DB_USERNAME:-postgres}"
DB_DATABASE_NAME="${DB_DATABASE_NAME:-immich}"
UPLOAD_LOCATION="${UPLOAD_LOCATION:-/mnt/immich/upload}"
DB_DATA_LOCATION="${DB_DATA_LOCATION:-/var/lib/postgresql/data}"

echo -e "${CYAN}========================================"
echo "Immich Restore Script for Linux"
echo -e "========================================${NC}"
echo ""

# Check if database dump file is provided
if [ -z "$1" ]; then
    echo -e "${RED}[ERROR] Database dump file not provided${NC}"
    echo "Usage: $0 <database_dump_file>"
    echo ""
    echo "Examples:"
    echo "  $0 immich-db-backup.sql"
    echo "  $0 immich-db-backup.sql.gz"
    exit 1
fi

DB_DUMP_FILE="$1"

# Verify database dump file exists
if [ ! -f "$DB_DUMP_FILE" ]; then
    echo -e "${RED}[ERROR] Database dump file does not exist: $DB_DUMP_FILE${NC}"
    exit 1
fi

# Get absolute path of dump file
DB_DUMP_FILE="$(realpath "$DB_DUMP_FILE")"

echo -e "${YELLOW}Configuration:${NC}"
echo -e "  Compose Directory: $COMPOSE_DIR"
echo -e "  Database Container: $DB_CONTAINER"
echo -e "  Database Username: $DB_USERNAME"
echo -e "  Database Name: $DB_DATABASE_NAME"
echo -e "  Upload Location: $UPLOAD_LOCATION"
echo -e "  DB Data Location: $DB_DATA_LOCATION"
echo ""
echo -e "${GREEN}[OK] Found database dump: $DB_DUMP_FILE${NC}"
echo -e "${YELLOW}[INFO] Upload files will NOT be modified - only database will be restored${NC}"
echo -e "${YELLOW}[INFO] Ensure your upload files are already in: $UPLOAD_LOCATION${NC}"
echo ""

# Confirm restore operation
echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                        WARNING!                                ║${NC}"
echo -e "${RED}║  This will COMPLETELY RESET your Immich installation!         ║${NC}"
echo -e "${RED}║  All existing data will be PERMANENTLY DELETED!                ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}What will be deleted:${NC}"
echo -e "  • Database data in: $DB_DATA_LOCATION"
echo -e "${GREEN}What will NOT be touched:${NC}"
echo -e "  • Upload files in: $UPLOAD_LOCATION (preserved)"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}[CANCELLED] Restore operation cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo -e "${CYAN}  Starting Restore Process...${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo ""

# Step 1: Stop and remove any existing Immich containers
echo -e "${CYAN}[1/7] Stopping and removing existing Immich containers...${NC}"
cd "$COMPOSE_DIR"

# Check if any Immich containers exist (running or stopped)
if docker ps -a --format '{{.Names}}' | grep -q immich; then
    echo -e "${YELLOW}[INFO] Found existing Immich containers${NC}"
    docker compose down -v
    echo -e "${GREEN}[OK] Existing containers stopped and removed${NC}"
else
    echo -e "${YELLOW}[INFO] No existing Immich containers found (fresh installation)${NC}"
fi
echo ""

# Step 2: Remove database data to ensure clean restore
echo -e "${CYAN}[2/7] Preparing database directory...${NC}"
if [ -d "$DB_DATA_LOCATION" ]; then
    # Check if directory has any PostgreSQL data
    if [ -n "$(ls -A "$DB_DATA_LOCATION" 2>/dev/null)" ]; then
        echo -e "${YELLOW}[WARNING] Existing database data found in: $DB_DATA_LOCATION${NC}"
        echo -e "${YELLOW}[INFO] This must be removed for a clean restore${NC}"
        read -p "Confirm deletion of database data? (type 'yes'): " db_confirm
        if [ "$db_confirm" = "yes" ]; then
            rm -rf "$DB_DATA_LOCATION"/*
            echo -e "${GREEN}[OK] Database data removed${NC}"
        else
            echo -e "${RED}[ERROR] Database deletion cancelled - cannot proceed${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}[INFO] Database directory exists but is empty (ready for restore)${NC}"
    fi
else
    echo -e "${YELLOW}[INFO] Database directory does not exist - will be created automatically${NC}"
    mkdir -p "$DB_DATA_LOCATION"
    # sudo chown -R 1000:1000 "$DB_DATA_LOCATION"
fi
echo ""

# Step 3: Verify upload files exist
echo -e "${CYAN}[3/7] Verifying upload files...${NC}"
if [ -d "$UPLOAD_LOCATION" ]; then
    echo -e "${GREEN}[OK] Upload directory exists: $UPLOAD_LOCATION${NC}"
    
    # Check if directory has content
    if [ -n "$(ls -A "$UPLOAD_LOCATION" 2>/dev/null)" ]; then
        echo -e "${GREEN}[OK] Upload directory contains files${NC}"
    else
        echo -e "${YELLOW}[WARNING] Upload directory is empty - you may need to restore files manually${NC}"
    fi
else
    echo -e "${YELLOW}[WARNING] Upload directory does not exist: $UPLOAD_LOCATION${NC}"
    echo -e "${YELLOW}[INFO] Creating directory - you will need to restore files manually${NC}"
    mkdir -p "$UPLOAD_LOCATION"
    # sudo chown -R 1000:1000 "$UPLOAD_LOCATION"
fi
echo ""

# Step 4: Pull latest Immich images (skip to use existing)
echo -e "${CYAN}[4/7] Checking Immich images...${NC}"
echo -e "${YELLOW}[INFO] Skipping image pull to use existing images${NC}"
echo -e "${YELLOW}[INFO] You can manually run 'docker compose pull' later if needed${NC}"
echo ""

# Step 5: Create required containers (exclude ML when NVIDIA runtime is unavailable)
echo -e "${CYAN}[5/7] Creating required Immich containers...${NC}"
echo -e "${YELLOW}[INFO] Creating only database, redis, and server containers...${NC}"
echo -e "${YELLOW}[INFO] Skipping machine-learning container to avoid NVIDIA runtime requirement${NC}"
docker compose create database redis immich-server
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] Required containers created successfully${NC}"
else
    echo -e "${RED}[ERROR] Failed to create required containers${NC}"
    exit 1
fi
echo ""

# Step 6: Start only the database and wait for it to be ready
echo -e "${CYAN}[6/7] Starting PostgreSQL database...${NC}"
echo -e "${YELLOW}[INFO] Starting database container (this initializes a fresh PostgreSQL instance)${NC}"

if docker start "$DB_CONTAINER"; then
    echo -e "${GREEN}[OK] Database container started${NC}"
else
    echo -e "${RED}[ERROR] Failed to start database container${NC}"
    exit 1
fi

echo -e "${YELLOW}[INFO] Waiting for PostgreSQL to initialize and be ready (this may take 30-60 seconds)...${NC}"

# Wait for database to be ready with better feedback
for i in {1..60}; do
    if docker exec "$DB_CONTAINER" pg_isready -U "$DB_USERNAME" &> /dev/null; then
        echo ""
        echo -e "${GREEN}[OK] PostgreSQL is ready and accepting connections${NC}"
        sleep 2  # Give it a couple extra seconds to be fully ready
        break
    fi
    if [ $i -eq 60 ]; then
        echo ""
        echo -e "${RED}[ERROR] PostgreSQL failed to start within 60 seconds${NC}"
        echo -e "${YELLOW}[INFO] Check database logs: docker logs $DB_CONTAINER${NC}"
        exit 1
    fi
    sleep 1
    if [ $((i % 5)) -eq 0 ]; then
        echo -n " $i"
    else
        echo -n "."
    fi
done
echo ""
echo ""

# Step 7: Restore the database
echo -e "${CYAN}[7/7] Restoring database from dump...${NC}"

# Check if dump is compressed
if [[ "$DB_DUMP_FILE" == *.gz ]]; then
    echo -e "${YELLOW}[INFO] Decompressing and restoring from gzipped dump...${NC}"
    gunzip --stdout "$DB_DUMP_FILE" \
        | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
        | docker exec -i "$DB_CONTAINER" psql --dbname=postgres --username="$DB_USERNAME"
else
    echo -e "${YELLOW}[INFO] Restoring from SQL dump...${NC}"
    cat "$DB_DUMP_FILE" \
        | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
        | docker exec -i "$DB_CONTAINER" psql --dbname=postgres --username="$DB_USERNAME"
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] Database restored successfully${NC}"
else
    echo -e "${RED}[ERROR] Database restore failed${NC}"
    exit 1
fi
echo ""

# Step 8: Start Immich core services (server, redis, database)
echo -e "${CYAN}[8/8] Starting Immich core services...${NC}"
cd "$COMPOSE_DIR"
echo -e "${YELLOW}[INFO] Starting server, redis, and database containers (excluding ML)${NC}"

if docker compose up -d database redis immich-server; then
    echo -e "${GREEN}[OK] Core services started${NC}"
    sleep 3
    echo ""
    echo -e "${CYAN}Container Status:${NC}"
    docker compose ps
else
    echo -e "${RED}[ERROR] Failed to start core services${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Restore Completed Successfully!                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo -e "  1. Wait a few minutes for all services to start"
echo -e "  2. Access Immich at: http://localhost:2283"
echo -e "  3. Check logs: docker compose logs -f immich-server"
echo -e "  4. Verify your photos and videos appear correctly"
echo ""
echo -e "${CYAN}[NOTE] Database restored - Upload files preserved at: $UPLOAD_LOCATION${NC}"
echo ""
echo -e "${CYAN}Monitoring:${NC}"
echo -e "  • View all logs: docker compose logs -f"
echo -e "  • View server logs: docker compose logs -f immich-server"
echo -e "  • View database logs: docker compose logs -f database"
echo -e "  • Check status: docker compose ps"
echo ""
