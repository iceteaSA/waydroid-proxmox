#!/usr/bin/env bash

# Waydroid LXC Installation Script for Proxmox
# Copyright (c) 2025
# License: MIT

# Color definitions
BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
YW="\033[1;93m"
CL="\033[m"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

# Default values
CTID=""
HOSTNAME="waydroid"
DISK_SIZE="16"
CORES="2"
RAM="2048"
BRIDGE="vmbr0"
STORAGE="local-lxc"
OS_TEMPLATE="debian-12-standard"
UNPRIVILEGED=0
GPU_TYPE=""
USE_GAPPS="yes"
SOFTWARE_RENDERING=0
GPU_DEVICE=""
RENDER_NODE=""

# Functions
msg_info() {
    echo -e "${BL}[INFO]${CL} $1"
}

msg_ok() {
    echo -e "${CM} $1"
}

msg_error() {
    echo -e "${CROSS} $1"
}

msg_warn() {
    echo -e "${YW}[WARN]${CL} $1"
}

# Cleanup function for error handling
cleanup_on_error() {
    local exit_code=$?
    msg_error "Installation failed at line $LINENO. Exit code: $exit_code"
    echo ""

    # Check if container was created
    if [ -n "${CTID:-}" ] && pct status "$CTID" &>/dev/null; then
        echo -e "${YW}Container $CTID was created but installation failed.${CL}"
        read -p "Do you want to remove the failed container? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            msg_info "Removing container $CTID..."
            pct stop "$CTID" 2>/dev/null || true
            pct destroy "$CTID" 2>/dev/null || true
            msg_ok "Container removed"
        else
            msg_info "Container $CTID left in place for debugging"
            echo -e "  Debug: ${GN}pct enter ${CTID}${CL}"
            echo -e "  Logs: ${GN}pct exec ${CTID} -- journalctl -xe${CL}"
        fi
    fi

    # Check if kernel module config was created
    if [ -f /etc/modules-load.d/waydroid.conf ]; then
        read -p "Remove kernel module configuration? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f /etc/modules-load.d/waydroid.conf
            msg_ok "Kernel module configuration removed"
        fi
    fi

    echo ""
    echo -e "${BL}Manual cleanup commands (if needed):${CL}"
    [ -n "${CTID:-}" ] && echo -e "  Remove container: ${GN}pct destroy ${CTID}${CL}"
    echo -e "  Remove modules config: ${GN}rm /etc/modules-load.d/waydroid.conf${CL}"
    echo -e "  Unload modules: ${GN}modprobe -r binder_linux ashmem_linux${CL}"
    echo ""

    exit $exit_code
}

# Preflight checks function
preflight_checks() {
    local checks_passed=true

    msg_info "Running preflight checks..."

    # Check required commands
    local required_cmds=("pct" "pvesm" "pveam" "modprobe" "lspci")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            msg_error "Required command not found: $cmd"
            checks_passed=false
        fi
    done

    # Check if storage exists
    if ! pvesm status | grep -q "^${STORAGE}"; then
        msg_error "Storage '${STORAGE}' does not exist"
        msg_info "Available storage:"
        pvesm status | awk 'NR>1 {print "  - " $1}'
        checks_passed=false
    else
        msg_ok "Storage '${STORAGE}' exists"
    fi

    # Check if network bridge exists
    if [ ! -d "/sys/class/net/${BRIDGE}" ]; then
        msg_error "Network bridge '${BRIDGE}' does not exist"
        msg_info "Available bridges:"
        ls /sys/class/net/ | grep -E '^vmbr' | while read br; do
            echo "  - $br"
        done
        checks_passed=false
    else
        msg_ok "Network bridge '${BRIDGE}' exists"
    fi

    # Check available disk space on storage
    local storage_path=$(pvesm path "${STORAGE}:1" 2>/dev/null | sed 's|/[^/]*$||' || echo "")
    if [ -n "$storage_path" ] && [ -d "$storage_path" ]; then
        local available_gb=$(df -BG "$storage_path" | awk 'NR==2 {print $4}' | sed 's/G//')
        local required_gb=$((DISK_SIZE + 5))  # Add 5GB buffer
        if [ "$available_gb" -lt "$required_gb" ]; then
            msg_error "Insufficient disk space on ${STORAGE}: ${available_gb}GB available, ${required_gb}GB required"
            checks_passed=false
        else
            msg_ok "Sufficient disk space: ${available_gb}GB available"
        fi
    fi

    # Check for kernel module support
    if ! modinfo binder_linux &>/dev/null && ! modprobe binder_linux &>/dev/null; then
        msg_warn "binder_linux module not available - Waydroid may not work properly"
    fi

    if [ "$checks_passed" = false ]; then
        msg_error "Preflight checks failed. Please resolve the issues above."
        exit 1
    fi

    msg_ok "All preflight checks passed"
    echo ""
}

