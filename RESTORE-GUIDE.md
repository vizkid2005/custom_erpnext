# Backup Restoration Guide

This guide explains how to use the `restore-backup.sh` script to restore ERPNext/Frappe backups to your Dockerized environment.

## Prerequisites

1. Docker and Docker Compose installed and running
2. Docker services started (`docker compose -f compose.custom.yaml up -d`)
3. Backup files available on disk:
   - Database SQL dump (`.sql` file)
   - Public files archive (`.tar` file)
   - Private files archive (`.tar` file)
   - Original `site_config.json` (recommended, for encryption_key)

## Quick Start

### Basic Restoration (Existing Site)

If you already have a site created and want to restore data to it:

```bash
./restore-backup.sh \
  -d /path/to/database-backup.sql \
  -p /path/to/public-files.tar \
  -r /path/to/private-files.tar \
  -s localhost
```

### Full Restoration (New Site)

If you want to create a new site and restore data to it:

```bash
./restore-backup.sh \
  -d /path/to/database-backup.sql \
  -p /path/to/public-files.tar \
  -r /path/to/private-files.tar \
  -s localhost \
  -c /path/to/site_config.json \
  -n
```

## Command Line Options

### Required Options

- `-d, --database PATH` - Path to database SQL backup file
- `-p, --public PATH` - Path to public files tar archive
- `-r, --private PATH` - Path to private files tar archive
- `-s, --site NAME` - Site name (e.g., `localhost` or `erp.example.com`)

### Optional Options

- `-c, --config PATH` - Path to original `site_config.json` (highly recommended)
- `-f, --compose-file PATH` - Path to docker compose file (default: `compose.custom.yaml`)
- `-n, --new-site` - Create a new site before restoration
- `--db-name NAME` - Database name (auto-detected if not provided)
- `--strip-components N` - Number of path components to strip from tar (default: 6)
- `--skip-migration` - Skip running bench migrate after restoration
- `-h, --help` - Display help message

## Important Notes

### Encryption Key

**CRITICAL**: The `encryption_key` in `site_config.json` is essential for accessing encrypted data (like user passwords, API keys, etc.). Without the original encryption key, you cannot decrypt this data.

Always provide the original `site_config.json` using the `-c` option when restoring from backups.

### Strip Components

The `--strip-components` option tells tar how many leading directory components to remove when extracting files. The default value is `6`, which works for most Frappe backups.

If file extraction fails, check your tar archive structure:

```bash
# Check the structure of your tar file
tar -tvf /path/to/public-files.tar | head -n 20
```

Count the directory levels before the actual files and adjust `--strip-components` accordingly.

Example structure:
```
./home/frappe/frappe-bench/sites/sitename/public/files/image.png
└─┴──┴────┴───────────┴────┴────────┴──────┴─────┴─────────
  1  2    3           4     5        6      7     8 (file)
```

In this case, use `--strip-components=7` to extract files directly.

### Apps Installation

The script assumes that all apps required by the backup are already included in your Docker image. If your backup includes custom apps not in the image, you'll need to rebuild the Docker image with those apps first.

### Database Credentials

The script uses environment variables from `.env` or `example.env`:
- `DB_PASSWORD` - MariaDB root password
- `ADMIN_PASSWORD` - Admin password for new sites

Ensure these are set correctly before running the script.

## Restoration Process

The script performs these steps in order:

1. **Validation** - Checks that all backup files and Docker services exist
2. **Site Creation** (if `-n` flag used) - Creates a new site with specified name
3. **Database Detection** - Automatically detects database name from site config
4. **Database Drop & Recreate** - Drops existing database and creates a fresh one
5. **Database Import** - Imports the SQL backup into the new database
6. **Files Restoration** - Extracts public and private files to the site directories
7. **Encryption Key** - Restores the encryption_key from backup site_config.json
8. **Migration** - Runs `bench migrate` to update database schema
9. **Cache Clear** - Clears site cache
10. **Services Restart** - Restarts backend services to apply changes

## Examples

### Example 1: Restore to Existing Site

```bash
./restore-backup.sh \
  -d /backups/20260117_database.sql \
  -p /backups/20260117_public_files.tar \
  -r /backups/20260117_private_files.tar \
  -s localhost \
  -c /backups/20260117_site_config.json
```

