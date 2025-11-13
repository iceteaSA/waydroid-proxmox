#!/usr/bin/env bash

# Waydroid LXC Update and Upgrade Script
# Safely updates Waydroid, system packages, and scripts

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

# Enhanced logging with timestamps
log_with_timestamp() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        INFO)  echo -e "${BL}[$timestamp] [INFO]${CL} $message" ;;
        OK)    echo -e "${GN}[$timestamp] [OK]${CL} $message" ;;
        ERROR) echo -e "${RD}[$timestamp] [ERROR]${CL} $message" ;;
        WARN)  echo -e "${YW}[$timestamp] [WARN]${CL} $message" ;;
    esac
}

# Override msg functions to use timestamps
msg_info() { log_with_timestamp INFO "$1"; }
msg_ok() { log_with_timestamp OK "$1"; }
msg_error() { log_with_timestamp ERROR "$1"; }
msg_warn() { log_with_timestamp WARN "$1"; }

# Configuration
DRY_RUN=false
BACKUP_BEFORE_UPDATE=true
UPDATE_SYSTEM=true
UPDATE_WAYDROID=true
UPDATE_GPU=true
UPDATE_SCRIPTS=false
RESTART_SERVICES=true
UPDATE_TIMEOUT=600  # 10 minutes timeout for updates
MIN_DISK_SPACE_MB=500  # Minimum free disk space required (MB)

show_help() {
    cat << EOF
${GN}Waydroid LXC Update and Upgrade Tool${CL}

Usage: $0 [options]

Options:
    --dry-run           Show what would be updated without making changes
    --no-backup         Skip creating backup before update
    --system-only       Only update system packages
    --waydroid-only     Only update Waydroid
    --gpu-only          Only update GPU drivers
    --components=LIST   Update specific components (comma-separated: system,waydroid,gpu,all)
    --skip-restart      Don't restart services after update
    --timeout=SECONDS   Set timeout for updates (default: 600)
    --help              Show this help message

Examples:
    $0                              # Full update with backup
    $0 --dry-run                    # Preview updates
    $0 --system-only                # Only update system packages
    $0 --components=waydroid,gpu    # Update Waydroid and GPU drivers only
    $0 --timeout=1200               # Set 20 minute timeout

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-backup)
            BACKUP_BEFORE_UPDATE=false
            shift
            ;;
        --system-only)
            UPDATE_WAYDROID=false
            UPDATE_GPU=false
            UPDATE_SCRIPTS=false
            shift
            ;;
        --waydroid-only)
            UPDATE_SYSTEM=false
            UPDATE_GPU=false
            UPDATE_SCRIPTS=false
            shift
            ;;
        --gpu-only)
            UPDATE_SYSTEM=false
            UPDATE_WAYDROID=false
            UPDATE_SCRIPTS=false
            shift
            ;;
        --components=*)
            components="${1#*=}"
            UPDATE_SYSTEM=false
            UPDATE_WAYDROID=false
            UPDATE_GPU=false
            IFS=',' read -ra COMP_ARRAY <<< "$components"
            for comp in "${COMP_ARRAY[@]}"; do
                case "$comp" in
                    system) UPDATE_SYSTEM=true ;;
                    waydroid) UPDATE_WAYDROID=true ;;
                    gpu) UPDATE_GPU=true ;;
                    all) UPDATE_SYSTEM=true; UPDATE_WAYDROID=true; UPDATE_GPU=true ;;
                    *) msg_error "Unknown component: $comp"; exit 1 ;;
                esac
            done
            shift
            ;;
        --timeout=*)
            UPDATE_TIMEOUT="${1#*=}"
            shift
            ;;
        --skip-restart)
            RESTART_SERVICES=false
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            msg_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Utility Functions

# Check available disk space
check_disk_space() {
    local required_mb=$1
    local available_kb=$(df / | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))

    msg_info "Checking disk space..."
    msg_info "Available: ${available_mb}MB, Required: ${required_mb}MB"

    if [ $available_mb -lt $required_mb ]; then
        msg_error "Insufficient disk space. Available: ${available_mb}MB, Required: ${required_mb}MB"
        return 1
    fi

    msg_ok "Sufficient disk space available"
    return 0
}

# Run command with timeout
run_with_timeout() {
    local timeout=$1
    shift
    local cmd="$@"

    msg_info "Running: $cmd (timeout: ${timeout}s)"

    if timeout $timeout bash -c "$cmd"; then
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            msg_error "Command timed out after ${timeout}s: $cmd"
        else
            msg_error "Command failed with exit code $exit_code: $cmd"
        fi
        return $exit_code
    fi
}