# Post-installation verification function
post_install_verification() {
    local verification_passed=true

    msg_info "Running post-installation verification..."
    echo ""

    # Check if container is running
    if pct status "$CTID" | grep -q "running"; then
        msg_ok "Container is running"
    else
        msg_error "Container is not running"
        verification_passed=false
    fi

    # Check if container has network connectivity
    if pct exec "$CTID" -- ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        msg_ok "Container has network connectivity"
    else
        msg_warn "Container may not have network connectivity"
        # Don't fail on network check as it might be a firewall issue
    fi

    # Check if Waydroid is installed
    if pct exec "$CTID" -- command -v waydroid &>/dev/null; then
        msg_ok "Waydroid is installed"
    else
        msg_error "Waydroid is not installed"
        verification_passed=false
    fi

    # Check if Waydroid systemd services exist
    if pct exec "$CTID" -- systemctl list-unit-files | grep -q "waydroid-container.service"; then
        msg_ok "Waydroid service is configured"
    else
        msg_warn "Waydroid service not found"
    fi

    # Check if wayvnc is installed
    if pct exec "$CTID" -- command -v wayvnc &>/dev/null; then
        msg_ok "WayVNC is installed"
    else
        msg_warn "WayVNC is not installed"
    fi

    # Check GPU devices if hardware rendering
    if [ "$SOFTWARE_RENDERING" = "0" ]; then
        if pct exec "$CTID" -- test -d /dev/dri; then
            msg_ok "GPU devices directory exists in container"

            # Check specific devices
            local gpu_devices_found=false
            if [ -n "$GPU_DEVICE" ] && pct exec "$CTID" -- test -e "$GPU_DEVICE"; then
                msg_ok "GPU card device accessible: $GPU_DEVICE"
                gpu_devices_found=true
            fi

            if [ -n "$RENDER_NODE" ] && pct exec "$CTID" -- test -e "$RENDER_NODE"; then
                msg_ok "GPU render node accessible: $RENDER_NODE"
                gpu_devices_found=true
            fi

            if [ "$gpu_devices_found" = false ]; then
                msg_warn "No specific GPU devices accessible, but /dev/dri exists"
            fi
        else
            msg_error "GPU devices not accessible in container"
            verification_passed=false
        fi

        # Check if GPU group permissions are correct
        if pct exec "$CTID" -- getent group render &>/dev/null; then
            msg_ok "Render group exists in container"
        else
            msg_warn "Render group not found in container"
        fi
    fi

    # Check binder devices
    if pct exec "$CTID" -- test -e /dev/binder; then
        msg_ok "Binder device accessible"
    else
        msg_warn "Binder device not found - this may be normal on first boot"
    fi

    echo ""
    if [ "$verification_passed" = false ]; then
        msg_error "Post-installation verification found issues"
        msg_warn "The container may not function correctly"
        msg_info "Check logs: pct exec $CTID -- journalctl -xe"
        return 1
    else
        msg_ok "All post-installation checks passed"
        return 0
    fi
}

# Enable strict error handling
set -euo pipefail
trap cleanup_on_error ERR

# Check if running on Proxmox
if ! command -v pveversion &> /dev/null; then
    msg_error "This script must be run on a Proxmox VE host"
    exit 1
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    msg_error "This script must be run as root"
    exit 1
fi

echo -e "${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}  Waydroid LXC Installation for Proxmox VE${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

