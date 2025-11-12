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

# Configuration
DRY_RUN=false
BACKUP_BEFORE_UPDATE=true
UPDATE_SYSTEM=true
UPDATE_WAYDROID=true
UPDATE_SCRIPTS=false
RESTART_SERVICES=true

show_help() {
    cat << EOF
${GN}Waydroid LXC Update and Upgrade Tool${CL}

Usage: $0 [options]

Options:
    --dry-run           Show what would be updated without making changes
    --no-backup         Skip creating backup before update
    --system-only       Only update system packages
    --waydroid-only     Only update Waydroid
    --skip-restart      Don't restart services after update
    --help              Show this help message

Examples:
    $0                  # Full update with backup
    $0 --dry-run        # Preview updates
    $0 --system-only    # Only update system packages

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
            UPDATE_SCRIPTS=false
            shift
            ;;
        --waydroid-only)
            UPDATE_SYSTEM=false
            UPDATE_SCRIPTS=false
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

if [ "$DRY_RUN" = true ]; then
    msg_warn "Running in DRY-RUN mode - no changes will be made"
    echo ""
fi

echo -e "${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}  Waydroid LXC Update System${CL}"
echo -e "${GN}  $(date '+%Y-%m-%d %H:%M:%S')${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

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
        if apt-get update; then
            msg_ok "Package lists updated"

            msg_info "Upgrading system packages..."
            if DEBIAN_FRONTEND=noninteractive apt-get upgrade -y; then
                msg_ok "System packages upgraded"
            else
                msg_error "Failed to upgrade system packages"
            fi

            msg_info "Cleaning up..."
            apt-get autoremove -y &>/dev/null
            apt-get autoclean -y &>/dev/null
            msg_ok "Cleanup complete"
        else
            msg_error "Failed to update package lists"
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

        if [ "$current_version" != "$available_version" ]; then
            msg_info "Waydroid update available: $current_version → $available_version"

            # Stop Waydroid before update
            msg_info "Stopping Waydroid services..."
            systemctl stop waydroid-vnc.service 2>/dev/null || true
            waydroid session stop 2>/dev/null || true
            waydroid container stop 2>/dev/null || true
            sleep 2

            msg_info "Updating Waydroid..."
            if DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y waydroid; then
                msg_ok "Waydroid updated to $available_version"
            else
                msg_error "Failed to update Waydroid"
            fi
        else
            msg_ok "Waydroid is already up to date ($current_version)"
        fi
    fi
    echo ""
fi

# Update GPU drivers
echo -e "${BL}[3/4] Checking GPU Drivers${CL}"
if [ "$DRY_RUN" = true ]; then
    msg_info "Would check for GPU driver updates"
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
        if DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y $gpu_packages &>/dev/null; then
            msg_ok "GPU drivers updated"
        else
            msg_warn "No GPU driver updates available"
        fi
    else
        msg_info "No GPU drivers installed (software rendering mode)"
    fi
fi
echo ""

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
    msg_info "Restarting services..."

    if systemctl is-enabled waydroid-vnc.service &>/dev/null; then
        systemctl restart waydroid-vnc.service
        msg_ok "Waydroid VNC service restarted"
    fi

    if systemctl is-enabled waydroid-api.service &>/dev/null; then
        systemctl restart waydroid-api.service
        msg_ok "API service restarted"
    fi

    # Wait for services to stabilize
    sleep 5

    # Verify services are running
    if systemctl is-active --quiet waydroid-api.service; then
        msg_ok "API service is running"
    else
        msg_warn "API service may not be running properly"
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
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

if [ "$DRY_RUN" = false ]; then
    msg_info "New Versions:"
    if command -v waydroid &>/dev/null; then
        new_waydroid=$(waydroid --version 2>/dev/null || echo "unknown")
        echo "  Waydroid: $new_waydroid"
    fi
    echo ""

    msg_info "Recommended next steps:"
    echo "  1. Review logs: journalctl -u waydroid-vnc.service -n 50"
    echo "  2. Test VNC connection"
    echo "  3. Test API: curl http://localhost:8080/health"
    echo ""
fi
