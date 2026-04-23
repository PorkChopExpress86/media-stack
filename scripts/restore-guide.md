# Immich Restore Guide - Linux

This guide will help you restore your Immich database and files from your Windows backup to your Linux system.

## Prerequisites

✅ You have:
- Database dump file: `immich-db-backup-20260124T020000-v2.4.1-pg14.19.sql`
- Upload files already in place at `/media/specter/immich/Immich/upload`
- Ownership of all files (already taken care of)
- `.env` file configured with correct paths

## Quick Start

### Option 1: Restore Database Only (Recommended if files are already in place)

Since you mentioned you've already migrated the files and taken ownership, you likely only need to restore the database:

```bash
cd /home/specter/Docker/MediaServer/scripts/linux
./restore-immich-linux.sh /home/specter/Docker/MediaServer/immich-db-backup-20260124T020000-v2.4.1-pg14.19.sql
```

### Option 2: Restore Database and Upload Files

If you need to restore both database and upload files:

```bash
cd /home/specter/Docker/MediaServer/scripts/linux
./restore-immich-linux.sh /home/specter/Docker/MediaServer/immich-db-backup-20260124T020000-v2.4.1-pg14.19.sql /path/to/upload/backup
```

## What the Script Does

The restore script performs these steps automatically:

1. **Stops Immich services** - Gracefully stops all running containers
2. **Removes database data** - Clears existing PostgreSQL data for clean restore
3. **Restores upload files** (optional) - Copies backed up photos/videos
4. **Pulls latest images** - Updates to latest Immich version
5. **Creates containers** - Sets up fresh container instances
6. **Starts database** - Launches PostgreSQL and waits for it to be ready
7. **Restores database dump** - Imports your backup data
8. **Starts all services** - Launches full Immich stack

## Important Notes

### Database Restore Requirements

According to Immich documentation, database restore requires either:
- **Fresh installation** (containers created but server never started), OR
- **Clean database** (DB_DATA_LOCATION folder deleted)

The script handles this automatically by removing the database folder.

### File Ownership

Your upload files need proper ownership for Immich to access them:

```bash
# Run this if you encounter permission issues
sudo chown -R 1000:1000 /media/specter/immich/Immich/upload
```

### Your Current Configuration

From your `.env` file:
- Upload Location: check `UPLOAD_LOCATION` in your `.env`
- Database Location: check `DB_DATA_LOCATION` in your `.env`
- Database Password: check `DB_PASSWORD` in your `.env`
- Immich Version: check `IMMICH_VERSION` in your `.env`

> **Note:** Never commit credentials to version control. All sensitive values should only exist in your `.env` file.

## Step-by-Step Process

### 1. Verify Your Backup Files

```bash
# Check database dump exists
ls -lh /home/specter/Docker/MediaServer/immich-db-backup-20260124T020000-v2.4.1-pg14.19.sql

# Check upload files are in place (if already migrated)
ls -la /media/specter/immich/Immich/upload/
```

### 2. Run the Restore Script

```bash
cd /home/specter/Docker/MediaServer/scripts/linux
./restore-immich-linux.sh ../../immich-db-backup-20260124T020000-v2.4.1-pg14.19.sql
```

The script will:
- Ask for confirmation before proceeding
- Show you what will be deleted
- Require you to type 'yes' multiple times to confirm

### 3. Monitor the Restore

During the restore, you'll see progress indicators for:
- Service shutdown
- Database cleanup
- File copying (if applicable)
- Image downloads
- Database restoration

### 4. Verify the Restore

After completion:

```bash
# Check all containers are running
docker compose ps

# View logs to ensure no errors
docker compose logs -f immich-server

# Access Immich web interface
# Open browser to: http://192.168.1.200:2283
```

## Troubleshooting

### Issue: Permission Denied

