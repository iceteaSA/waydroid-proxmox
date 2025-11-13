#!/usr/bin/env bash

# Waydroid Backup and Restore Script
# Allows backing up and restoring Waydroid data, apps, and configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/helper-functions.sh" ]; then
    source "${SCRIPT_DIR}/helper-functions.sh"
else
    msg_info() { echo "[INFO] $1"; }
    msg_ok() { echo "[OK] $1"; }
    msg_error() { echo "[ERROR] $1"; }
    msg_warn() { echo "[WARN] $1"; }
    GN="\033[1;92m"
    RD="\033[01;31m"
    YW="\033[1;93m"
    BL="\033[36m"
    CL="\033[m"
fi

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/var/backups/waydroid}"
WAYDROID_DATA="/var/lib/waydroid"
WAYDROID_CONFIG="/root/.config/waydroid"
MAX_BACKUPS="${MAX_BACKUPS:-5}"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Validate tar archive contents to prevent tar bombs and path traversal
validate_tar_archive() {
    local archive_file="$1"
    local expected_base_dir="${2:-}"

    # Check if archive contains absolute paths or parent directory references
    if tar -tzf "$archive_file" 2>/dev/null | grep -qE '(^/|^\.\./|/\.\./|\.\.$)'; then
        msg_error "Archive contains dangerous paths (absolute or parent directory references)"
        return 1
    fi

    # If expected base directory is specified, verify all paths start with it
    if [ -n "$expected_base_dir" ]; then
        if tar -tzf "$archive_file" 2>/dev/null | grep -v "^${expected_base_dir}/" | grep -q .; then
            msg_error "Archive contains files outside expected directory: $expected_base_dir"
            return 1
        fi
    fi

    # Check for suspicious file names
    if tar -tzf "$archive_file" 2>/dev/null | grep -qE '(\$|\||;|&|`|\(|\)|<|>|\{|\})'; then
        msg_error "Archive contains files with suspicious characters"
        return 1
    fi

    return 0
}

show_help() {
    cat << EOF
${GN}Waydroid Backup and Restore Tool${CL}

Usage: $0 <command> [options]

Commands:
    backup              Create a new backup
    restore <backup>    Restore from a backup
    list                List all available backups
    clean               Remove old backups (keep last $MAX_BACKUPS)
    export <backup>     Export backup to tar.gz for external storage
    import <file>       Import backup from tar.gz file

Options:
    --full              Backup everything including images (larger)
    --data-only         Backup only user data and apps (default)
    --help              Show this help message

Examples:
    $0 backup --full
    $0 list
    $0 restore waydroid-backup-20250112-143000
    $0 export waydroid-backup-20250112-143000

Backup Location: $BACKUP_DIR
EOF
}

create_backup() {
    local backup_type="${1:-data-only}"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="waydroid-backup-${timestamp}"
    local backup_path="$BACKUP_DIR/$backup_name"

    msg_info "Creating backup: $backup_name"

    # Check if Waydroid is running
    if pgrep -f "^(/usr/bin/python3 )?/usr/bin/waydroid (container|session)" > /dev/null; then
        msg_warn "Waydroid is currently running. Stopping for backup..."
        systemctl stop waydroid-vnc.service 2>/dev/null || true
        waydroid session stop 2>/dev/null || true
        sleep 3
        RESTART_AFTER=true
    else
        RESTART_AFTER=false
    fi

    mkdir -p "$backup_path"

    # Create backup manifest
    cat > "$backup_path/manifest.json" <<EOF
{
    "backup_name": "$backup_name",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "type": "$backup_type",
    "hostname": "$(hostname)",
    "waydroid_version": "$(waydroid --version 2>/dev/null || echo 'unknown')"
}
EOF

    # Backup configuration files
    msg_info "Backing up configuration..."
    if [ -d "$WAYDROID_CONFIG" ]; then
        cp -a "$WAYDROID_CONFIG" "$backup_path/config"
    fi

    if [ -f /etc/wayvnc/config ]; then
        mkdir -p "$backup_path/wayvnc"
        cp -a /etc/wayvnc "$backup_path/wayvnc/"
    fi

    if [ -f /root/vnc-password.txt ]; then
        cp /root/vnc-password.txt "$backup_path/"
    fi

    # Backup Waydroid data
    msg_info "Backing up Waydroid data..."
    if [ -f "$WAYDROID_DATA/waydroid.cfg" ]; then
        cp "$WAYDROID_DATA/waydroid.cfg" "$backup_path/"
    fi

    if [ -d "$WAYDROID_DATA/data" ]; then
        msg_info "Backing up user data and apps..."
        tar -czf "$backup_path/userdata.tar.gz" -C "$WAYDROID_DATA" data 2>/dev/null || true
    fi

    # Backup images only if full backup
    if [ "$backup_type" = "full" ]; then
        msg_info "Backing up system images (this may take a while)..."
        if [ -d "$WAYDROID_DATA/images" ]; then
            tar -czf "$backup_path/images.tar.gz" -C "$WAYDROID_DATA" images 2>/dev/null || true
        fi
    fi

    # Calculate backup size
    backup_size=$(du -sh "$backup_path" | cut -f1)
    echo "$backup_size" > "$backup_path/size.txt"

    msg_ok "Backup created successfully: $backup_name"
    echo -e "  Location: $backup_path"
    echo -e "  Size: $backup_size"

    # Restart Waydroid if it was running
    if [ "$RESTART_AFTER" = true ]; then
        msg_info "Restarting Waydroid..."
        systemctl start waydroid-vnc.service
    fi

    # Clean old backups
    clean_old_backups
}

