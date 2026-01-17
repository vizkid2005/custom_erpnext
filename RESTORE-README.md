# ERPNext/Frappe Backup Restoration System

This directory contains automated scripts for restoring ERPNext/Frappe backups to your Dockerized environment.

## What's Included

### Scripts

1. **restore-backup.sh** (16 KB)
   - Main restoration script that automates the entire backup restore process
   - Handles database import, file extraction, encryption key restoration, migration, and cache clearing
   - Interactive with safety confirmations
   - Colored output for easy reading

2. **verify-backup.sh** (11 KB)
   - Pre-restoration validation tool
   - Checks backup file integrity, tar structure, and disk space
   - Validates site_config.json and detects encryption_key
   - Generates suggested restore command with correct parameters

### Documentation

3. **RESTORE-GUIDE.md** (8.7 KB)
   - Comprehensive restoration guide
   - Detailed explanations of all options
   - Troubleshooting section
   - Best practices for backups

4. **RESTORE-QUICKREF.md** (6.5 KB)
   - Quick reference card for common scenarios
   - Checklists and step-by-step commands
   - Common troubleshooting fixes
   - Emergency recovery procedures

## Quick Start

### Step 1: Verify Your Backups

Before restoration, verify your backup files are valid:

```bash
./verify-backup.sh \
  -d /path/to/database.sql \
  -p /path/to/public_files.tar \
  -r /path/to/private_files.tar \
  -c /path/to/site_config.json
```

This will:
- Check file existence and validity
- Detect tar archive structure
- Suggest correct --strip-components value
- Verify encryption_key presence
- Generate the exact restore command to use

### Step 2: Run Restoration

Use the command suggested by verify-backup.sh, or run manually:

```bash
./restore-backup.sh \
  -d /path/to/database.sql \
  -p /path/to/public_files.tar \
  -r /path/to/private_files.tar \
  -s localhost \
  -c /path/to/site_config.json
```

Add `-n` flag if you want to create a new site first:

```bash
./restore-backup.sh \
  -d /path/to/database.sql \
  -p /path/to/public_files.tar \
  -r /path/to/private_files.tar \
  -s localhost \
  -c /path/to/site_config.json \
  -n
```

## Typical Workflow

```bash
# 1. Navigate to project directory
cd /home/aqm-prod-admin/services/print_designer_test

# 2. Start Docker services
docker compose -f compose.custom.yaml up -d

# 3. Wait for services to be ready (30-60 seconds)
sleep 30

# 4. Verify backups
./verify-backup.sh \
  -d /backups/database.sql \
  -p /backups/public.tar \
  -r /backups/private.tar \
  -c /backups/site_config.json

# 5. Run restoration (use command from verify-backup.sh output)
./restore-backup.sh \
  -d /backups/database.sql \
  -p /backups/public.tar \
  -r /backups/private.tar \
  -s localhost \
  -c /backups/site_config.json

# 6. Access your restored site
echo "Site: http://localhost:$(grep HTTP_PUBLISH_PORT .env | cut -d'=' -f2)"
```

## Important Requirements

### Critical Files

1. **Database SQL dump** - The database backup (`.sql` file)
2. **Public files archive** - User-uploaded files visible to all (`.tar` file)
3. **Private files archive** - User-uploaded files with restricted access (`.tar` file)
4. **site_config.json** - CRITICAL for encryption_key (`.json` file)

**WARNING**: Without the original `site_config.json` containing the `encryption_key`, encrypted data (user passwords, API keys, OAuth tokens) will be permanently inaccessible!

### Prerequisites

- Docker and Docker Compose installed
- Docker services running (`docker compose -f compose.custom.yaml up -d`)
- Sufficient disk space (at least 3x the size of backups)
- Backup files accessible on disk

## Common Scenarios

### Scenario 1: Restore to Fresh Installation

```bash
# Create new site and restore everything
./restore-backup.sh -d db.sql -p public.tar -r private.tar \
  -s localhost -c site_config.json -n
```

### Scenario 2: Restore to Existing Site

```bash
# Restore to already-created site
./restore-backup.sh -d db.sql -p public.tar -r private.tar \
  -s localhost -c site_config.json
```

### Scenario 3: Restore with Wrong Tar Structure

```bash
# First, verify and get correct strip-components value
./verify-backup.sh -d db.sql -p public.tar -r private.tar

# Then restore with suggested value
./restore-backup.sh -d db.sql -p public.tar -r private.tar \
  -s localhost --strip-components=4
```

## Features

### restore-backup.sh Features

- ✓ Automatic database name detection
- ✓ Safe database drop/recreate
- ✓ Parallel file extraction
- ✓ Encryption key preservation
- ✓ Automatic migration execution
- ✓ Cache clearing
- ✓ Service restart
- ✓ Interactive confirmation prompts
- ✓ Colored status output
- ✓ Comprehensive error handling
- ✓ Configurable strip-components for tar

### verify-backup.sh Features

- ✓ File existence validation
- ✓ SQL file content verification
- ✓ Tar archive integrity check
- ✓ JSON validation for site_config
- ✓ Encryption key detection
- ✓ Tar structure analysis
- ✓ Docker service status check
- ✓ Disk space verification
- ✓ Auto-generate restore command
- ✓ Strip-components suggestion

