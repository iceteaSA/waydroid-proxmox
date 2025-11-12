#!/usr/bin/env bash

# Waydroid LXC Installation Script for Proxmox
# Optimized for Intel N150 SoC with GPU Passthrough
# Copyright (c) 2025
# License: MIT

# Color definitions
BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
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

# Check if running on Proxmox
if ! command -v pveversion &> /dev/null; then
    msg_error "This script must be run on a Proxmox VE host"
    exit 1
fi

msg_info "Waydroid LXC Installation for Proxmox VE"
echo -e "${GN}Optimized for Intel N150 SoC with GPU Passthrough${CL}\n"

# Get next available CTID if not specified
if [ -z "$CTID" ]; then
    CTID=$(pvesh get /cluster/nextid)
    msg_info "Using next available CT ID: $CTID"
fi

# Check for Intel GPU
msg_info "Checking for Intel GPU..."
if ! lspci | grep -i "VGA.*Intel" &> /dev/null; then
    msg_error "Intel GPU not detected. This script is optimized for Intel N150 SoC"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    msg_ok "Intel GPU detected"
fi

# Get GPU device information
msg_info "Detecting GPU devices..."
GPU_DEVICES=$(ls -la /dev/dri/ | grep -E "card|renderD" | awk '{print $NF}')
msg_ok "Found GPU devices: $(echo $GPU_DEVICES | tr '\n' ' ')"

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

# Configure container for GPU passthrough
msg_info "Configuring GPU passthrough..."

# Add GPU devices to container config
CONFIG_FILE="/etc/pve/lxc/${CTID}.conf"

# Add device passthrough entries
cat >> $CONFIG_FILE <<EOF

# GPU Passthrough for Waydroid
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 29:0 rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir 0 0
lxc.mount.entry: /dev/fb0 dev/fb0 none bind,optional,create=file 0 0

# Additional features for Waydroid
lxc.apparmor.profile: unconfined
lxc.cap.drop:
lxc.cgroup2.devices.allow: a
lxc.mount.auto: proc:rw sys:rw cgroup:rw

# Kernel modules
lxc.autodev: 1
EOF

msg_ok "GPU passthrough configured"

# Load required kernel modules on host
msg_info "Loading required kernel modules..."
modprobe binder_linux || msg_error "Failed to load binder_linux module"
modprobe ashmem_linux || msg_error "Failed to load ashmem_linux module"

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

# Execute setup script in container
msg_info "Running setup script in container (this may take several minutes)..."
pct exec $CTID -- bash /tmp/waydroid-setup.sh

# Get container IP
CONTAINER_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

msg_ok "Installation Complete!"
echo -e "\n${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}Waydroid LXC Successfully Installed!${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"
echo -e "${BL}Container Details:${CL}"
echo -e "  CTID: ${GN}${CTID}${CL}"
echo -e "  IP Address: ${GN}${CONTAINER_IP}${CL}"
echo -e "  Hostname: ${GN}${HOSTNAME}${CL}\n"
echo -e "${BL}Access Information:${CL}"
echo -e "  VNC: ${GN}${CONTAINER_IP}:5900${CL}"
echo -e "  Home Assistant API: ${GN}http://${CONTAINER_IP}:8080${CL}\n"
echo -e "${BL}Next Steps:${CL}"
echo -e "  1. Enter container: ${GN}pct enter ${CTID}${CL}"
echo -e "  2. Start Waydroid: ${GN}systemctl start waydroid-vnc${CL}"
echo -e "  3. Start API: ${GN}systemctl start waydroid-api${CL}"
echo -e "  4. Connect via VNC to install Android apps\n"
echo -e "${BL}Home Assistant Integration:${CL}"
echo -e "  POST http://${CONTAINER_IP}:8080/app/launch"
echo -e "  Body: {\"package\": \"com.example.app\"}\n"
