# ERPNext + HRMS (Version 15) Docker Setup

This guide documents the exact steps required to:

- Build a custom ERPNext + HRMS v15 Docker image
- Spin up a clean frappe_docker environment
- Create a new site (localhost)
- Restore a full ERPNext v15 backup
- Fix all common issues (site routing, DB users, permissions, etc.)

It reflects the final working solution used in December 2025.

## 1. Prerequisites

- Docker & Docker Compose installed
- Apple Silicon: use `linux/arm64`
- Repository cloned:

```bash
git clone <your-custom-repo> custom_erpnext
cd custom_erpnext
```

- Backup files available:
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

Base64-encode it (macOS compatible):

```bash
export APPS_JSON_BASE64="$(base64 < apps.json | tr -d '\n')"
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

PLATFORM=linux/arm64     # on Apple Silicon

MYSQL_ROOT_PASSWORD=123
MARIADB_ROOT_PASSWORD=123

SITE_NAME=localhost
ADMIN_PASSWORD=Admin123!

# Required when accessing via IP (e.g., 192.168.4.10)
FRAPPE_SITE_NAME_HEADER=localhost
```

## 4. Generate Clean Compose File

```bash
docker compose --env-file example.env \
  -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.noproxy.yaml \
  config > compose.custom.yaml
```

Remove any `platform: linux/amd64` lines if present.

## 5. Remove Existing Containers & Volumes

Clean start:

```bash
docker compose -f compose.custom.yaml down -v
docker volume rm frappe_docker_db-data frappe_docker_sites frappe_docker_redis-queue-data 2>/dev/null
```

## 6. Start Fresh Stack

```bash
docker compose -f compose.custom.yaml up -d
```

Check containers:

```bash
docker ps
```

## 7. Create a New Site

Inside backend:

```bash
docker compose -f compose.custom.yaml exec backend bash
cd /home/frappe/frappe-bench
```

Create site:

```bash
bench new-site localhost \
  --admin-password "Admin123!" \
  --db-root-username root \
  --db-root-password "123" \
  --install-app erpnext \
  --install-app hrms
```

Set default:

```bash
bench set-default-site localhost
exit
```

Restart:

```bash
docker compose -f compose.custom.yaml restart backend frontend websocket scheduler queue-short queue-long
```

You should now see ERPNext login at:
- `http://localhost:8080`
- `http://192.168.4.10:8080`

## 8. Restore Database Backup

Place your backup in `/backups/erp/`.

### 8.1 Extract SQL

```bash
gzip -d /backups/erp/database.sql.gz
```

### 8.2 Copy into db container

```bash
docker compose -f compose.custom.yaml cp /backups/erp/database.sql db:/tmp/database.sql
```

### 8.3 Get DB name & password from site_config.json

```bash
docker compose -f compose.custom.yaml exec backend bash -c \
  "cat /home/frappe/frappe-bench/sites/localhost/site_config.json | grep -E 'db_name|db_password'"
```

Example output:

```json
"db_name": "_77f5e42251d79843",
"db_password": "FvbE6ZYLo*RWEWsB"
```

### 8.4 Import SQL

```bash
docker compose -f compose.custom.yaml exec db bash -c \
  'mariadb -u root -p"$MYSQL_ROOT_PASSWORD" _77f5e42251d79843 < /tmp/database.sql'
```

## 9. Restore File Backups

### 9.1 Copy tar files

```bash
docker compose -f compose.custom.yaml cp /backups/erp/public_files.tar backend:/home/frappe/frappe-bench/
docker compose -f compose.custom.yaml cp /backups/erp/private_files.tar backend:/home/frappe/frappe-bench/
```

### 9.2 Extract inside backend

```bash
docker compose -f compose.custom.yaml exec backend bash
cd /home/frappe/frappe-bench

mkdir -p sites/localhost/public/files
mkdir -p sites/localhost/private/files
```

Your archive paths look like:

```
home/<user>/frappe-bench/sites/<oldsite>/private/files/...
```

Use `--strip-components=6`:

```bash
tar -xvf private_files.tar -C sites/localhost/private --strip-components=6
tar -xvf public_files.tar  -C sites/localhost/public --strip-components=6
```

Exit backend:

```bash
exit
```

## 10. Restore the Old Encryption Key

Open old `site_config.json` and copy:

```json
"encryption_key": "xxxx..."
```

Replace in:

```bash
docker compose -f compose.custom.yaml exec backend bash -c \
  "nano /home/frappe/frappe-bench/sites/localhost/site_config.json"
```

## 11. Migrate & Clear Cache

```bash
docker compose -f compose.custom.yaml exec backend bash -c \
  "cd /home/frappe/frappe-bench && bench --site localhost migrate"

docker compose -f compose.custom.yaml exec backend bash -c \
  "cd /home/frappe/frappe-bench && bench --site localhost clear-cache"
```

## 12. Restart All Services

```bash
docker compose -f compose.custom.yaml restart backend frontend websocket scheduler queue-short queue-long
```

## 13. Login and Verify

Open: `http://192.168.4.10:8080`

Login using your old ERPNext credentials (not the new-site password).

Check:
- Customers / Items / Invoices exist
- Attachments load
- HRMS modules load
- No DB errors
- No "site does not exist" errors

## Completion

Your ERPNext + HRMS v15 system is restored and running. This process ensures a fully reproducible, clean, and battle-tested deployment workflow.
