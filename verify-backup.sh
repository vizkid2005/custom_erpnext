#!/bin/bash

#
# Backup Verification Script
#
# Validates backup files before restoration to catch common issues early
#

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BACKUP_DB_PATH=""
BACKUP_PUBLIC_PATH=""
BACKUP_PRIVATE_PATH=""
BACKUP_SITE_CONFIG_PATH=""
COMPOSE_FILE="compose.custom.yaml"

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Verify ERPNext/Frappe backup files before restoration.

Options:
    -d, --database PATH         Path to database SQL backup file
    -p, --public PATH           Path to public files tar archive
    -r, --private PATH          Path to private files tar archive
    -c, --config PATH           Path to site_config.json (optional but recommended)
    -f, --compose-file PATH     Path to docker compose file (default: compose.custom.yaml)
    -h, --help                  Display this help message

Example:
    $0 -d /backups/db.sql -p /backups/public.tar -r /backups/private.tar -c /backups/site_config.json

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--database) BACKUP_DB_PATH="$2"; shift 2 ;;
            -p|--public) BACKUP_PUBLIC_PATH="$2"; shift 2 ;;
            -r|--private) BACKUP_PRIVATE_PATH="$2"; shift 2 ;;
            -c|--config) BACKUP_SITE_CONFIG_PATH="$2"; shift 2 ;;
            -f|--compose-file) COMPOSE_FILE="$2"; shift 2 ;;
            -h|--help) print_usage; exit 0 ;;
            *) print_error "Unknown option: $1"; print_usage; exit 1 ;;
        esac
    done

    if [[ -z "$BACKUP_DB_PATH" || -z "$BACKUP_PUBLIC_PATH" || -z "$BACKUP_PRIVATE_PATH" ]]; then
        print_error "Missing required arguments"
        print_usage
        exit 1
    fi
}

check_file_exists() {
    local file="$1"
    local name="$2"

    if [[ ! -f "$file" ]]; then
        print_error "$name not found: $file"
        return 1
    fi

    print_success "$name exists"
    return 0
}

get_file_size() {
    local file="$1"
    du -h "$file" | cut -f1
}

check_database_file() {
    print_info "Checking database backup..."

    if ! check_file_exists "$BACKUP_DB_PATH" "Database backup"; then
        return 1
    fi

    local size=$(get_file_size "$BACKUP_DB_PATH")
    echo "    Size: $size"

    # Check if it's a valid SQL file
    if head -n 20 "$BACKUP_DB_PATH" | grep -q "MySQL\|MariaDB\|CREATE\|INSERT"; then
        print_success "Database backup appears to be valid SQL"
    else
        print_warning "Database file may not be a valid SQL dump"
        echo "    First 5 lines:"
        head -n 5 "$BACKUP_DB_PATH" | sed 's/^/    /'
    fi

    # Check for common tables
    if grep -q "tabDocType\|tabUser\|tabSingles" "$BACKUP_DB_PATH"; then
        print_success "Frappe/ERPNext database tables detected"
    else
        print_warning "Frappe/ERPNext tables not detected - is this the correct backup?"
    fi

    echo
}

check_tar_file() {
    local file="$1"
    local name="$2"

    print_info "Checking $name..."

    if ! check_file_exists "$file" "$name"; then
        return 1
    fi

    local size=$(get_file_size "$file")
    echo "    Size: $size"

    # Check if it's a valid tar file
    if tar -tzf "$file" >/dev/null 2>&1 || tar -tf "$file" >/dev/null 2>&1; then
        print_success "$name is a valid tar archive"

        # Show structure
        echo "    Archive structure (first 10 entries):"
        tar -tf "$file" 2>/dev/null | head -n 10 | sed 's/^/      /'

        # Count directory levels
        local first_file=$(tar -tf "$file" 2>/dev/null | grep -v '/$' | head -n 1)
        if [[ -n "$first_file" ]]; then
            local levels=$(echo "$first_file" | tr -cd '/' | wc -c)
            echo "    Detected path depth: $levels levels"
            echo "    Suggested --strip-components: $((levels))"
        fi

        # Count total files
        local file_count=$(tar -tf "$file" 2>/dev/null | grep -v '/$' | wc -l)
        echo "    Total files: $file_count"

    else
        print_error "$name is not a valid tar archive"
        return 1
    fi

    echo
}

