#!/bin/bash

#
# ERPNext/Frappe Docker Backup Restoration Script
#
# This script automates the restoration of ERPNext/Frappe backups including:
# - Database restoration
# - Public and private files restoration
# - Site configuration (encryption_key preservation)
# - Post-restore migration and cache clearing
#

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
COMPOSE_FILE="compose.custom.yaml"
STRIP_COMPONENTS=6
SITE_NAME=""
DB_NAME=""
BACKUP_DB_PATH=""
BACKUP_PUBLIC_PATH=""
BACKUP_PRIVATE_PATH=""
BACKUP_SITE_CONFIG_PATH=""
CREATE_NEW_SITE=false
SKIP_MIGRATION=false

# Functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Restore ERPNext/Frappe backup from disk files.

Required Options:
    -d, --database PATH         Path to database SQL backup file
    -p, --public PATH           Path to public files tar archive
    -r, --private PATH          Path to private files tar archive
    -s, --site NAME             Site name (e.g., localhost or erp.example.com)

Optional Options:
    -c, --config PATH           Path to original site_config.json (for encryption_key)
    -f, --compose-file PATH     Path to docker compose file (default: compose.custom.yaml)
    -n, --new-site              Create a new site before restoration
    --db-name NAME              Database name (auto-detected if not provided)
    --strip-components N        Number of leading path components to strip from tar (default: 6)
    --skip-migration            Skip running bench migrate after restoration
    -h, --help                  Display this help message

Examples:
    # Restore to existing site
    $0 -d /backups/database.sql -p /backups/public.tar -r /backups/private.tar -s localhost

    # Restore with site config and create new site
    $0 -d /backups/db.sql -p /backups/public.tar -r /backups/private.tar \\
       -s localhost -c /backups/site_config.json -n

    # Restore with custom compose file
    $0 -d /backups/db.sql -p /backups/public.tar -r /backups/private.tar \\
       -s erp.example.com -f /path/to/compose.yaml

EOF
}

# Parse command line arguments
parse_args() {
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 1
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--database)
                BACKUP_DB_PATH="$2"
                shift 2
                ;;
            -p|--public)
                BACKUP_PUBLIC_PATH="$2"
                shift 2
                ;;
            -r|--private)
                BACKUP_PRIVATE_PATH="$2"
                shift 2
                ;;
            -s|--site)
                SITE_NAME="$2"
                shift 2
                ;;
            -c|--config)
                BACKUP_SITE_CONFIG_PATH="$2"
                shift 2
                ;;
            -f|--compose-file)
                COMPOSE_FILE="$2"
                shift 2
                ;;
            -n|--new-site)
                CREATE_NEW_SITE=true
                shift
                ;;
            --db-name)
                DB_NAME="$2"
                shift 2
                ;;
            --strip-components)
                STRIP_COMPONENTS="$2"
                shift 2
                ;;
            --skip-migration)
                SKIP_MIGRATION=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$BACKUP_DB_PATH" || -z "$BACKUP_PUBLIC_PATH" || -z "$BACKUP_PRIVATE_PATH" || -z "$SITE_NAME" ]]; then
        print_error "Missing required arguments"
        print_usage
        exit 1
    fi
}

# Validate files exist
validate_files() {
    print_info "Validating backup files..."

    if [[ ! -f "$BACKUP_DB_PATH" ]]; then
        print_error "Database backup not found: $BACKUP_DB_PATH"
        exit 1
    fi

    if [[ ! -f "$BACKUP_PUBLIC_PATH" ]]; then
        print_error "Public files backup not found: $BACKUP_PUBLIC_PATH"
        exit 1
    fi

    if [[ ! -f "$BACKUP_PRIVATE_PATH" ]]; then
        print_error "Private files backup not found: $BACKUP_PRIVATE_PATH"
        exit 1
    fi

    if [[ -n "$BACKUP_SITE_CONFIG_PATH" && ! -f "$BACKUP_SITE_CONFIG_PATH" ]]; then
        print_error "Site config backup not found: $BACKUP_SITE_CONFIG_PATH"
        exit 1
    fi

    if [[ ! -f "$COMPOSE_FILE" ]]; then
        print_error "Docker compose file not found: $COMPOSE_FILE"
        exit 1
    fi

    print_success "All backup files validated"
}

# Check if services are running
check_services() {
    print_info "Checking if Docker services are running..."

    if ! docker compose -f "$COMPOSE_FILE" ps | grep -q "Up"; then
        print_error "Docker services are not running. Please start them first with:"
        print_error "  docker compose -f $COMPOSE_FILE up -d"
        exit 1
    fi

    print_success "Docker services are running"
}

# Load environment variables
load_env() {
    if [[ -f ".env" ]]; then
        print_info "Loading environment variables from .env"
        set -a
        source .env
        set +a
    elif [[ -f "example.env" ]]; then
        print_warning ".env not found, using example.env"
        set -a
        source example.env
        set +a
    else
        print_error "No .env or example.env file found"
        exit 1
    fi
}