**Solution**: Run with sudo or fix file ownership:
```bash
sudo chown -R 1000:1000 /media/specter/immich/Immich/upload
sudo chown -R 1000:1000 /media/specter/immich/Immich/postgres
```

### Issue: Database Connection Errors

**Solution**: Wait longer for PostgreSQL to start:
```bash
# Check database logs
docker logs immich_postgres

# Manually verify database is ready
docker exec immich_postgres pg_isready -U postgres
```

### Issue: Search Path Errors

**Solution**: The script automatically fixes this with sed command. If you still see errors about `search_path`, the sed command in the script handles the common PostgreSQL search path issue.

### Issue: Restore Fails with "relation already exists"

**Solution**: The database wasn't clean. Manually remove:
```bash
sudo rm -rf /media/specter/immich/Immich/postgres
```
Then run the restore script again.

### Issue: Missing Photos After Restore

**Possible causes**:
1. Upload files not in correct location
2. Incorrect ownership
3. Database references different paths

**Solution**:
```bash
# Verify files exist
ls -la /media/specter/immich/Immich/upload/

# Check ownership
ls -ld /media/specter/immich/Immich/upload/

# Fix ownership if needed
sudo chown -R 1000:1000 /media/specter/immich/Immich/upload
```

## Post-Restore Tasks

### 1. Verify All Services Running

```bash
docker compose ps
```

Expected output should show all containers as "Up" and healthy.

### 2. Check Logs for Errors

```bash
# All services
docker compose logs

# Just the server
docker compose logs immich-server

# Follow logs in real-time
docker compose logs -f
```

### 3. Access Immich Web Interface

- URL: `http://192.168.1.200:2283` (based on your local_ip in .env)
- Or: `http://localhost:2283` if accessing locally

### 4. Verify Your Data

- Log in with your existing credentials
- Check that photos/videos appear
- Verify albums and metadata
- Test face recognition (may need to re-run)

### 5. Optional: Regenerate Thumbnails

If thumbnails don't appear or you didn't restore the upload files, regenerate them:

1. Go to Administration → Jobs
2. Run "Thumbnail Generation" for all assets
3. Wait for completion

## Backup Strategy Going Forward

Now that you're on Linux, consider setting up automated backups:

### Option 1: Use Existing Backup Scripts

```bash
# Database backup
cd /home/specter/Docker/MediaServer/scripts/linux
./backup-volumes.sh
```

### Option 2: Set Up Cron Job

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * /home/specter/Docker/MediaServer/scripts/linux/backup-volumes.sh
```

### Option 3: Use Immich's Built-in Backup

Immich automatically creates database dumps daily at 2 AM, stored in:
`/media/specter/immich/Immich/upload/backups/`

Configure in: Administration → Settings → Backup Settings

## Additional Resources

- **Immich Documentation**: https://docs.immich.app/administration/backup-and-restore
- **Your Backup Guide**: [immich-backup-guide.md](./immich-backup-guide.md)
- **Docker Compose File**: [../immich/compose.yml](../immich/compose.yml)
- **Environment Config**: [../.env](../.env)

## Quick Reference Commands

```bash
# Navigate to the Immich stack directory
cd /home/specter/Docker/MediaServer/immich

# Run restore (database only)
./scripts/linux/restore-immich-linux.sh immich-db-backup-20260124T020000-v2.4.1-pg14.19.sql

# Check container status
docker compose ps

# View logs
docker compose logs -f immich-server

# Restart Immich
docker compose restart

# Stop Immich
docker compose down

# Start Immich
docker compose up -d

# Fix file ownership
sudo chown -R 1000:1000 /media/specter/immich/Immich/upload
```

## Support

If you encounter issues not covered here:
1. Check the logs: `docker compose logs`
2. Review Immich docs: https://docs.immich.app
3. Check GitHub issues: https://github.com/immich-app/immich/issues
4. Discord community: https://discord.immich.app

---

**Remember**: Always verify your backup before deleting the source!