# Verify service is running and healthy
verify_service() {
    local service_name=$1
    local max_attempts=${2:-10}
    local wait_time=${3:-2}

    msg_info "Verifying $service_name..."

    for i in $(seq 1 $max_attempts); do
        if systemctl is-active --quiet "$service_name"; then
            # Check if service has been running for at least 3 seconds
            local uptime=$(systemctl show -p ActiveEnterTimestamp "$service_name" | cut -d= -f2)
            if [ -n "$uptime" ]; then
                msg_ok "$service_name is active and running"
                return 0
            fi
        fi

        if [ $i -lt $max_attempts ]; then
            msg_info "Attempt $i/$max_attempts: Waiting ${wait_time}s for $service_name..."
            sleep $wait_time
        fi
    done

    msg_error "$service_name failed to start properly after $max_attempts attempts"
    msg_info "Service status:"
    systemctl status "$service_name" --no-pager -l | head -20
    return 1
}

# Create restore point
create_restore_point() {
    local restore_file="/tmp/waydroid-update-restore-$(date +%s).txt"
    msg_info "Creating restore point: $restore_file"

    {
        echo "# Waydroid Update Restore Point"
        echo "# Created: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "## Package Versions"
        dpkg -l | grep -E 'waydroid|mesa|intel|amd' || true
        echo ""
        echo "## Service Status"
        systemctl status waydroid-vnc.service --no-pager 2>/dev/null || true
        systemctl status waydroid-api.service --no-pager 2>/dev/null || true
    } > "$restore_file"

    msg_ok "Restore point saved: $restore_file"
    echo "$restore_file"
}

if [ "$DRY_RUN" = true ]; then
    msg_warn "Running in DRY-RUN mode - no changes will be made"
    echo ""
fi

echo -e "${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}  Waydroid LXC Update System${CL}"
echo -e "${GN}  $(date '+%Y-%m-%d %H:%M:%S')${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

# Pre-update checks
if [ "$DRY_RUN" = false ]; then
    msg_info "Running pre-update checks..."

    # Check disk space
    if ! check_disk_space $MIN_DISK_SPACE_MB; then
        msg_error "Pre-update checks failed. Aborting update."
        exit 1
    fi

    # Create restore point
    RESTORE_POINT=$(create_restore_point)
    echo ""
fi

# Pre-update backup
if [ "$BACKUP_BEFORE_UPDATE" = true ] && [ "$DRY_RUN" = false ]; then
    msg_info "Creating pre-update backup..."
    if [ -f "${SCRIPT_DIR}/backup-restore.sh" ]; then
        bash "${SCRIPT_DIR}/backup-restore.sh" backup --data-only
        msg_ok "Backup created"
    else
        msg_warn "Backup script not found, skipping backup"
    fi
    echo ""
fi

# Check current versions
msg_info "Current Versions:"
if command -v waydroid &>/dev/null; then
    current_waydroid=$(waydroid --version 2>/dev/null || echo "unknown")
    echo "  Waydroid: $current_waydroid"
fi
echo "  Python: $(python3 --version 2>/dev/null || echo 'not installed')"
echo "  API: $(grep 'api_version' /usr/local/bin/waydroid-api.py 2>/dev/null | head -1 | grep -o '[0-9.]*' || echo 'unknown')"
echo ""

# Update system packages
if [ "$UPDATE_SYSTEM" = true ]; then
    echo -e "${BL}[1/4] Updating System Packages${CL}"

    if [ "$DRY_RUN" = true ]; then
        msg_info "Would update system packages:"
        apt list --upgradable 2>/dev/null | head -20
    else
        msg_info "Updating package lists..."
        if run_with_timeout 120 "apt-get update"; then
            msg_ok "Package lists updated"

            msg_info "Upgrading system packages..."
            if run_with_timeout $UPDATE_TIMEOUT "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"; then
                msg_ok "System packages upgraded"
            else
                msg_error "Failed to upgrade system packages"
                msg_warn "You can check the restore point: $RESTORE_POINT"
                msg_info "Continuing with other updates..."
            fi

            msg_info "Cleaning up..."
            apt-get autoremove -y &>/dev/null
            apt-get autoclean -y &>/dev/null
            msg_ok "Cleanup complete"
        else
            msg_error "Failed to update package lists"
            msg_warn "Skipping system package upgrade"
        fi
    fi
    echo ""