check_site_config() {
    if [[ -z "$BACKUP_SITE_CONFIG_PATH" ]]; then
        print_warning "site_config.json not provided"
        echo "    IMPORTANT: Without site_config.json, the encryption_key cannot be restored"
        echo "    Encrypted data (passwords, API keys) will be inaccessible"
        echo "    Provide with: -c /path/to/site_config.json"
        echo
        return 1
    fi

    print_info "Checking site_config.json..."

    if ! check_file_exists "$BACKUP_SITE_CONFIG_PATH" "site_config.json"; then
        return 1
    fi

    # Validate JSON
    if python3 -m json.tool "$BACKUP_SITE_CONFIG_PATH" >/dev/null 2>&1; then
        print_success "site_config.json is valid JSON"
    else
        print_error "site_config.json is not valid JSON"
        return 1
    fi

    # Check for critical keys
    local has_encryption_key=false
    local has_db_name=false
    local has_db_password=false

    if grep -q '"encryption_key"' "$BACKUP_SITE_CONFIG_PATH"; then
        print_success "encryption_key found"
        has_encryption_key=true
    else
        print_error "encryption_key NOT found - encrypted data will be inaccessible!"
    fi

    if grep -q '"db_name"' "$BACKUP_SITE_CONFIG_PATH"; then
        print_success "db_name found"
        has_db_name=true
        local db_name=$(grep '"db_name"' "$BACKUP_SITE_CONFIG_PATH" | cut -d'"' -f4)
        echo "    Database name: $db_name"
    else
        print_warning "db_name not found"
    fi

    if grep -q '"db_password"' "$BACKUP_SITE_CONFIG_PATH"; then
        print_success "db_password found"
        has_db_password=true
    else
        print_warning "db_password not found"
    fi

    echo

    if [[ "$has_encryption_key" == false ]]; then
        return 1
    fi
}

check_docker_services() {
    print_info "Checking Docker services..."

    if [[ ! -f "$COMPOSE_FILE" ]]; then
        print_warning "Compose file not found: $COMPOSE_FILE"
        echo "    Services check skipped"
        echo
        return 0
    fi

    if ! docker compose -f "$COMPOSE_FILE" ps >/dev/null 2>&1; then
        print_warning "Cannot check Docker services"
        echo
        return 0
    fi

    # Check if any core services are running
    local running_services=$(docker compose -f "$COMPOSE_FILE" ps --format "table {{.Service}}\t{{.State}}" 2>/dev/null | grep -c "running" || echo "0")

    if [[ $running_services -gt 0 ]]; then
        print_success "Docker services are running"

        # Check specific services
        local services=("backend" "db" "frontend" "websocket")
        for service in "${services[@]}"; do
            if docker compose -f "$COMPOSE_FILE" ps "$service" 2>/dev/null | grep -q "running\|Up"; then
                echo "    ✓ $service is running"
            else
                echo "    ✗ $service is not running"
            fi
        done
    else
        print_warning "Docker services are not running"
        echo "    Start with: docker compose -f $COMPOSE_FILE up -d"
    fi

    echo
}