# Create new site if requested
create_site() {
    if [[ "$CREATE_NEW_SITE" == true ]]; then
        print_info "Creating new site: $SITE_NAME"

        docker compose -f "$COMPOSE_FILE" exec backend bash -c \
            "cd /home/frappe/frappe-bench && bench new-site $SITE_NAME \
            --mariadb-user-host-login-scope=% \
            --admin-password '${ADMIN_PASSWORD:-Admin123!}' \
            --db-root-password '${DB_PASSWORD:-123}' \
            --no-mariadb-socket" || {
            print_error "Failed to create site"
            exit 1
        }

        print_success "Site created successfully"

        # Set as default site
        print_info "Setting $SITE_NAME as default site"
        docker compose -f "$COMPOSE_FILE" exec backend bash -c \
            "cd /home/frappe/frappe-bench && bench set-default-site $SITE_NAME"
    fi
}

# Get database name from site config
get_db_name() {
    if [[ -z "$DB_NAME" ]]; then
        print_info "Detecting database name from site configuration..."

        DB_NAME=$(docker compose -f "$COMPOSE_FILE" exec backend bash -c \
            "cat /home/frappe/frappe-bench/sites/$SITE_NAME/site_config.json" | \
            grep -o '"db_name": *"[^"]*"' | \
            cut -d'"' -f4)

        if [[ -z "$DB_NAME" ]]; then
            print_error "Could not detect database name. Please specify with --db-name"
            exit 1
        fi

        print_success "Database name detected: $DB_NAME"
    fi
}

# Drop and recreate database
drop_and_create_db() {
    print_warning "Dropping existing database: $DB_NAME"

    docker compose -f "$COMPOSE_FILE" exec db bash -c \
        "mariadb -u root -p\"\$MYSQL_ROOT_PASSWORD\" -e 'DROP DATABASE IF EXISTS \`$DB_NAME\`;'" || {
        print_error "Failed to drop database"
        exit 1
    }

    print_info "Creating fresh database: $DB_NAME"

    docker compose -f "$COMPOSE_FILE" exec db bash -c \
        "mariadb -u root -p\"\$MYSQL_ROOT_PASSWORD\" -e 'CREATE DATABASE \`$DB_NAME\`;'" || {
        print_error "Failed to create database"
        exit 1
    }

    print_success "Database recreated"
}

# Restore database
restore_database() {
    print_info "Copying database backup to container..."

    docker compose -f "$COMPOSE_FILE" cp "$BACKUP_DB_PATH" db:/tmp/database.sql || {
        print_error "Failed to copy database backup"
        exit 1
    }

    print_info "Importing database backup (this may take a while)..."

    docker compose -f "$COMPOSE_FILE" exec db bash -c \
        "mariadb -u root -p\"\$MYSQL_ROOT_PASSWORD\" $DB_NAME < /tmp/database.sql" || {
        print_error "Failed to import database"
        exit 1
    }

    print_info "Cleaning up temporary database file..."
    docker compose -f "$COMPOSE_FILE" exec db rm /tmp/database.sql

    print_success "Database restored successfully"
}

# Restore files
restore_files() {
    print_info "Copying file backups to container..."

    docker compose -f "$COMPOSE_FILE" cp "$BACKUP_PUBLIC_PATH" backend:/home/frappe/frappe-bench/public_files.tar || {
        print_error "Failed to copy public files backup"
        exit 1
    }

    docker compose -f "$COMPOSE_FILE" cp "$BACKUP_PRIVATE_PATH" backend:/home/frappe/frappe-bench/private_files.tar || {
        print_error "Failed to copy private files backup"
        exit 1
    }

    print_info "Extracting private files..."
    docker compose -f "$COMPOSE_FILE" exec backend bash -c \
        "cd /home/frappe/frappe-bench && \
         tar -xvf private_files.tar -C sites/$SITE_NAME/private --strip-components=$STRIP_COMPONENTS" || {
        print_warning "Failed to extract private files (check --strip-components value)"
    }

    print_info "Extracting public files..."
    docker compose -f "$COMPOSE_FILE" exec backend bash -c \
        "cd /home/frappe/frappe-bench && \
         tar -xvf public_files.tar -C sites/$SITE_NAME/public --strip-components=$STRIP_COMPONENTS" || {
        print_warning "Failed to extract public files (check --strip-components value)"
    }

    print_info "Cleaning up temporary file archives..."
    docker compose -f "$COMPOSE_FILE" exec backend bash -c \
        "rm /home/frappe/frappe-bench/public_files.tar /home/frappe/frappe-bench/private_files.tar"

    print_success "Files restored successfully"
}

