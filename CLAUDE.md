# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a **frappe_docker** repository for deploying ERPNext + HRMS (Human Resource Management System) version 15 using Docker containerization. It provides a complete Docker orchestration setup with customizable configurations for development and production deployments.

Current configuration includes ERPNext v15 with HRMS v15 apps.

**Platform**: Linux x86_64/AMD64
**Working versions**: Python 3.11.6, Node.js 18.18.2

## Common Commands

### Building Custom Images

Build a custom image with ERPNext + HRMS (or other apps):

```bash
# Create apps.json with desired apps
cat > apps.json << 'EOF'
[
  {"url": "https://github.com/frappe/erpnext", "branch": "version-15"},
  {"url": "https://github.com/frappe/hrms", "branch": "version-15"}
]
EOF

# Encode apps.json to base64
export APPS_JSON_BASE64=$(base64 -w 0 apps.json)

# Build the image using layered Containerfile
docker build \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=version-15 \
  --build-arg=PYTHON_VERSION=3.11.6 \
  --build-arg=NODE_VERSION=18.18.2 \
  --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
  --tag=erpnext-hrms-local:15 \
  --file=images/layered/Containerfile .
```

For production builds, use `images/production/Containerfile` instead.

### Generating Compose Configuration

Generate the final compose file from base + overrides:

```bash
# Common setup: MariaDB + Redis + No proxy (direct port exposure)
docker compose --env-file example.env \
  -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.noproxy.yaml \
  config > compose.custom.yaml
```

### Starting/Stopping Services

```bash
# Start all services
docker compose -f compose.custom.yaml up -d

# Stop all services
docker compose -f compose.custom.yaml down

# Restart specific services (common after config changes)
docker compose -f compose.custom.yaml restart backend frontend websocket scheduler queue-short queue-long

# View logs
docker compose -f compose.custom.yaml logs -f backend
```

### Site Operations

All bench commands run inside the `backend` container:

```bash
# Create a new site
docker compose -f compose.custom.yaml exec backend bash -c \
  "cd /home/frappe/frappe-bench && bench new-site localhost \
  --mariadb-user-host-login-scope=% \
  --admin-password 'Admin123!' \
  --db-root-password '123' \
  --install-app erpnext \
  --install-app hrms"

# Set default site
docker compose -f compose.custom.yaml exec backend bash -c \
  "cd /home/frappe/frappe-bench && bench set-default-site localhost"

# Migrate site (after restore or updates)
docker compose -f compose.custom.yaml exec backend bash -c \
  "cd /home/frappe/frappe-bench && bench --site localhost migrate"

# Clear cache
docker compose -f compose.custom.yaml exec backend bash -c \
  "cd /home/frappe/frappe-bench && bench --site localhost clear-cache"

# Access bench shell
docker compose -f compose.custom.yaml exec backend bash
```

### Database Operations

```bash
# Get site database credentials
docker compose -f compose.custom.yaml exec backend bash -c \
  "cat /home/frappe/frappe-bench/sites/localhost/site_config.json | grep -E 'db_name|db_password'"

# Import database backup
docker compose -f compose.custom.yaml cp /path/to/database.sql db:/tmp/database.sql
docker compose -f compose.custom.yaml exec db bash -c \
  'mariadb -u root -p"$MYSQL_ROOT_PASSWORD" <db_name> < /tmp/database.sql'

# Access MariaDB shell
docker compose -f compose.custom.yaml exec db bash -c \
  'mariadb -u root -p"$MYSQL_ROOT_PASSWORD"'
```

### File Restoration

```bash
# Copy backup files to backend
docker compose -f compose.custom.yaml cp /path/to/public_files.tar backend:/home/frappe/frappe-bench/
docker compose -f compose.custom.yaml cp /path/to/private_files.tar backend:/home/frappe/frappe-bench/

# Extract files (adjust --strip-components based on archive structure)
docker compose -f compose.custom.yaml exec backend bash -c \
  "cd /home/frappe/frappe-bench && \
   tar -xvf private_files.tar -C sites/localhost/private --strip-components=6 && \
   tar -xvf public_files.tar -C sites/localhost/public --strip-components=6"
```

### Testing

```bash
# Install test dependencies
pip install -r requirements-test.txt

# Run pytest tests
pytest tests/ -v

# Run specific test
pytest tests/test_frappe_docker.py::TestClass::test_method -v
```

## Architecture

### Service Structure

The compose setup defines these core services:

- **configurator**: One-time initialization service that sets up bench configuration (DB host, Redis, socketio port)
- **backend**: Gunicorn application server (port 8000) running Frappe/ERPNext Python backend
- **frontend**: NGINX reverse proxy (port 8080 by default) serving static files and proxying to backend/websocket
- **websocket**: Node.js Socket.IO server (port 9000) for real-time communications
- **queue-short**: Worker for short-running background jobs
- **queue-long**: Worker for long-running background jobs (also handles short/default queues)
- **scheduler**: Bench scheduler service for cron-like scheduled tasks
- **internal-proxy**: Additional NGINX proxy for internal HTTPS routing (custom addition)

