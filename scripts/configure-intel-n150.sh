#!/usr/bin/env bash

# Intel N150 Specific Configuration Script
# Run this on the Proxmox HOST to optimize for N150 SoC

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helper-functions.sh"

if ! is_proxmox_host; then
    msg_error "This script must be run on the Proxmox host"
    exit 1
fi

echo -e "${GN}Configuring Proxmox Host for Intel N150${CL}\n"

# Load configuration
CONFIG_FILE="${SCRIPT_DIR}/../config/intel-n150.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    msg_ok "Configuration loaded"
else
    msg_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Check for Intel GPU
msg_info "Checking for Intel GPU..."
if get_intel_gpu_info &> /dev/null; then
    msg_ok "Intel GPU detected:"
    get_intel_gpu_info
else
    msg_error "No Intel GPU detected"
    exit 1
fi

# Load required kernel modules
msg_info "Loading kernel modules..."
for module in "${REQUIRED_MODULES[@]}"; do
    load_kernel_module "$module"
done

# Configure i915 module parameters
msg_info "Configuring i915 module parameters..."
if [ ! -f /etc/modprobe.d/i915.conf ]; then
    echo "options i915 ${I915_PARAMS}" > /etc/modprobe.d/i915.conf
    msg_ok "i915 parameters configured"
    msg_warn "Reboot required for i915 parameters to take effect"
else
    msg_ok "i915 already configured"
fi

# Ensure modules load on boot
msg_info "Configuring modules to load on boot..."
cat > /etc/modules-load.d/waydroid.conf <<EOF
# Waydroid required modules
binder_linux
ashmem_linux
# Intel GPU
i915
EOF
msg_ok "Module autoload configured"

# Check device permissions
msg_info "Checking GPU device permissions..."
for device in "${DEVICE_NODES[@]}"; do
    if [ -e "$device" ]; then
        msg_ok "$device exists"
        ls -la "$device"
    else
        msg_warn "$device not found"
    fi
done

# Create udev rules for GPU devices
msg_info "Creating udev rules..."
cat > /etc/udev/rules.d/99-waydroid-intel.rules <<EOF
# Intel GPU devices for Waydroid LXC
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", MODE="0666"
SUBSYSTEM=="drm", KERNEL=="renderD[0-9]*", MODE="0666"
SUBSYSTEM=="graphics", KERNEL=="fb[0-9]*", MODE="0666"
EOF

udevadm control --reload-rules
udevadm trigger
msg_ok "Udev rules created and reloaded"

# Display current Intel GPU status
msg_info "Intel GPU Status:"
if [ -d /sys/class/drm/card0 ]; then
    echo -e "  Device: /dev/dri/card0"
    if [ -f /sys/class/drm/card0/device/enable ]; then
        echo -e "  Enabled: $(cat /sys/class/drm/card0/device/enable)"
    fi
fi

# Check Intel GPU firmware
msg_info "Checking Intel GPU firmware..."
if command -v dmesg &> /dev/null; then
    if dmesg | grep -i "i915.*firmware" | tail -5; then
        msg_ok "Firmware loaded"
    fi
fi

echo -e "\n${GN}==================================================${CL}"
echo -e "${GN}Intel N150 Configuration Complete${CL}"
echo -e "${GN}==================================================${CL}\n"

msg_info "Summary:"
echo -e "  • Kernel modules loaded and configured for autoload"
echo -e "  • i915 parameters optimized for N150"
echo -e "  • GPU device permissions configured"
echo -e "  • Udev rules created"

echo -e "\n${BL}Recommended Next Steps:${CL}"
echo -e "  1. Reboot the Proxmox host (if i915 was just configured)"
echo -e "  2. Run the installation script: ${GN}./install/install.sh${CL}\n"