list_backups() {
    echo -e "${GN}Available Backups:${CL}\n"

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo "No backups found in $BACKUP_DIR"
        return
    fi

    printf "%-35s %-15s %-15s %s\n" "Backup Name" "Date" "Size" "Type"
    echo "────────────────────────────────────────────────────────────────────────────"

    for backup in "$BACKUP_DIR"/waydroid-backup-*; do
        if [ -d "$backup" ]; then
            backup_name=$(basename "$backup")
            if [ -f "$backup/manifest.json" ]; then
                backup_date=$(grep timestamp "$backup/manifest.json" | cut -d'"' -f4 | cut -d'T' -f1)
                backup_type=$(grep '"type"' "$backup/manifest.json" | cut -d'"' -f4)
            else
                backup_date="unknown"
                backup_type="unknown"
            fi

            if [ -f "$backup/size.txt" ]; then
                backup_size=$(cat "$backup/size.txt")
            else
                backup_size=$(du -sh "$backup" 2>/dev/null | cut -f1)
            fi

            printf "%-35s %-15s %-15s %s\n" "$backup_name" "$backup_date" "$backup_size" "$backup_type"
        fi
    done
    echo ""
}

restore_backup() {
    local backup_name="$1"

    if [ -z "$backup_name" ]; then
        msg_error "Backup name required"
        echo "Usage: $0 restore <backup-name>"
        echo "Run '$0 list' to see available backups"
        exit 1
    fi

    # Validate backup name to prevent path traversal attacks
    if [[ "$backup_name" =~ (\.\./|^/|^\.|[[:space:]]|\$|[|;]|&|[\`]|[()]|[<>]|[{}]|[\[\]]) ]]; then
        msg_error "Invalid backup name: contains dangerous characters or path traversal patterns"
        exit 1
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    if [ ! -d "$backup_path" ]; then
        msg_error "Backup not found: $backup_name"
        exit 1
    fi

    echo -e "${YW}WARNING: This will overwrite current Waydroid data!${CL}"
    read -p "Are you sure you want to restore? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        msg_info "Restore cancelled"
        exit 0
    fi

    msg_info "Restoring from backup: $backup_name"

    # Stop Waydroid
    msg_info "Stopping Waydroid..."
    systemctl stop waydroid-vnc.service 2>/dev/null || true
    systemctl stop waydroid-api.service 2>/dev/null || true
    waydroid session stop 2>/dev/null || true
    waydroid container stop 2>/dev/null || true
    sleep 3

    # Restore configuration
    msg_info "Restoring configuration..."
    if [ -d "$backup_path/config" ]; then
        rm -rf "$WAYDROID_CONFIG"
        cp -a "$backup_path/config" "$WAYDROID_CONFIG"
    fi

    if [ -d "$backup_path/wayvnc/wayvnc" ]; then
        mkdir -p /etc/wayvnc
        cp -a "$backup_path/wayvnc/wayvnc/"* /etc/wayvnc/
        chmod 644 /etc/wayvnc/config
        chmod 600 /etc/wayvnc/password 2>/dev/null || true
    fi

    if [ -f "$backup_path/vnc-password.txt" ]; then
        cp "$backup_path/vnc-password.txt" /root/
    fi

    # Restore Waydroid config
    if [ -f "$backup_path/waydroid.cfg" ]; then
        cp "$backup_path/waydroid.cfg" "$WAYDROID_DATA/"
    fi

    # Restore user data
    if [ -f "$backup_path/userdata.tar.gz" ]; then
        msg_info "Restoring user data and apps..."
        if ! validate_tar_archive "$backup_path/userdata.tar.gz" "data"; then
            msg_error "Validation failed for userdata archive"
            exit 1
        fi
        tar --no-absolute-names -xzf "$backup_path/userdata.tar.gz" -C "$WAYDROID_DATA"
    fi

    # Restore images if available
    if [ -f "$backup_path/images.tar.gz" ]; then
        msg_info "Restoring system images..."
        if ! validate_tar_archive "$backup_path/images.tar.gz" "images"; then
            msg_error "Validation failed for images archive"
            exit 1
        fi
        tar --no-absolute-names -xzf "$backup_path/images.tar.gz" -C "$WAYDROID_DATA"
    fi

    msg_ok "Restore completed successfully"

    # Restart services
    msg_info "Restarting services..."
    systemctl start waydroid-vnc.service
    systemctl start waydroid-api.service

    echo -e "\n${GN}Restore Complete!${CL}"
    echo "Waydroid has been restored from: $backup_name"
}

clean_old_backups() {
    local backup_count=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "waydroid-backup-*" | wc -l)

    if [ "$backup_count" -gt "$MAX_BACKUPS" ]; then
        msg_info "Cleaning old backups (keeping last $MAX_BACKUPS)..."
        find "$BACKUP_DIR" -maxdepth 1 -type d -name "waydroid-backup-*" -printf '%T@ %p\n' | \
            sort -n | head -n -"$MAX_BACKUPS" | cut -d' ' -f2- | \
            while read -r old_backup; do
                msg_info "Removing old backup: $(basename "$old_backup")"
                rm -rf "$old_backup"
            done
        msg_ok "Cleanup complete"
    fi
}

export_backup() {
    local backup_name="$1"

    # Validate backup name to prevent path traversal attacks
    if [[ "$backup_name" =~ (\.\./|^/|^\.|[[:space:]]|\$|[|;]|&|[\`]|[()]|[<>]|[{}]|[\[\]]) ]]; then
        msg_error "Invalid backup name: contains dangerous characters or path traversal patterns"
        exit 1
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    if [ ! -d "$backup_path" ]; then
        msg_error "Backup not found: $backup_name"
        exit 1
    fi

    local export_file="/tmp/${backup_name}.tar.gz"
    msg_info "Exporting backup to: $export_file"

    tar -czf "$export_file" -C "$BACKUP_DIR" "$backup_name"

    msg_ok "Backup exported successfully"
    echo "  File: $export_file"
    echo "  Size: $(du -sh "$export_file" | cut -f1)"
}

import_backup() {
    local import_file="$1"

    if [ ! -f "$import_file" ]; then
        msg_error "File not found: $import_file"
        exit 1
    fi

    msg_info "Importing backup from: $import_file"

    # Validate the archive before extraction
    if ! validate_tar_archive "$import_file" "waydroid-backup-"; then
        msg_error "Validation failed for import archive"
        exit 1
    fi

    tar --no-absolute-names -xzf "$import_file" -C "$BACKUP_DIR"

    msg_ok "Backup imported successfully"
    list_backups
}

# Main script logic
case "${1:-}" in
    backup)
        if [ "${2:-}" = "--full" ]; then
            create_backup "full"
        else
            create_backup "data-only"
        fi
        ;;
    restore)
        restore_backup "$2"
        ;;
    list)
        list_backups
        ;;
    clean)
        clean_old_backups
        ;;
    export)
        export_backup "$2"
        ;;
    import)
        import_backup "$2"
        ;;
    --help|-h|help)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