### Example 2: Create New Site and Restore

```bash
./restore-backup.sh \
  -d /backups/production_db.sql \
  -p /backups/production_public.tar \
  -r /backups/production_private.tar \
  -s erp.example.com \
  -c /backups/production_site_config.json \
  -n
```

### Example 3: Custom Strip Components

```bash
./restore-backup.sh \
  -d /backups/db.sql \
  -p /backups/public.tar \
  -r /backups/private.tar \
  -s localhost \
  --strip-components=4
```

### Example 4: Skip Migration (Debug Mode)

```bash
./restore-backup.sh \
  -d /backups/db.sql \
  -p /backups/public.tar \
  -r /backups/private.tar \
  -s localhost \
  -c /backups/site_config.json \
  --skip-migration
```

## Troubleshooting

### Issue: "Database backup not found"

**Solution**: Ensure the path to your backup file is correct and absolute. Use tab completion or `ls` to verify.

### Issue: "Docker services are not running"

**Solution**: Start your Docker services first:
```bash
docker compose -f compose.custom.yaml up -d
```

Wait a minute for all services to be healthy, then retry.

### Issue: "Failed to extract private files"

**Solution**: Check the tar archive structure and adjust `--strip-components`:

```bash
# View tar structure
tar -tvf /path/to/private_files.tar | head

# Try different strip values
./restore-backup.sh ... --strip-components=5
```

### Issue: "Could not detect database name"

**Solution**: Manually specify the database name:
```bash
./restore-backup.sh ... --db-name _abc123def456
```

Or check the site_config.json in your existing site:
```bash
docker compose -f compose.custom.yaml exec backend bash -c \
  "cat /home/frappe/frappe-bench/sites/localhost/site_config.json"
```

### Issue: "Migration failed"

**Possible causes**:
1. Apps missing from Docker image
2. Version mismatch between backup and current ERPNext version
3. Corrupted database backup

**Solution**:
- Check logs: `docker compose -f compose.custom.yaml logs backend`
- Ensure your Docker image includes all apps from the backup
- Verify backup integrity

### Issue: "Encrypted data not accessible after restore"

**Solution**: This means the encryption_key wasn't properly restored. You must provide the original `site_config.json`:

```bash
./restore-backup.sh ... -c /path/to/original_site_config.json
```

Without the original encryption key, encrypted data cannot be recovered.

## Post-Restoration Steps

After successful restoration:

1. **Verify Site Access**: Visit `http://localhost:8080` (or your configured port)

2. **Check Admin Login**: Log in with your original admin credentials

3. **Configure host_name** (for PDF generation):
   ```bash
   docker compose -f compose.custom.yaml exec backend bash -c \
     "cd /home/frappe/frappe-bench && \
      bench --site localhost set-config host_name https://erp.mydomain.com"
   ```

4. **Verify File Access**: Check if uploaded files are accessible

5. **Test Key Functionality**:
   - Create a test document
   - Generate a PDF report
   - Check if scheduled jobs are running

6. **Monitor Logs**: Keep an eye on logs for any errors
   ```bash
   docker compose -f compose.custom.yaml logs -f backend
   ```

## Backup Best Practices

To ensure smooth restorations in the future:

1. **Always backup site_config.json**: This contains the critical encryption_key
2. **Use consistent backup format**: Keep the same tar structure
3. **Test your backups**: Periodically test restoration in a dev environment
4. **Document strip-components**: Note the value that works for your backups
5. **Version your backups**: Include date/version in backup filenames
6. **Store backups securely**: Keep multiple copies in different locations

## Getting Help

If you encounter issues:

1. Check logs: `docker compose -f compose.custom.yaml logs -f backend`
2. Review the script output for error messages
3. Verify all prerequisites are met
4. Check the main CLAUDE.md documentation
5. Consult Frappe documentation at https://frappeframework.com/docs

## Script Location

The restoration script is located at:
```
/home/serviceuser/services/print_designer_test/restore-backup.sh
```

Make it executable if needed:
```bash
chmod +x restore-backup.sh
```