Database and cache services come from override files:
- **db**: MariaDB 11.8 or PostgreSQL (via overrides)
- **redis-cache**: Redis for caching layer
- **redis-queue**: Redis for job queue

### Image Types

Located in `images/` directory:

1. **bench** (`images/bench/Dockerfile`): Base development image with Python, Node.js, Frappe bench CLI, and all development tools. Multi-version support for Python (3.10, 3.11) and Node.js (16, 18, 20).

2. **layered** (`images/layered/Containerfile`): Multi-stage production build (builder → base) optimized for custom app combinations. Takes `APPS_JSON_BASE64` parameter.

3. **production** (`images/production/Containerfile`): Full-featured production image with health checks, wkhtmltopdf for PDF generation, and Restic for backups.

4. **custom** (`images/custom/Containerfile`): Development image for custom apps.

### Build System

Uses **Docker Buildx Bake** (`docker-bake.hcl`) for:
- Multi-platform builds (linux/amd64, linux/arm64)
- Version matrix management (Frappe versions, Python versions, Node.js versions)
- Automated tagging (version tags, major version tags, latest tags)
- Build targets: `erpnext`, `base`, `build`, `bench`

CI/CD via GitHub Actions builds and publishes multi-architecture images automatically.

### Override System

Compose override files in `overrides/` directory provide modular configuration:

- **Database**: `compose.mariadb.yaml`, `compose.postgres.yaml`, `compose.mariadb-shared.yaml`
- **Caching**: `compose.redis.yaml`
- **Networking**: `compose.noproxy.yaml` (direct port exposure), `compose.proxy.yaml`, `compose.traefik.yaml`
- **SSL/TLS**: `compose.https.yaml`, `compose.traefik-ssl.yaml`, `compose.custom-domain-ssl.yaml`
- **Multi-tenancy**: `compose.multi-bench.yaml`, `compose.multi-bench-ssl.yaml`
- **Backups**: `compose.backup-cron.yaml`

Combine multiple overrides using `-f` flag when generating compose config.

### Volume Architecture

- **sites**: Shared volume mounted across backend, frontend, websocket, and queue services containing:
  - `/home/frappe/frappe-bench/sites/<sitename>/` directories
  - `site_config.json` (DB credentials, encryption keys)
  - `public/files/` and `private/files/` directories
  - `apps.txt` (list of installed apps)

### Site Configuration

Critical site configuration in `sites/<sitename>/site_config.json`:
- `db_name`: Database name (auto-generated UUID-based)
- `db_password`: Database user password
- `encryption_key`: **CRITICAL** - Must be preserved when restoring backups, otherwise encrypted data becomes inaccessible
- Redis connection strings
- Site-specific settings

When restoring from backup, the `encryption_key` from the original `site_config.json` must be copied to the new site's config.

### Platform Considerations

- This setup is configured for Linux x86_64/AMD64 platform
- Multi-platform builds use QEMU emulation in CI/CD

### Environment Variables

Key variables in `example.env` or `.env`:

- `CUSTOM_IMAGE`: Docker image name (e.g., `erpnext-hrms-local`)
- `CUSTOM_TAG`: Image tag (e.g., `15`)
- `PULL_POLICY`: `never` for local images, `always` for remote
- `SITE_NAME`: Default site name (e.g., `localhost`)
- `ADMIN_PASSWORD`: Administrator password for new sites
- `DB_PASSWORD`: Database root password
- `FRAPPE_SITE_NAME_HEADER`: Override site resolution (useful for IP-based access)
- `HTTP_PUBLISH_PORT`: Frontend port (default: `8080`)
- `ERPNEXT_VERSION`: Version tag for pulling pre-built images

## Development Workflow

1. Clone repository and create `apps.json` with desired apps
2. Build custom Docker image with apps
3. Copy and edit `example.env` to configure environment
4. Generate compose file using base + overrides
5. Start services with `docker compose up -d`
6. Create new site or restore from backup
7. Access site at `http://localhost:8080` (or configured port)

For debugging, access backend container shell and use standard `bench` commands. Logs are available via `docker compose logs`.

## Testing Infrastructure

- Test suite in `tests/test_frappe_docker.py` uses pytest
- Fixtures in `tests/conftest.py` handle environment setup, site creation, ERPNext installation
- CI configuration in `tests/compose.ci.yaml`
- Tests cover: backend connectivity, API endpoints, file uploads, ERPNext setup, PostgreSQL support, HTTPS, S3 backups

Run tests with `pytest tests/ -v` after installing `requirements-test.txt`.

## Documentation

Comprehensive documentation in `docs/` organized by topic:

- `01-getting-started/`: Quick start guides for different platforms
- `02-setup/`: Build, start, environment variables, overrides, examples
- `03-production/`: TLS/SSL, backups, multi-tenancy
- `04-operations/`: Site operations (create, migrate, backup)
- `05-development/`: Development workflows and debugging
- `06-migration/`: Migration guides from older setups
- `07-troubleshooting/`: Common issues and solutions
- `08-reference/`: Historical reference materials

Refer to these docs for detailed procedures and troubleshooting.