# Get next available CTID if not specified
if [ -z "$CTID" ]; then
    CTID=$(pvesh get /cluster/nextid)
    msg_info "Using next available CT ID: $CTID"
fi

# Validate CTID
if ! [[ "$CTID" =~ ^[0-9]+$ ]]; then
    msg_error "Invalid CTID: must be numeric"
    exit 1
fi

if [ "$CTID" -lt 100 ] || [ "$CTID" -gt 999999999 ]; then
    msg_error "Invalid CTID: must be between 100 and 999999999"
    exit 1
fi

if pct status "$CTID" &>/dev/null; then
    msg_error "Container $CTID already exists"
    exit 1
fi

# Ask about container type
echo -e "${BL}Container Configuration:${CL}"
echo -e "  1) Privileged (recommended for GPU passthrough)"
echo -e "  2) Unprivileged (more secure, software rendering only)"
read -p "Select container type [1]: " CONTAINER_TYPE
CONTAINER_TYPE=${CONTAINER_TYPE:-1}

if [ "$CONTAINER_TYPE" = "2" ]; then
    UNPRIVILEGED=1
    SOFTWARE_RENDERING=1
    msg_warn "Unprivileged container selected - will use software rendering"
    echo ""
fi

# Ask about GPU type (only if privileged)
if [ "$UNPRIVILEGED" = "0" ]; then
    echo -e "${BL}GPU Configuration:${CL}"
    echo -e "  1) Intel (recommended - hardware acceleration)"
    echo -e "  2) AMD (hardware acceleration)"
    echo -e "  3) NVIDIA (software rendering only)"
    echo -e "  4) Software rendering (no GPU passthrough)"
    read -p "Select GPU type [1]: " GPU_CHOICE
    GPU_CHOICE=${GPU_CHOICE:-1}

    case $GPU_CHOICE in
        1)
            GPU_TYPE="intel"
            msg_info "Intel GPU selected"
            ;;
        2)
            GPU_TYPE="amd"
            msg_info "AMD GPU selected"
            ;;
        3)
            GPU_TYPE="nvidia"
            SOFTWARE_RENDERING=1
            msg_warn "NVIDIA selected - using software rendering (GPU passthrough not supported)"
            ;;
        4)
            GPU_TYPE="software"
            SOFTWARE_RENDERING=1
            msg_info "Software rendering selected"
            ;;
        *)
            msg_error "Invalid choice, defaulting to Intel"
            GPU_TYPE="intel"
            ;;
    esac
    echo ""
else
    GPU_TYPE="software"
fi

# Detect GPU if hardware acceleration selected
if [ "$SOFTWARE_RENDERING" = "0" ]; then
    msg_info "Detecting ${GPU_TYPE^^} GPU..."

    case $GPU_TYPE in
        intel)
            if lspci | grep -i "VGA.*Intel" &> /dev/null; then
                msg_ok "Intel GPU detected"
                lspci | grep -i "VGA.*Intel"
            else
                msg_error "Intel GPU not detected"
                read -p "Continue with software rendering? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    SOFTWARE_RENDERING=1
                    GPU_TYPE="software"
                    msg_warn "Switched to software rendering"
                else
                    exit 1
                fi
            fi
            ;;
        amd)
            if lspci | grep -i "VGA.*AMD\|VGA.*Radeon" &> /dev/null; then
                msg_ok "AMD GPU detected"
                lspci | grep -i "VGA.*AMD\|VGA.*Radeon"
            else
                msg_error "AMD GPU not detected"
                read -p "Continue with software rendering? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    SOFTWARE_RENDERING=1
                    GPU_TYPE="software"
                    msg_warn "Switched to software rendering"
                else
                    exit 1
                fi
            fi
            ;;
    esac
    echo ""
fi

