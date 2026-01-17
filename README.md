# ERPNext + HRMS (Version 15) Docker Setup

This guide documents the exact steps required to:

- Build a custom ERPNext + HRMS v15 Docker image
- Spin up a clean frappe_docker environment
- Create a new site (localhost)
- Restore a full ERPNext v15 backup
- Fix all common issues (site routing, DB users, permissions, etc.)

This guide provides a production-ready, reproducible deployment workflow.

## 1. Prerequisites

- Docker & Docker Compose installed
- Linux x86_64/AMD64 platform
- frappe_docker repository cloned:

```bash
git clone <your-frappe-docker-repo-url> custom_erpnext
cd custom_erpnext
```

**Example**:
```bash
git clone https://github.com/frappe/frappe_docker.git custom_erpnext
cd custom_erpnext
```

- Backup files available (if restoring from existing ERPNext installation):
  - `database.sql.gz`
  - `public_files.tar`
  - `private_files.tar`
  - `site_config.json` (old one, for encryption_key)

## 2. Build ERPNext + HRMS Custom Image

Create `apps.json`:

```json
[
  { "url": "https://github.com/frappe/erpnext", "branch": "version-15" },
  { "url": "https://github.com/frappe/hrms", "branch": "version-15" }
]
```

Base64-encode it:

```bash
export APPS_JSON_BASE64=$(base64 -w 0 apps.json)
```

Build your image:

```bash
docker build \
  --no-cache \
  --build-arg FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg FRAPPE_BRANCH=version-15 \
  --build-arg PYTHON_VERSION=3.11.6 \
  --build-arg NODE_VERSION=18.18.2 \
  --build-arg APPS_JSON_BASE64=$APPS_JSON_BASE64 \
  --file=images/layered/Containerfile \
  --tag=erpnext-hrms-local:15 .
```

## 3. Configure Environment

Edit `example.env` and include at minimum:

```bash
CUSTOM_IMAGE=erpnext-hrms-local
CUSTOM_TAG=15
PULL_POLICY=never

# Set secure passwords for database root access
MYSQL_ROOT_PASSWORD=<your-secure-root-password>
MARIADB_ROOT_PASSWORD=<your-secure-root-password>

SITE_NAME=localhost
# Set a strong admin password for ERPNext login
ADMIN_PASSWORD=<your-secure-admin-password>

# Required for site resolution (allows access via IP addresses)
# This is the standard for this setup
FRAPPE_SITE_NAME_HEADER=localhost
```

## 4. Generate SSL Certificates for Internal Proxy