# Restore encryption key from backup site_config.json
restore_encryption_key() {
    if [[ -n "$BACKUP_SITE_CONFIG_PATH" ]]; then
        print_info "Extracting encryption_key from backup site_config.json..."

        ENCRYPTION_KEY=$(grep -o '"encryption_key": *"[^"]*"' "$BACKUP_SITE_CONFIG_PATH" | cut -d'"' -f4)

        if [[ -n "$ENCRYPTION_KEY" ]]; then
            print_info "Updating encryption_key in site configuration..."

            docker compose -f "$COMPOSE_FILE" exec backend bash -c \
                "cd /home/frappe/frappe-bench && \
                 bench --site $SITE_NAME set-config encryption_key '$ENCRYPTION_KEY'" || {
                print_error "Failed to update encryption_key"
                exit 1
            }

            print_success "Encryption key restored"
        else
            print_warning "No encryption_key found in backup site_config.json"
        fi
    else
        print_warning "No site_config.json provided. Encryption key not restored."
        print_warning "If the backup contained encrypted data, provide the original site_config.json with -c option"
    fi
}

# Install apps if needed
install_apps() {
    print_info "Checking if apps need to be installed..."

    # Get list of apps from restored database
    APPS_IN_BACKUP=$(docker compose -f "$COMPOSE_FILE" exec backend bash -c \
        "cat /home/frappe/frappe-bench/sites/$SITE_NAME/apps.txt 2>/dev/null || echo ''")

    if [[ -n "$APPS_IN_BACKUP" ]]; then
        print_info "Apps from backup: $APPS_IN_BACKUP"

        # Note: Apps should already be in the Docker image
        # This is just a check - actual app installation would require the apps to be available
        print_info "Ensure these apps are available in your Docker image"
    fi
}

# Run migration
run_migration() {
    if [[ "$SKIP_MIGRATION" == false ]]; then
        print_info "Running bench migrate (this may take a while)..."

        docker compose -f "$COMPOSE_FILE" exec backend bash -c \
            "cd /home/frappe/frappe-bench && bench --site $SITE_NAME migrate" || {
            print_error "Migration failed"
            exit 1
        }

        print_success "Migration completed"
    else
        print_warning "Skipping migration as requested"
    fi
}

# Clear cache
clear_cache() {
    print_info "Clearing site cache..."

    docker compose -f "$COMPOSE_FILE" exec backend bash -c \
        "cd /home/frappe/frappe-bench && bench --site $SITE_NAME clear-cache" || {
        print_warning "Failed to clear cache"
    }

    print_success "Cache cleared"
}

# Restart services
restart_services() {
    print_info "Restarting backend services..."

    docker compose -f "$COMPOSE_FILE" restart backend frontend websocket scheduler queue-short queue-long || {
        print_warning "Failed to restart some services"
    }

    print_success "Services restarted"
}

# Configure host_name for PDF generation
configure_hostname() {
    print_info "Checking host_name configuration for PDF generation..."

    # Check if host_name is already set
    HOST_NAME=$(docker compose -f "$COMPOSE_FILE" exec backend bash -c \
        "cd /home/frappe/frappe-bench && bench --site $SITE_NAME get-config host_name 2>/dev/null || echo ''")

    if [[ -z "$HOST_NAME" ]]; then
        print_warning "host_name not configured. PDF generation may not work."
        print_warning "Configure it with:"
        print_warning "  docker compose -f $COMPOSE_FILE exec backend bash -c \\"
        print_warning "    \"cd /home/frappe/frappe-bench && bench --site $SITE_NAME set-config host_name https://erp.mydomain.com\""
    else
        print_success "host_name is configured: $HOST_NAME"
    fi
}

# Main execution
main() {
    echo "=========================================="
    echo "  ERPNext/Frappe Backup Restoration"
    echo "=========================================="
    echo

    parse_args "$@"
    validate_files
    load_env
    check_services

    echo
    echo "Restoration Parameters:"
    echo "  Site Name: $SITE_NAME"
    echo "  Database Backup: $BACKUP_DB_PATH"
    echo "  Public Files: $BACKUP_PUBLIC_PATH"
    echo "  Private Files: $BACKUP_PRIVATE_PATH"
    echo "  Site Config: ${BACKUP_SITE_CONFIG_PATH:-Not provided}"
    echo "  Compose File: $COMPOSE_FILE"
    echo "  Create New Site: $CREATE_NEW_SITE"
    echo "  Strip Components: $STRIP_COMPONENTS"
    echo

    read -p "Continue with restoration? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Restoration cancelled"
        exit 0
    fi

    echo
    print_info "Starting restoration process..."
    echo

    # Execute restoration steps
    create_site
    get_db_name
    drop_and_create_db
    restore_database
    restore_files
    restore_encryption_key
    install_apps
    run_migration
    clear_cache
    restart_services
    configure_hostname

    echo
    echo "=========================================="
    print_success "Restoration completed successfully!"
    echo "=========================================="
    echo
    print_info "Your restored site is available at:"
    print_info "  http://localhost:${HTTP_PUBLISH_PORT:-8080}"
    echo
    print_info "Site name: $SITE_NAME"
    print_info "Admin credentials: Use the credentials from your backup"
    echo
}

# Run main function
main "$@"