check_disk_space() {
    print_info "Checking disk space..."

    # Initialize variables with defaults
    local db_size=0
    local public_size=0
    local private_size=0
    local available_space=0

    # Get file sizes with proper error handling
    if [[ -f "$BACKUP_DB_PATH" ]]; then
        db_size=$(stat -f "%z" "$BACKUP_DB_PATH" 2>/dev/null || stat -c "%s" "$BACKUP_DB_PATH" 2>/dev/null || echo "0")
    fi

    if [[ -f "$BACKUP_PUBLIC_PATH" ]]; then
        public_size=$(stat -f "%z" "$BACKUP_PUBLIC_PATH" 2>/dev/null || stat -c "%s" "$BACKUP_PUBLIC_PATH" 2>/dev/null || echo "0")
    fi

    if [[ -f "$BACKUP_PRIVATE_PATH" ]]; then
        private_size=$(stat -f "%z" "$BACKUP_PRIVATE_PATH" 2>/dev/null || stat -c "%s" "$BACKUP_PRIVATE_PATH" 2>/dev/null || echo "0")
    fi

    local total_size=$((db_size + public_size + private_size))
    local required_space=$((total_size * 3))  # 3x for safety

    # Get available disk space with error handling
    local df_output=$(df . 2>/dev/null | tail -1 | awk '{print $4}')
    if [[ -n "$df_output" && "$df_output" =~ ^[0-9]+$ ]]; then
        available_space=$((df_output * 1024))  # Convert to bytes
    fi

    echo "    Total backup size: $(numfmt --to=iec $total_size 2>/dev/null || echo "$total_size bytes")"
    echo "    Recommended free space: $(numfmt --to=iec $required_space 2>/dev/null || echo "$required_space bytes")"
    echo "    Available space: $(numfmt --to=iec $available_space 2>/dev/null || echo "$available_space bytes")"

    if [[ $available_space -gt $required_space ]]; then
        print_success "Sufficient disk space available"
    else
        print_error "Insufficient disk space - restoration may fail"
    fi

    echo
}

generate_restore_command() {
    print_info "Suggested restore command:"
    echo

    local cmd="./restore-backup.sh \\"
    cmd="$cmd\n  -d \"$BACKUP_DB_PATH\" \\"
    cmd="$cmd\n  -p \"$BACKUP_PUBLIC_PATH\" \\"
    cmd="$cmd\n  -r \"$BACKUP_PRIVATE_PATH\" \\"
    cmd="$cmd\n  -s localhost"

    if [[ -n "$BACKUP_SITE_CONFIG_PATH" ]]; then
        cmd="$cmd \\\n  -c \"$BACKUP_SITE_CONFIG_PATH\""
    fi

    if [[ "$COMPOSE_FILE" != "compose.custom.yaml" ]]; then
        cmd="$cmd \\\n  -f \"$COMPOSE_FILE\""
    fi

    # Check if we should suggest --strip-components
    if [[ -f "$BACKUP_PUBLIC_PATH" ]]; then
        local first_file=$(tar -tf "$BACKUP_PUBLIC_PATH" 2>/dev/null | grep -v '/$' | head -n 1)
        if [[ -n "$first_file" ]]; then
            local levels=$(echo "$first_file" | tr -cd '/' | wc -c)
            if [[ $levels -ne 6 ]]; then
                cmd="$cmd \\\n  --strip-components=$levels"
            fi
        fi
    fi

    echo -e "    $cmd"
    echo
}

main() {
    echo "=========================================="
    echo "  Backup Verification Tool"
    echo "=========================================="
    echo

    parse_args "$@"

    local errors=0

    check_database_file || ((errors++))
    check_tar_file "$BACKUP_PUBLIC_PATH" "Public files archive" || ((errors++))
    check_tar_file "$BACKUP_PRIVATE_PATH" "Private files archive" || ((errors++))
    check_site_config || ((errors++))
    check_docker_services
    check_disk_space

    echo "=========================================="

    if [[ $errors -eq 0 ]]; then
        print_success "All checks passed!"
        echo
        generate_restore_command
        print_info "You can now run the restore command above"
    else
        print_error "Found $errors issue(s) - please fix before restoring"
        echo

        if [[ -z "$BACKUP_SITE_CONFIG_PATH" ]]; then
            print_warning "CRITICAL: No site_config.json provided!"
            echo "    Without it, encrypted data cannot be restored"
        fi
    fi

    echo "=========================================="
}

main "$@"