Generate self-signed certificates for wkhtmltopdf PDF generation ([ref: frappe_docker#1547](https://github.com/frappe/frappe_docker/issues/1547)):

```bash
mkdir -p docker-configs/certs

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout docker-configs/certs/internal.key \
  -out docker-configs/certs/internal.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=erp.mydomain.com"

chmod 600 docker-configs/certs/internal.key
```

## 6. Generate Clean Compose File

```bash
docker compose --env-file example.env \
  -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.noproxy.yaml \
  config > compose.custom.yaml
```

## 7. Remove Existing Containers & Volumes

Clean start:

```bash
docker compose -f compose.custom.yaml down -v
docker volume rm frappe_docker_db-data frappe_docker_sites frappe_docker_redis-queue-data 2>/dev/null
```

## 8. Start Fresh Stack

```bash
docker compose -f compose.custom.yaml up -d
```

Check containers:

```bash
docker ps
```

## 9. Create a New Site

Inside backend:

```bash
docker compose -f compose.custom.yaml exec backend bash
cd /home/frappe/frappe-bench
```

Create site:

```bash
bench new-site localhost \
  --mariadb-user-host-login-scope=% \
  --admin-password "<your-secure-admin-password>" \
  --db-root-password "<your-secure-root-password>" \
  --install-app erpnext \
  --install-app hrms
```

**Note**: Use the same passwords you set in your `example.env` file.

Set default and configure host for PDF generation:

```bash
bench set-default-site localhost
bench --site localhost set-config host_name https://erp.mydomain.com
exit
```

Restart:

```bash
docker compose -f compose.custom.yaml restart backend frontend websocket scheduler queue-short queue-long
```

You should now see ERPNext login at:
- `http://localhost:8080`
- `http://<your-server-ip>:8080` (example: `http://192.168.1.100:8080`)

## 10. Restore Database Backup

Place your backup files in an accessible location (example: `/backups/erp/`).

**Required files**:
- `database.sql.gz` - Your database backup
- `public_files.tar` - Public file attachments
- `private_files.tar` - Private file attachments
- `site_config.json` - Your old site configuration (contains encryption key)

### 10.1 Extract SQL

Replace `/path/to/backup/` with your actual backup location:

```bash
gzip -d /path/to/backup/database.sql.gz
```

**Example**: `gzip -d /backups/erp/database.sql.gz`

### 10.2 Copy into db container

```bash
docker compose -f compose.custom.yaml cp /path/to/backup/database.sql db:/tmp/database.sql
```

**Example**: `docker compose -f compose.custom.yaml cp /backups/erp/database.sql db:/tmp/database.sql`

### 10.3 Get DB name & password from site_config.json

```bash
docker compose -f compose.custom.yaml exec backend bash -c \
  "cat /home/frappe/frappe-bench/sites/localhost/site_config.json | grep -E 'db_name|db_password'"
```

Example output (your values will be different):

```json
"db_name": "_abc123def456ghij",
"db_password": "RandomGeneratedPassword123"
```

**Note**: Copy these exact values for use in the next step.

### 10.4 Import SQL

Replace `<your-db-name>` with the `db_name` value from the previous step:

```bash
docker compose -f compose.custom.yaml exec db bash -c \
  'mariadb -u root -p"$MYSQL_ROOT_PASSWORD" <your-db-name> < /tmp/database.sql'
```

**Example**: If your db_name was `_abc123def456ghij`, the command would be:
```bash
docker compose -f compose.custom.yaml exec db bash -c \
  'mariadb -u root -p"$MYSQL_ROOT_PASSWORD" _abc123def456ghij < /tmp/database.sql'
```

## 11. Restore File Backups

### 11.1 Copy tar files

Replace `/path/to/backup/` with your actual backup location:

```bash
docker compose -f compose.custom.yaml cp /path/to/backup/public_files.tar backend:/home/frappe/frappe-bench/
docker compose -f compose.custom.yaml cp /path/to/backup/private_files.tar backend:/home/frappe/frappe-bench/
```

**Example**:
```bash
docker compose -f compose.custom.yaml cp /backups/erp/public_files.tar backend:/home/frappe/frappe-bench/
docker compose -f compose.custom.yaml cp /backups/erp/private_files.tar backend:/home/frappe/frappe-bench/
```

### 11.2 Extract inside backend

```bash
docker compose -f compose.custom.yaml exec backend bash
cd /home/frappe/frappe-bench

mkdir -p sites/localhost/public/files
mkdir -p sites/localhost/private/files
```

Check your archive structure to determine the correct `--strip-components` value. Your archive paths may look like:

```
home/<username>/frappe-bench/sites/<old-sitename>/private/files/...
```

**Example**: If the path is `home/john/frappe-bench/sites/erp.example.com/private/files/...`, use `--strip-components=6`:

```bash
# Count the directory levels: home(1)/john(2)/frappe-bench(3)/sites(4)/erp.example.com(5)/private(6)/files
```

Extract files:

```bash
tar -xvf private_files.tar -C sites/localhost/private --strip-components=6
tar -xvf public_files.tar  -C sites/localhost/public --strip-components=6
```

Exit backend:

```bash
exit
```

## 12. Restore the Old Encryption Key

**CRITICAL**: The encryption key from your old backup must be copied to the new site, otherwise encrypted data will be inaccessible.

Open your old backup's `site_config.json` and copy the encryption key:

```json
"encryption_key": "your-original-encryption-key-from-backup"
```

Edit the new site's config and replace the encryption_key value:

```bash
docker compose -f compose.custom.yaml exec backend bash -c \
  "nano /home/frappe/frappe-bench/sites/localhost/site_config.json"
```

**Example**: If your old encryption_key was `a1b2c3d4e5f6...`, paste that exact value into the new site_config.json.

## 13. Migrate & Clear Cache

```bash
docker compose -f compose.custom.yaml exec backend bash -c \
  "cd /home/frappe/frappe-bench && bench --site localhost migrate"

docker compose -f compose.custom.yaml exec backend bash -c \
  "cd /home/frappe/frappe-bench && bench --site localhost clear-cache"
```

## 14. Restart All Services

```bash
docker compose -f compose.custom.yaml restart backend frontend websocket scheduler queue-short queue-long
```

## 15. Login and Verify

Open: `http://<your-server-ip>:8080` or `http://localhost:8080`

**Example**: `http://192.168.1.100:8080`

Login using your old ERPNext credentials from the backup (not the new-site password you set during site creation).

Check:
- Customers / Items / Invoices exist
- Attachments load
- HRMS modules load
- PDF generation works (test print format)
- No DB errors
- No "site does not exist" errors

## Completion

Your ERPNext + HRMS v15 system is restored and running. This process ensures a fully reproducible, clean, and battle-tested deployment workflow.
