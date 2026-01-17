# Backup Restoration - Quick Reference

## Prerequisites Checklist

- [ ] Docker services running: `docker compose -f compose.custom.yaml ps`
- [ ] Database backup file (`.sql`)
- [ ] Public files archive (`.tar`)
- [ ] Private files archive (`.tar`)
- [ ] Site config with encryption_key (`.json`) - IMPORTANT!

## Common Commands

### 1. Standard Restore (Existing Site)

```bash
./restore-backup.sh \
  -d /path/to/database.sql \
  -p /path/to/public_files.tar \
  -r /path/to/private_files.tar \
  -s localhost \
  -c /path/to/site_config.json
```

### 2. Create New Site + Restore

```bash
./restore-backup.sh \
  -d /path/to/database.sql \
  -p /path/to/public_files.tar \
  -r /path/to/private_files.tar \
  -s localhost \
  -c /path/to/site_config.json \
  -n
```

### 3. Restore with Custom Strip Components

```bash
# First check tar structure
tar -tvf /path/to/public_files.tar | head -n 10

# Then restore with adjusted strip value
./restore-backup.sh \
  -d /path/to/database.sql \
  -p /path/to/public_files.tar \
  -r /path/to/private_files.tar \
  -s localhost \
  --strip-components=4
```

## Before You Start

### 1. Start Docker Services

```bash
cd /home/serviceuser/services/print_designer_test
docker compose -f compose.custom.yaml up -d
```

Wait 30-60 seconds for services to be ready, then check:

```bash
docker compose -f compose.custom.yaml ps
```

All services should show "Up" status.

### 2. Verify Backup Files

```bash
ls -lh /path/to/backups/
```

Should show:
- `database.sql` or `*.sql`
- `public_files.tar` or similar
- `private_files.tar` or similar
- `site_config.json` (CRITICAL!)

### 3. Check Disk Space

```bash
df -h
```

Ensure you have enough space (at least 2x the size of your backups).

## During Restoration

The script will:
1. Validate all files exist
2. Show a summary of what will be restored
3. Ask for confirmation (y/N)
4. Perform restoration (5-15 minutes depending on size)
5. Show success message with access URL

## After Restoration

### 1. Test Site Access

```bash
# Check the port from your .env file
cat .env | grep HTTP_PUBLISH_PORT
```

Then visit: `http://localhost:8080` (or your configured port)

### 2. Test Login

Use the admin credentials from your original backup.

### 3. Configure host_name for PDF Generation

```bash
docker compose -f compose.custom.yaml exec backend bash -c \
  "cd /home/frappe/frappe-bench && \
   bench --site localhost set-config host_name https://erp.mydomain.com"
```

Replace `erp.mydomain.com` with your actual domain.

## Troubleshooting Quick Fixes

### Services Won't Start

```bash
docker compose -f compose.custom.yaml down
docker compose -f compose.custom.yaml up -d
```

### Wrong Strip Components

Check tar structure:
```bash
tar -tvf /path/to/private_files.tar | head
```

Count directories before files, then use `--strip-components=N`.

### Database Name Detection Failed

Find the correct database name:
```bash
docker compose -f compose.custom.yaml exec backend bash -c \
  "cat /home/frappe/frappe-bench/sites/localhost/site_config.json" | grep db_name
```

Then use `--db-name` option:
```bash
./restore-backup.sh ... --db-name _your_db_name_here
```

### Encryption Key Issues

If encrypted data is inaccessible, you MUST provide the original `site_config.json`:
```bash
./restore-backup.sh ... -c /path/to/original_site_config.json
```

Without it, encrypted data cannot be recovered.

### View Logs

```bash
# Backend logs
docker compose -f compose.custom.yaml logs -f backend

# All logs
docker compose -f compose.custom.yaml logs -f

# Specific service
docker compose -f compose.custom.yaml logs -f scheduler
```

## Manual Backup Creation (For Reference)

If you need to create backups manually:

### 1. Database Backup

```bash
# Get database credentials
docker compose -f compose.custom.yaml exec backend bash -c \
  "cat /home/frappe/frappe-bench/sites/localhost/site_config.json" | \
  grep -E 'db_name|db_password'

# Export database
docker compose -f compose.custom.yaml exec db bash -c \
  'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" <db_name>' > database-$(date +%Y%m%d).sql
```

### 2. Files Backup

```bash
# Public files
docker compose -f compose.custom.yaml exec backend bash -c \
  "cd /home/frappe/frappe-bench && \
   tar -czf /tmp/public.tar.gz sites/localhost/public/files/"

docker compose -f compose.custom.yaml cp backend:/tmp/public.tar.gz ./public-$(date +%Y%m%d).tar.gz

# Private files
docker compose -f compose.custom.yaml exec backend bash -c \
  "cd /home/frappe/frappe-bench && \
   tar -czf /tmp/private.tar.gz sites/localhost/private/files/"

docker compose -f compose.custom.yaml cp backend:/tmp/private.tar.gz ./private-$(date +%Y%m%d).tar.gz
```

### 3. Site Config Backup

```bash
docker compose -f compose.custom.yaml cp \
  backend:/home/frappe/frappe-bench/sites/localhost/site_config.json \
  ./site_config-$(date +%Y%m%d).json
```

## Complete Restoration Example

```bash
# 1. Navigate to project directory
cd /home/serviceuser/services/print_designer_test

# 2. Ensure services are running
docker compose -f compose.custom.yaml up -d

# 3. Wait for services to be ready
sleep 30

# 4. Run restoration
./restore-backup.sh \
  -d /backups/20260117-database.sql \
  -p /backups/20260117-public_files.tar \
  -r /backups/20260117-private_files.tar \
  -s localhost \
  -c /backups/20260117-site_config.json \
  -n

# 5. Access site
echo "Site available at: http://localhost:$(grep HTTP_PUBLISH_PORT .env | cut -d'=' -f2)"
```

## Emergency Recovery

If restoration fails midway:

```bash
# 1. Stop all services
docker compose -f compose.custom.yaml down

# 2. Remove volumes (WARNING: This deletes all data)
docker volume rm print_designer_test_sites 2>/dev/null || true

# 3. Restart services
docker compose -f compose.custom.yaml up -d

# 4. Wait and retry restoration
sleep 60
./restore-backup.sh ... -n
```

## Help & Documentation

- Full guide: `cat RESTORE-GUIDE.md`
- Script help: `./restore-backup.sh --help`
- Project docs: `cat CLAUDE.md`
- Check script: `ls -lh restore-backup.sh`

## Key Points to Remember

1. **ALWAYS provide site_config.json** with `-c` option for encryption_key
2. **Check tar structure** if file extraction fails
3. **Ensure Docker services are running** before starting
4. **Wait for confirmation prompt** - review parameters before proceeding
5. **Monitor logs** if something goes wrong
6. **Test the restoration** in a dev environment first if possible

---

**Script Location**: `/home/serviceuser/services/print_designer_test/restore-backup.sh`

**For detailed information**, see: `RESTORE-GUIDE.md`
