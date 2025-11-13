#!/usr/bin/env bash

# Waydroid LXC Installation Script for Proxmox (Refactored)
# Copyright (c) 2025
# License: MIT
#
# This script uses Proxmox VE helper script functions for robust
# template downloading, storage selection, and container creation.

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Source helper functions
source "${REPO_ROOT}/misc/core.func"
source "${REPO_ROOT}/misc/build.func"

# Application definition
APP="Waydroid"
var_tags="android;waydroid"

# Call core initialization
variables

# Default settings for Waydroid
var_cpu="2"
var_ram="2048"
var_disk="16"
var_os="debian"
var_version="12"
var_unprivileged="0"  # Privileged by default for GPU access

# Waydroid-specific variables
GPU_TYPE=""
USE_GAPPS="yes"
SOFTWARE_RENDERING=0
GPU_DEVICE=""
RENDER_NODE=""

# Custom Waydroid prompts (before standard install_script)
waydroid_custom_settings() {
    echo ""
    msg_info "Waydroid-Specific Configuration"

    # Ask about container type
    echo -e "${BL}Container Configuration:${CL}"
    echo -e "  1) Privileged (recommended for GPU passthrough)"
    echo -e "  2) Unprivileged (more secure, software rendering only)"
    read -p "Select container type [1]: " CONTAINER_TYPE
    CONTAINER_TYPE=${CONTAINER_TYPE:-1}

    if [ "$CONTAINER_TYPE" = "2" ]; then
        var_unprivileged="1"
        SOFTWARE_RENDERING=1
        msg_warn "Unprivileged container selected - will use software rendering"
        echo ""
    else
        var_unprivileged="0"
    fi

    # Ask about GPU type (only if privileged)
    if [ "$var_unprivileged" = "0" ]; then
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
                        card_num=$(basename "$device" | sed 's/card//')
                        gpu_info=""

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

                    if ! [[ "$CARD_CHOICE" =~ ^[0-9]+$ ]]; then
                        GPU_DEVICE="${CARDS[0]}"
                        msg_warn "Invalid input, using: $GPU_DEVICE"
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
                        echo -e "  $((i+1))) ${RENDERS[$i]}"
                    done

                    read -p "Select render node [1]: " RENDER_CHOICE
                    RENDER_CHOICE=${RENDER_CHOICE:-1}

                    if ! [[ "$RENDER_CHOICE" =~ ^[0-9]+$ ]]; then
                        RENDER_NODE="${RENDERS[0]}"
                        msg_warn "Invalid input, using: $RENDER_NODE"
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
    echo -e "${GN}  Waydroid Configuration Summary${CL}"
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo -e "${BL}Container:${CL}"
    echo -e "  Type: ${GN}$([ "$var_unprivileged" = "1" ] && echo "Unprivileged" || echo "Privileged")${CL}"
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
}

# Custom container configuration for Waydroid
configure_waydroid_container() {
    local CTID=$1
    local CONFIG_FILE="/etc/pve/lxc/${CTID}.conf"

    msg_info "Configuring Waydroid-specific LXC settings..."

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
            if [[ "$GPU_DEVICE" =~ ^/dev/dri/card[0-9]+$ ]]; then
                card_name=$(basename "$GPU_DEVICE")
                echo "lxc.mount.entry: $GPU_DEVICE dev/dri/$card_name none bind,optional,create=file 0 0" >> "$CONFIG_FILE"
            fi
        fi

        if [ -n "$RENDER_NODE" ]; then
            if [[ "$RENDER_NODE" =~ ^/dev/dri/renderD[0-9]+$ ]]; then
                render_name=$(basename "$RENDER_NODE")
                echo "lxc.mount.entry: $RENDER_NODE dev/dri/$render_name none bind,optional,create=file 0 0" >> "$CONFIG_FILE"
            fi
        fi

        msg_ok "GPU passthrough configured"
    fi

    # Add privileged-specific config
    if [ "$var_unprivileged" = "0" ]; then
        cat >> "$CONFIG_FILE" <<EOF
lxc.cap.drop:
EOF
    fi

    msg_ok "Waydroid LXC configuration complete"
}