# Detect and select GPU devices if hardware acceleration
if [ "$SOFTWARE_RENDERING" = "0" ]; then
    msg_info "Detecting GPU devices..."

    if [ -d /dev/dri ]; then
        # Detect all card and renderD devices
        mapfile -t CARDS < <(ls /dev/dri/card* 2>/dev/null | sort)
        mapfile -t RENDERS < <(ls /dev/dri/renderD* 2>/dev/null | sort)

        if [ ${#CARDS[@]} -eq 0 ] && [ ${#RENDERS[@]} -eq 0 ]; then
            msg_warn "No GPU devices found in /dev/dri/"
            read -p "Continue with software rendering? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                SOFTWARE_RENDERING=1
                GPU_TYPE="software"
            else
                exit 1
            fi
        else
            msg_ok "Found GPU devices"

            # Select card device if multiple available
            if [ ${#CARDS[@]} -gt 1 ]; then
                echo -e "\n${BL}Multiple GPU card devices detected:${CL}"
                for i in "${!CARDS[@]}"; do
                    device="${CARDS[$i]}"
                    # Try to get GPU info for this card
                    card_num=$(basename "$device" | sed 's/card//')
                    gpu_info=""

                    # Get GPU info from lspci if available
                    if [ -f "/sys/class/drm/card${card_num}/device/uevent" ]; then
                        pci_slot=$(grep PCI_SLOT_NAME /sys/class/drm/card${card_num}/device/uevent 2>/dev/null | cut -d= -f2)
                        if [ -n "$pci_slot" ]; then
                            gpu_info=$(lspci -s "$pci_slot" | grep -i "VGA\|3D\|Display" | cut -d: -f3- | xargs)
                        fi
                    fi

                    echo -e "  $((i+1))) ${device}${gpu_info:+ - $gpu_info}"
                done

                read -p "Select card device [1]: " CARD_CHOICE
                CARD_CHOICE=${CARD_CHOICE:-1}

                # Validate numeric input
                if ! [[ "$CARD_CHOICE" =~ ^[0-9]+$ ]]; then
                    GPU_DEVICE="${CARDS[0]}"
                    msg_warn "Invalid input (not numeric), using: $GPU_DEVICE"
                elif [ "$CARD_CHOICE" -ge 1 ] && [ "$CARD_CHOICE" -le ${#CARDS[@]} ]; then
                    GPU_DEVICE="${CARDS[$((CARD_CHOICE-1))]}"
                    msg_ok "Selected: $GPU_DEVICE"
                else
                    GPU_DEVICE="${CARDS[0]}"
                    msg_warn "Invalid choice, using: $GPU_DEVICE"
                fi
            elif [ ${#CARDS[@]} -eq 1 ]; then
                GPU_DEVICE="${CARDS[0]}"
                msg_ok "Using card device: $GPU_DEVICE"
            fi

            # Select render node if multiple available
            if [ ${#RENDERS[@]} -gt 1 ]; then
                echo -e "\n${BL}Multiple render nodes detected:${CL}"
                for i in "${!RENDERS[@]}"; do
                    device="${RENDERS[$i]}"
                    # Try to get info about render node
                    render_num=$(basename "$device" | sed 's/renderD//')

                    echo -e "  $((i+1))) ${device}"
                done

                read -p "Select render node [1]: " RENDER_CHOICE
                RENDER_CHOICE=${RENDER_CHOICE:-1}

                # Validate numeric input
                if ! [[ "$RENDER_CHOICE" =~ ^[0-9]+$ ]]; then
                    RENDER_NODE="${RENDERS[0]}"
                    msg_warn "Invalid input (not numeric), using: $RENDER_NODE"
                elif [ "$RENDER_CHOICE" -ge 1 ] && [ "$RENDER_CHOICE" -le ${#RENDERS[@]} ]; then
                    RENDER_NODE="${RENDERS[$((RENDER_CHOICE-1))]}"
                    msg_ok "Selected: $RENDER_NODE"
                else
                    RENDER_NODE="${RENDERS[0]}"
                    msg_warn "Invalid choice, using: $RENDER_NODE"
                fi
            elif [ ${#RENDERS[@]} -eq 1 ]; then
                RENDER_NODE="${RENDERS[0]}"
                msg_ok "Using render node: $RENDER_NODE"
            fi

            echo ""
        fi
    else
        msg_warn "/dev/dri/ directory not found"
        SOFTWARE_RENDERING=1
        GPU_TYPE="software"
    fi
fi

# Ask about GAPPS
echo -e "${BL}Android Configuration:${CL}"
echo -e "Include Google Apps (Play Store, Gmail, etc.)?"
read -p "Install GAPPS? (Y/n): " GAPPS_CHOICE
GAPPS_CHOICE=${GAPPS_CHOICE:-y}

if [[ $GAPPS_CHOICE =~ ^[Nn]$ ]]; then
    USE_GAPPS="no"
    msg_info "Waydroid will be installed without GAPPS"
else
    USE_GAPPS="yes"
    msg_info "Waydroid will be installed with GAPPS (Google Play Store)"
fi
echo ""

# Summary
echo -e "${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}  Installation Summary${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}"
echo -e "${BL}Container:${CL}"
echo -e "  CTID: ${GN}${CTID}${CL}"
echo -e "  Type: ${GN}$([ "$UNPRIVILEGED" = "1" ] && echo "Unprivileged" || echo "Privileged")${CL}"
echo -e "  Cores: ${GN}${CORES}${CL}"
echo -e "  RAM: ${GN}${RAM}MB${CL}"
echo -e "  Disk: ${GN}${DISK_SIZE}GB${CL}"
echo -e "${BL}GPU:${CL}"
echo -e "  Type: ${GN}${GPU_TYPE}${CL}"
echo -e "  Acceleration: ${GN}$([ "$SOFTWARE_RENDERING" = "1" ] && echo "Software" || echo "Hardware")${CL}"
if [ "$SOFTWARE_RENDERING" = "0" ]; then
    [ -n "$GPU_DEVICE" ] && echo -e "  Card: ${GN}${GPU_DEVICE}${CL}"
    [ -n "$RENDER_NODE" ] && echo -e "  Render: ${GN}${RENDER_NODE}${CL}"
fi
echo -e "${BL}Android:${CL}"
echo -e "  GAPPS: ${GN}${USE_GAPPS}${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

read -p "Continue with installation? (Y/n): " CONFIRM
CONFIRM=${CONFIRM:-y}
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    msg_info "Installation cancelled"
    exit 0
fi
echo ""

# Run preflight checks
preflight_checks

# Download OS template if not present
msg_info "Checking for OS template..."

# Validate OS_TEMPLATE to prevent path traversal
if [[ "$OS_TEMPLATE" =~ \.\./|\.\. ]]; then
    msg_error "Invalid OS_TEMPLATE: path traversal detected"
    exit 1
fi

if [[ "$OS_TEMPLATE" =~ ^/ ]]; then
    msg_error "Invalid OS_TEMPLATE: absolute paths not allowed"
    exit 1
fi

TEMPLATE_PATH="/var/lib/vz/template/cache/${OS_TEMPLATE}_amd64.tar.zst"
if [ ! -f "$TEMPLATE_PATH" ]; then
    msg_info "Downloading Debian 12 template..."
    if ! pveam update; then
        msg_error "Failed to update template list"
        exit 1
    fi
    if ! pveam download "$STORAGE" "${OS_TEMPLATE}_amd64.tar.zst"; then
        msg_error "Failed to download template"
        exit 1
    fi
    msg_ok "Template downloaded"
else
    msg_ok "Template already exists"
fi

# Verify template was downloaded
if [ ! -f "$TEMPLATE_PATH" ]; then
    msg_error "Template file not found after download: $TEMPLATE_PATH"
    exit 1
fi

# Create LXC container
msg_info "Creating LXC container ${CTID}..."
if ! pct create "$CTID" "$TEMPLATE_PATH" \
    --hostname "$HOSTNAME" \
    --cores "$CORES" \
    --memory "$RAM" \
    --swap 512 \
    --net0 "name=eth0,bridge=$BRIDGE,ip=dhcp" \
    --storage "$STORAGE" \
    --rootfs "$STORAGE:$DISK_SIZE" \
    --unprivileged "$UNPRIVILEGED" \
    --features nesting=1,keyctl=1 \
    --ostype debian \
    --onboot 1; then
    msg_error "Failed to create container"
    exit 1
fi

msg_ok "Container created"

# Configure container config file
CONFIG_FILE="/etc/pve/lxc/${CTID}.conf"

# Add base Waydroid configuration
cat >> "$CONFIG_FILE" <<EOF

# Waydroid Configuration
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: a
lxc.mount.auto: proc:rw sys:rw cgroup:rw
lxc.autodev: 1
EOF

# Configure GPU passthrough if hardware acceleration
if [ "$SOFTWARE_RENDERING" = "0" ]; then
    msg_info "Configuring GPU passthrough..."

    cat >> "$CONFIG_FILE" <<EOF

# GPU Passthrough for Waydroid
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 29:0 rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir 0 0
lxc.mount.entry: /dev/fb0 dev/fb0 none bind,optional,create=file 0 0
EOF

    # Add specific device mounts if selected
    if [ -n "$GPU_DEVICE" ]; then
        # Validate GPU device path
        if ! [[ "$GPU_DEVICE" =~ ^/dev/dri/card[0-9]+$ ]]; then
            msg_error "Invalid GPU device path: $GPU_DEVICE"
            exit 1
        fi
        card_name=$(basename "$GPU_DEVICE")
        echo "lxc.mount.entry: $GPU_DEVICE dev/dri/$card_name none bind,optional,create=file 0 0" >> "$CONFIG_FILE"
    fi

    if [ -n "$RENDER_NODE" ]; then
        # Validate render node path
        if ! [[ "$RENDER_NODE" =~ ^/dev/dri/renderD[0-9]+$ ]]; then
            msg_error "Invalid render node path: $RENDER_NODE"
            exit 1
        fi
        render_name=$(basename "$RENDER_NODE")
        echo "lxc.mount.entry: $RENDER_NODE dev/dri/$render_name none bind,optional,create=file 0 0" >> "$CONFIG_FILE"
    fi

    msg_ok "GPU passthrough configured"
else
    msg_info "Skipping GPU passthrough (software rendering mode)"
fi

# Add privileged-specific config
if [ "$UNPRIVILEGED" = "0" ]; then
    cat >> "$CONFIG_FILE" <<EOF
lxc.cap.drop:
EOF
fi

# Load required kernel modules on host
msg_info "Loading required kernel modules..."
modprobe binder_linux 2>/dev/null || msg_warn "binder_linux module not available"
modprobe ashmem_linux 2>/dev/null || msg_warn "ashmem_linux module not available"

# Make modules persistent
cat > /etc/modules-load.d/waydroid.conf <<EOF
binder_linux
ashmem_linux
EOF

msg_ok "Kernel modules configured"

# Start the container
msg_info "Starting container..."
if ! pct start "$CTID"; then
    msg_error "Failed to start container"
    exit 1
fi
sleep 5
msg_ok "Container started"

# Wait for container to be ready with exponential backoff
msg_info "Waiting for container to be ready..."
READY=false
MAX_ATTEMPTS=15
TOTAL_WAIT=0
attempt=1
wait_time=1

while [ $attempt -le $MAX_ATTEMPTS ]; do
    if pct exec "$CTID" -- systemctl is-system-running --wait &>/dev/null; then
        READY=true
        break
    fi

    # Log progress every few attempts
    if [ $attempt -eq 5 ] || [ $attempt -eq 10 ]; then
        msg_info "Still waiting... (${TOTAL_WAIT}s elapsed, attempt $attempt/$MAX_ATTEMPTS)"
    fi

    # Exponential backoff: 1, 2, 4, 8, 16, 16, 16...
    sleep $wait_time
    TOTAL_WAIT=$((TOTAL_WAIT + wait_time))

    # Double wait time up to max of 16 seconds
    if [ $wait_time -lt 16 ]; then
        wait_time=$((wait_time * 2))
    fi

    attempt=$((attempt + 1))
done

if [ "$READY" = false ]; then
    msg_error "Container failed to become ready after ${TOTAL_WAIT} seconds"
    msg_info "Checking container status..."
    pct status "$CTID" || true
    msg_info "Recent container logs:"
    pct exec "$CTID" -- journalctl -n 50 --no-pager 2>/dev/null || msg_warn "Could not retrieve logs"
    exit 1
fi
msg_ok "Container is ready (took ${TOTAL_WAIT}s)"

# Copy setup script into container
msg_info "Copying setup script to container..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="${SCRIPT_DIR}/../ct/waydroid-lxc.sh"

if [ ! -f "$SETUP_SCRIPT" ]; then
    msg_error "Setup script not found: $SETUP_SCRIPT"
    exit 1
fi

if ! pct push "$CTID" "$SETUP_SCRIPT" /tmp/waydroid-setup.sh; then
    msg_error "Failed to copy setup script to container"
    exit 1
fi
msg_ok "Setup script copied"

# Execute setup script in container with parameters
msg_info "Running setup script in container (this may take several minutes)..."
if ! pct exec "$CTID" -- bash /tmp/waydroid-setup.sh "$GPU_TYPE" "$USE_GAPPS" "$SOFTWARE_RENDERING" "$GPU_DEVICE" "$RENDER_NODE"; then
    msg_error "Setup script failed inside container"
    msg_info "You can try to debug by entering the container: pct enter $CTID"
    msg_info "Check logs: pct exec $CTID -- journalctl -xe"
    exit 1
fi

# Run post-installation verification
if ! post_install_verification; then
    msg_warn "Installation completed with warnings - manual verification recommended"
fi

# Get container IP
msg_info "Retrieving container IP address..."
CONTAINER_IP=$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$CONTAINER_IP" ]; then
    msg_warn "Could not retrieve container IP address"
    CONTAINER_IP="<container-ip>"
else
    msg_ok "Container IP: $CONTAINER_IP"
fi

msg_ok "Installation Complete!"
echo -e "\n${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}  Waydroid LXC Successfully Installed!${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"
echo -e "${BL}Container Details:${CL}"
echo -e "  CTID: ${GN}${CTID}${CL}"
echo -e "  Type: ${GN}$([ "$UNPRIVILEGED" = "1" ] && echo "Unprivileged" || echo "Privileged")${CL}"
echo -e "  IP Address: ${GN}${CONTAINER_IP}${CL}"
echo -e "  Hostname: ${GN}${HOSTNAME}${CL}"
echo -e "${BL}GPU Configuration:${CL}"
echo -e "  Type: ${GN}${GPU_TYPE}${CL}"
echo -e "  Rendering: ${GN}$([ "$SOFTWARE_RENDERING" = "1" ] && echo "Software" || echo "Hardware Accelerated")${CL}"
if [ "$SOFTWARE_RENDERING" = "0" ]; then
    [ -n "$GPU_DEVICE" ] && echo -e "  Card: ${GN}${GPU_DEVICE}${CL}"
    [ -n "$RENDER_NODE" ] && echo -e "  Render: ${GN}${RENDER_NODE}${CL}"
fi
echo -e "${BL}Android:${CL}"
echo -e "  GAPPS: ${GN}${USE_GAPPS}${CL}"
echo -e "${BL}Access Information:${CL}"
echo -e "  VNC: ${GN}${CONTAINER_IP}:5900${CL}"
echo -e "  Home Assistant API: ${GN}http://${CONTAINER_IP}:8080${CL}\n"
echo -e "${BL}Next Steps:${CL}"
echo -e "  1. Enter container: ${GN}pct enter ${CTID}${CL}"
echo -e "  2. Start Waydroid: ${GN}systemctl start waydroid-vnc${CL}"
echo -e "  3. Start API: ${GN}systemctl start waydroid-api${CL}"
echo -e "  4. Connect via VNC to access Android\n"

if [ "$USE_GAPPS" = "yes" ]; then
    echo -e "${BL}Google Play Store:${CL}"
    echo -e "  Sign in with your Google account via VNC\n"
fi

if [ "$SOFTWARE_RENDERING" = "1" ]; then
    msg_warn "Software rendering is slower than hardware acceleration"
    echo -e "  Graphics performance may be limited\n"
fi

echo -e "${BL}Home Assistant Integration:${CL}"
echo -e "  POST http://${CONTAINER_IP}:8080/app/launch"
echo -e "  Body: {\"package\": \"com.example.app\"}\n"