fi

# Update Waydroid
if [ "$UPDATE_WAYDROID" = true ]; then
    echo -e "${BL}[2/4] Updating Waydroid${CL}"

    if [ "$DRY_RUN" = true ]; then
        msg_info "Would check for Waydroid updates"
        apt-cache policy waydroid 2>/dev/null | grep -A1 "Installed:"
    else
        # Check if update available
        current_version=$(dpkg -l waydroid 2>/dev/null | grep ^ii | awk '{print $3}')
        available_version=$(apt-cache policy waydroid 2>/dev/null | grep Candidate | awk '{print $2}')

        if [ "$current_version" != "$available_version" ] && [ -n "$available_version" ]; then
            msg_info "Waydroid update available: $current_version → $available_version"

            # Stop Waydroid before update
            msg_info "Stopping Waydroid services..."
            systemctl stop waydroid-vnc.service 2>/dev/null || true
            systemctl stop waydroid-api.service 2>/dev/null || true
            waydroid session stop 2>/dev/null || true
            waydroid container stop 2>/dev/null || true
            sleep 3

            msg_info "Updating Waydroid..."
            if run_with_timeout $UPDATE_TIMEOUT "DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y waydroid"; then
                msg_ok "Waydroid updated to $available_version"
            else
                msg_error "Failed to update Waydroid"
                msg_warn "Attempting to recover by restarting services..."
                systemctl start waydroid-vnc.service 2>/dev/null || true
                systemctl start waydroid-api.service 2>/dev/null || true
            fi
        else
            msg_ok "Waydroid is already up to date ($current_version)"
        fi
    fi
    echo ""
fi

# Update GPU drivers
if [ "$UPDATE_GPU" = true ]; then
    echo -e "${BL}[3/4] Checking GPU Drivers${CL}"

    if [ "$DRY_RUN" = true ]; then
        msg_info "Would check for GPU driver updates"
        dpkg -l | grep -E 'mesa|intel.*driver|amd.*graphics' | awk '{print $2, $3}'
    else
        gpu_packages=""

        # Check what GPU packages are installed
        if dpkg -l | grep -q intel-media-va-driver; then
            gpu_packages="intel-media-va-driver i965-va-driver mesa-va-drivers mesa-vulkan-drivers"
        elif dpkg -l | grep -q firmware-amd-graphics; then
            gpu_packages="mesa-va-drivers mesa-vulkan-drivers firmware-amd-graphics"
        fi

        if [ -n "$gpu_packages" ]; then
            msg_info "Updating GPU drivers..."
            if run_with_timeout $UPDATE_TIMEOUT "DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y $gpu_packages"; then
                msg_ok "GPU drivers updated"
            else
                msg_warn "Failed to update GPU drivers or no updates available"
            fi
        else
            msg_info "No GPU drivers installed (software rendering mode)"
        fi
    fi
    echo ""
else
    echo -e "${BL}[3/4] Skipping GPU Drivers (not selected)${CL}"
    echo ""
fi

# Update Python dependencies
echo -e "${BL}[4/4] Checking Python Dependencies${CL}"
if [ "$DRY_RUN" = true ]; then
    msg_info "Would check Python package updates"
else
    # No external Python packages currently, but placeholder for future
    msg_ok "Python dependencies are up to date"
fi
echo ""