# Setup kernel modules on host
setup_kernel_modules() {
    msg_info "Loading required kernel modules..."
    modprobe binder_linux 2>/dev/null || msg_warn "binder_linux module not available"
    modprobe ashmem_linux 2>/dev/null || msg_warn "ashmem_linux module not available"

    # Make modules persistent
    cat > /etc/modules-load.d/waydroid.conf <<EOF
binder_linux
ashmem_linux
EOF

    msg_ok "Kernel modules configured"
}

# Install Waydroid inside container
install_waydroid_in_container() {
    local CTID=$1

    msg_info "Installing Waydroid in container..."

    # Copy setup script into container
    SETUP_SCRIPT="${REPO_ROOT}/ct/waydroid-lxc.sh"

    if [ ! -f "$SETUP_SCRIPT" ]; then
        msg_error "Setup script not found: $SETUP_SCRIPT"
        return 1
    fi

    if ! pct push "$CTID" "$SETUP_SCRIPT" /tmp/waydroid-setup.sh; then
        msg_error "Failed to copy setup script to container"
        return 1
    fi

    # Execute setup script in container with parameters
    if ! pct exec "$CTID" -- bash /tmp/waydroid-setup.sh "$GPU_TYPE" "$USE_GAPPS" "$SOFTWARE_RENDERING" "$GPU_DEVICE" "$RENDER_NODE"; then
        msg_error "Setup script failed inside container"
        msg_info "Debug: pct enter $CTID"
        msg_info "Logs: pct exec $CTID -- journalctl -xe"
        return 1
    fi

    msg_ok "Waydroid installed successfully"
    return 0
}

# Main installation flow
main() {
    # Standard checks
    pve_check
    shell_check
    root_check
    arch_check

    # Display header
    clear
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo -e "${GN}  Waydroid LXC Installation for Proxmox VE${CL}"
    echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

    # Waydroid-specific configuration prompts
    waydroid_custom_settings

    # Confirm installation
    read -p "Continue with installation? (Y/n): " CONFIRM
    CONFIRM=${CONFIRM:-y}
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        msg_info "Installation cancelled"
        exit 0
    fi
    echo ""

    # Setup host kernel modules
    setup_kernel_modules

    # Run standard install_script to get container settings
    # This will handle all the standard Proxmox configuration
    install_script

    # Build the container using standard functions
    # This handles template download, storage selection, and container creation
    build_container

    # Get the container ID that was created
    CTID="${CT_ID}"

    # Apply Waydroid-specific configuration
    configure_waydroid_container "$CTID"

    # Restart container to apply new config
    msg_info "Restarting container to apply configuration..."
    pct stop "$CTID" 2>/dev/null || true
    sleep 2
    pct start "$CTID"

    # Wait for container to be ready
    msg_info "Waiting for container to be ready..."
    READY=false
    MAX_ATTEMPTS=15
    attempt=1
    wait_time=1

    while [ $attempt -le $MAX_ATTEMPTS ]; do
        if pct exec "$CTID" -- systemctl is-system-running --wait &>/dev/null; then
            READY=true
            break
        fi
        sleep $wait_time
        if [ $wait_time -lt 16 ]; then
            wait_time=$((wait_time * 2))
        fi
        attempt=$((attempt + 1))
    done

    if [ "$READY" = false ]; then
        msg_error "Container failed to become ready"
        exit 1
    fi
    msg_ok "Container is ready"

    # Install Waydroid inside the container
    if ! install_waydroid_in_container "$CTID"; then
        msg_error "Waydroid installation failed"
        exit 1
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

    # Set container description
    description

    # Success message
    msg_ok "Installation Complete!"
    echo -e "\n${GN}═══════════════════════════════════════════════${CL}"
    echo -e "${GN}  Waydroid LXC Successfully Installed!${CL}"
    echo -e "${GN}═══════════════════════════════════════════════${CL}\n"
    echo -e "${BL}Container Details:${CL}"
    echo -e "  CTID: ${GN}${CTID}${CL}"
    echo -e "  Type: ${GN}$([ "$var_unprivileged" = "1" ] && echo "Unprivileged" || echo "Privileged")${CL}"
    echo -e "  IP Address: ${GN}${CONTAINER_IP}${CL}"
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
}

# Run main installation
main "$@"