## Help Commands

```bash
# Show restore script help
./restore-backup.sh --help

# Show verification script help
./verify-backup.sh --help

# View full guide
cat RESTORE-GUIDE.md

# View quick reference
cat RESTORE-QUICKREF.md

# View this readme
cat RESTORE-README.md
```

## Troubleshooting

### Common Issues

1. **Services not running**
   ```bash
   docker compose -f compose.custom.yaml up -d
   ```

2. **Wrong strip-components value**
   ```bash
   ./verify-backup.sh -d db.sql -p public.tar -r private.tar
   # Use suggested value in restore command
   ```

3. **Encryption key missing**
   ```bash
   # Always provide original site_config.json
   ./restore-backup.sh ... -c /path/to/original_site_config.json
   ```

4. **View logs for errors**
   ```bash
   docker compose -f compose.custom.yaml logs -f backend
   ```

### Getting Help

- Check `RESTORE-GUIDE.md` for detailed troubleshooting
- Check `RESTORE-QUICKREF.md` for quick fixes
- View Docker logs for specific errors
- Check main project documentation in `CLAUDE.md`

## What Happens During Restoration

The restoration process follows these steps:

1. **Validation Phase**
   - Checks all backup files exist
   - Validates Docker services are running
   - Loads environment variables

2. **Site Preparation**
   - Creates new site if requested (-n flag)
   - Detects database name from site config

3. **Database Restoration**
   - Drops existing database
   - Creates fresh database
   - Imports SQL backup
   - Cleans up temporary files

4. **File Restoration**
   - Copies tar archives to backend container
   - Extracts public files to sites/{sitename}/public/
   - Extracts private files to sites/{sitename}/private/
   - Removes temporary archives

5. **Configuration**
   - Restores encryption_key from site_config.json
   - Validates critical configuration keys

6. **Post-Restoration**
   - Runs bench migrate to update schema
   - Clears site cache
   - Restarts backend services
   - Verifies host_name configuration

7. **Completion**
   - Shows success message
   - Displays site access URL
   - Provides next steps

Total time: 5-15 minutes depending on backup size.

## Best Practices

1. **Always test first**: Try restoration in a dev environment before production
2. **Verify backups regularly**: Use verify-backup.sh to check backup integrity
3. **Keep site_config.json**: Store it securely with backups
4. **Document strip-components**: Note the value for your backup format
5. **Monitor logs**: Watch logs during restoration for issues
6. **Test after restore**: Verify login, file access, and PDF generation
7. **Backup before restore**: If restoring to existing site, backup first

## Security Notes

- site_config.json contains sensitive information (passwords, encryption keys)
- Store backups in secure locations
- Use strong DB_PASSWORD in .env file
- Don't commit backup files or site_config.json to version control
- Rotate encryption keys periodically (requires re-encrypting data)

## File Locations

```
/home/aqm-prod-admin/services/print_designer_test/
├── restore-backup.sh          # Main restoration script
├── verify-backup.sh           # Backup verification tool
├── RESTORE-README.md          # This file
├── RESTORE-GUIDE.md           # Comprehensive guide
├── RESTORE-QUICKREF.md        # Quick reference
├── compose.custom.yaml        # Docker compose config (you need to generate this)
└── .env                       # Environment variables
```

## Example: Complete Fresh Restoration

Here's a complete example of restoring to a fresh environment:

```bash
# Navigate to directory
cd /home/aqm-prod-admin/services/print_designer_test

# Ensure environment is configured
ls -lh .env compose.custom.yaml

# Start services
docker compose -f compose.custom.yaml up -d

# Wait for services
echo "Waiting for services to start..."
sleep 60

# Verify services are ready
docker compose -f compose.custom.yaml ps

# Verify backups
./verify-backup.sh \
  -d /mnt/backups/20260117-production-db.sql \
  -p /mnt/backups/20260117-production-public.tar \
  -r /mnt/backups/20260117-production-private.tar \
  -c /mnt/backups/20260117-production-site_config.json

# Run restoration (creating new site)
./restore-backup.sh \
  -d /mnt/backups/20260117-production-db.sql \
  -p /mnt/backups/20260117-production-public.tar \
  -r /mnt/backups/20260117-production-private.tar \
  -s localhost \
  -c /mnt/backups/20260117-production-site_config.json \
  -n

# Configure host_name for PDF generation
docker compose -f compose.custom.yaml exec backend bash -c \
  "cd /home/frappe/frappe-bench && \
   bench --site localhost set-config host_name https://erp.mydomain.com"

# Test access
echo "Site restored! Access at: http://localhost:8000"
```

## Support

For issues or questions:

1. Check the troubleshooting section in RESTORE-GUIDE.md
2. Review logs: `docker compose -f compose.custom.yaml logs -f backend`
3. Verify backup files with verify-backup.sh
4. Check main project documentation: CLAUDE.md
5. Consult Frappe documentation: https://frappeframework.com/docs

---

**Created**: 2026-01-17
**Version**: 1.0
**Maintained for**: ERPNext v15 / Frappe v15