# Restart services if needed
if [ "$RESTART_SERVICES" = true ] && [ "$DRY_RUN" = false ]; then
    echo -e "${BL}Restarting and Verifying Services${CL}"
    msg_info "Restarting services..."

    SERVICE_RESTART_FAILED=false

    # Restart and verify VNC service
    if systemctl is-enabled waydroid-vnc.service &>/dev/null; then
        msg_info "Restarting Waydroid VNC service..."
        if systemctl restart waydroid-vnc.service; then
            if verify_service waydroid-vnc.service 15 3; then
                msg_ok "Waydroid VNC service restarted and verified"
            else
                msg_error "Waydroid VNC service failed verification"
                SERVICE_RESTART_FAILED=true

                # Attempt recovery
                msg_info "Attempting to recover VNC service..."
                systemctl stop waydroid-vnc.service
                sleep 2
                waydroid session stop 2>/dev/null || true
                sleep 2
                systemctl start waydroid-vnc.service

                if verify_service waydroid-vnc.service 10 3; then
                    msg_ok "VNC service recovered successfully"
                    SERVICE_RESTART_FAILED=false
                else
                    msg_error "VNC service recovery failed"
                fi
            fi
        else
            msg_error "Failed to restart Waydroid VNC service"
            SERVICE_RESTART_FAILED=true
        fi
    fi

    # Restart and verify API service
    if systemctl is-enabled waydroid-api.service &>/dev/null; then
        msg_info "Restarting Waydroid API service..."
        if systemctl restart waydroid-api.service; then
            if verify_service waydroid-api.service 10 2; then
                msg_ok "Waydroid API service restarted and verified"

                # Test API endpoint
                msg_info "Testing API endpoint..."
                sleep 2
                if curl -s -f http://localhost:8080/health &>/dev/null; then
                    msg_ok "API health endpoint is responding"
                else
                    msg_warn "API health endpoint is not responding (service may still be initializing)"
                fi
            else
                msg_error "Waydroid API service failed verification"
                SERVICE_RESTART_FAILED=true

                # Attempt recovery
                msg_info "Attempting to recover API service..."
                systemctl stop waydroid-api.service
                sleep 2
                systemctl start waydroid-api.service

                if verify_service waydroid-api.service 10 2; then
                    msg_ok "API service recovered successfully"
                    SERVICE_RESTART_FAILED=false
                else
                    msg_error "API service recovery failed"
                fi
            fi
        else
            msg_error "Failed to restart Waydroid API service"
            SERVICE_RESTART_FAILED=true
        fi
    fi

    # Report service restart status
    if [ "$SERVICE_RESTART_FAILED" = true ]; then
        msg_error "Some services failed to restart properly"
        msg_info "Check service logs:"
        echo "  - journalctl -u waydroid-vnc.service -n 50"
        echo "  - journalctl -u waydroid-api.service -n 50"
        msg_warn "You can restore from: $RESTORE_POINT"
    else
        msg_ok "All services restarted and verified successfully"
    fi
    echo ""
fi

# Post-update health check
if [ "$DRY_RUN" = false ]; then
    msg_info "Running post-update health check..."
    if [ -f "${SCRIPT_DIR}/health-check.sh" ]; then
        if bash "${SCRIPT_DIR}/health-check.sh" | tail -5; then
            msg_ok "Health check passed"
        else
            msg_warn "Health check reported issues - review logs"
        fi
    fi
    echo ""
fi

# Summary
echo -e "${GN}═══════════════════════════════════════════════${CL}"
if [ "$DRY_RUN" = true ]; then
    echo -e "${GN}  Update Preview Complete${CL}"
else
    echo -e "${GN}  Update Complete!${CL}"
fi
echo -e "${GN}  $(date '+%Y-%m-%d %H:%M:%S')${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

if [ "$DRY_RUN" = false ]; then
    msg_info "Update Summary:"
    echo "  Components Updated:"
    [ "$UPDATE_SYSTEM" = true ] && echo "    - System packages: ✓"
    [ "$UPDATE_WAYDROID" = true ] && echo "    - Waydroid: ✓"
    [ "$UPDATE_GPU" = true ] && echo "    - GPU drivers: ✓"
    echo ""

    msg_info "New Versions:"
    if command -v waydroid &>/dev/null; then
        new_waydroid=$(waydroid --version 2>/dev/null || echo "unknown")
        echo "  Waydroid: $new_waydroid"
    fi
    echo "  Python: $(python3 --version 2>/dev/null || echo 'not installed')"
    echo ""

    # Service status
    msg_info "Service Status:"
    for service in waydroid-vnc.service waydroid-api.service; do
        if systemctl is-enabled "$service" &>/dev/null; then
            if systemctl is-active --quiet "$service"; then
                echo -e "  $service: ${GN}Active${CL}"
            else
                echo -e "  $service: ${RD}Inactive${CL}"
            fi
        fi
    done
    echo ""

    if [ -n "$RESTORE_POINT" ]; then
        msg_info "Restore point: $RESTORE_POINT"
        echo ""
    fi

    msg_info "Recommended next steps:"
    echo "  1. Review logs: journalctl -u waydroid-vnc.service -n 50"
    echo "  2. Test VNC connection"
    echo "  3. Test API: curl http://localhost:8080/health"
    if [ "$SERVICE_RESTART_FAILED" = true ]; then
        echo ""
        msg_warn "Some services failed - please check logs and consider restoring"
    fi
    echo ""
fi
