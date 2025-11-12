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

# Check if running on Proxmox
if ! command -v pveversion &> /dev/null; then
    msg_error "This script must be run on a Proxmox VE host"
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

# Get GPU device information if hardware acceleration
if [ "$SOFTWARE_RENDERING" = "0" ]; then
    msg_info "Detecting GPU devices..."
    if [ -d /dev/dri ]; then
        GPU_DEVICES=$(ls -la /dev/dri/ 2>/dev/null | grep -E "card|renderD" | awk '{print $NF}')
        if [ -n "$GPU_DEVICES" ]; then
            msg_ok "Found GPU devices: $(echo $GPU_DEVICES | tr '\n' ' ')"
        else
            msg_warn "No GPU devices found in /dev/dri/"
        fi
    else
        msg_warn "/dev/dri/ directory not found"
    fi
    echo ""
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

# Download OS template if not present
msg_info "Checking for OS template..."
TEMPLATE_PATH="/var/lib/vz/template/cache/${OS_TEMPLATE}_amd64.tar.zst"
if [ ! -f "$TEMPLATE_PATH" ]; then
    msg_info "Downloading Debian 12 template..."
    pveam update
    pveam download local ${OS_TEMPLATE}_amd64.tar.zst
    msg_ok "Template downloaded"
else
    msg_ok "Template already exists"
fi

# Create LXC container
msg_info "Creating LXC container ${CTID}..."
pct create $CTID $TEMPLATE_PATH \
    --hostname $HOSTNAME \
    --cores $CORES \
    --memory $RAM \
    --swap 512 \
    --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
    --storage $STORAGE \
    --rootfs $STORAGE:$DISK_SIZE \
    --unprivileged $UNPRIVILEGED \
    --features nesting=1,keyctl=1 \
    --ostype debian \
    --onboot 1

msg_ok "Container created"

# Configure container config file
CONFIG_FILE="/etc/pve/lxc/${CTID}.conf"

# Add base Waydroid configuration
cat >> $CONFIG_FILE <<EOF

# Waydroid Configuration
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: a
lxc.mount.auto: proc:rw sys:rw cgroup:rw
lxc.autodev: 1
EOF

# Configure GPU passthrough if hardware acceleration
if [ "$SOFTWARE_RENDERING" = "0" ]; then
    msg_info "Configuring GPU passthrough..."

    cat >> $CONFIG_FILE <<EOF

# GPU Passthrough for Waydroid
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 29:0 rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir 0 0
lxc.mount.entry: /dev/fb0 dev/fb0 none bind,optional,create=file 0 0
EOF

    msg_ok "GPU passthrough configured"
else
    msg_info "Skipping GPU passthrough (software rendering mode)"
fi

# Add privileged-specific config
if [ "$UNPRIVILEGED" = "0" ]; then
    cat >> $CONFIG_FILE <<EOF
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
pct start $CTID
sleep 5
msg_ok "Container started"

# Wait for container to be ready
msg_info "Waiting for container to be ready..."
for i in {1..30}; do
    if pct exec $CTID -- systemctl is-system-running --wait &>/dev/null; then
        break
    fi
    sleep 2
done
msg_ok "Container is ready"

# Copy setup script into container
msg_info "Copying setup script to container..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pct push $CTID "${SCRIPT_DIR}/../ct/waydroid-lxc.sh" /tmp/waydroid-setup.sh
msg_ok "Setup script copied"

# Execute setup script in container with parameters
msg_info "Running setup script in container (this may take several minutes)..."
pct exec $CTID -- bash /tmp/waydroid-setup.sh "$GPU_TYPE" "$USE_GAPPS" "$SOFTWARE_RENDERING"

# Get container IP
CONTAINER_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

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
