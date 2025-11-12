#!/usr/bin/env bash

# Test script to verify Waydroid LXC setup
# Run this inside the LXC container to verify everything is working

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helper-functions.sh"

echo -e "${GN}==================================================${CL}"
echo -e "${GN}  Waydroid LXC Setup Verification${CL}"
echo -e "${GN}==================================================${CL}\n"

# Check if running in LXC
if ! is_lxc; then
    msg_error "This script should be run inside the LXC container"
    exit 1
fi

# Display system info
show_system_info

# Test 1: Check GPU devices
echo -e "${BL}Test 1: GPU Device Access${CL}"
if check_gpu_access; then
    echo -e "${CM} GPU devices accessible\n"
else
    echo -e "${CROSS} GPU device access failed\n"
fi

# Test 2: Check kernel modules
echo -e "${BL}Test 2: Kernel Modules${CL}"
modules_ok=true
for module in binder_linux ashmem_linux; do
    if check_kernel_module "$module"; then
        echo -e "${CM} $module loaded"
    else
        echo -e "${CROSS} $module not loaded"
        modules_ok=false
    fi
done
if $modules_ok; then
    echo -e "${CM} All required modules loaded\n"
else
    echo -e "${CROSS} Some modules missing\n"
fi

# Test 3: Check Waydroid installation
echo -e "${BL}Test 3: Waydroid Installation${CL}"
if is_waydroid_installed; then
    echo -e "${CM} Waydroid installed"
    echo -e "    Version: $(waydroid --version 2>/dev/null || echo 'unknown')"
    echo -e "    Status: $(get_waydroid_status)\n"
else
    echo -e "${CROSS} Waydroid not installed\n"
fi

# Test 4: Check Wayland compositor
echo -e "${BL}Test 4: Wayland Compositor${CL}"
if command -v sway &> /dev/null; then
    echo -e "${CM} Sway installed"
else
    echo -e "${CROSS} Sway not found"
fi
if command -v weston &> /dev/null; then
    echo -e "${CM} Weston installed"
else
    echo -e "${CROSS} Weston not found"
fi
echo ""

# Test 5: Check VNC
echo -e "${BL}Test 5: VNC Server${CL}"
if command -v wayvnc &> /dev/null; then
    echo -e "${CM} WayVNC installed"
    if systemctl is-active --quiet waydroid-vnc.service; then
        echo -e "${CM} VNC service running"
        test_vnc 5900
    else
        echo -e "${YW}[WARN]${CL} VNC service not running"
    fi
else
    echo -e "${CROSS} WayVNC not installed"
fi
echo ""

# Test 6: Check API
echo -e "${BL}Test 6: Home Assistant API${CL}"
if [ -f /usr/local/bin/waydroid-api.py ]; then
    echo -e "${CM} API script exists"
    if systemctl is-active --quiet waydroid-api.service; then
        echo -e "${CM} API service running"
        test_api 8080
    else
        echo -e "${YW}[WARN]${CL} API service not running"
    fi
else
    echo -e "${CROSS} API script not found"
fi
echo ""

# Test 7: Check services
echo -e "${BL}Test 7: Systemd Services${CL}"
for service in waydroid-container.service waydroid-vnc.service waydroid-api.service; do
    if systemctl list-unit-files | grep -q "$service"; then
        status=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
        active=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        echo -e "${CM} $service: enabled=$status, active=$active"
    else
        echo -e "${CROSS} $service not found"
    fi
done
echo ""

# Summary
echo -e "${GN}==================================================${CL}"
echo -e "${GN}  Verification Complete${CL}"
echo -e "${GN}==================================================${CL}\n"

# Provide recommendations
echo -e "${BL}Next Steps:${CL}"
if ! systemctl is-active --quiet waydroid-vnc.service; then
    echo -e "  • Start VNC: ${GN}systemctl start waydroid-vnc${CL}"
    echo -e "  • Enable VNC: ${GN}systemctl enable waydroid-vnc${CL}"
fi

if ! systemctl is-active --quiet waydroid-api.service; then
    echo -e "  • Start API: ${GN}systemctl start waydroid-api${CL}"
    echo -e "  • Enable API: ${GN}systemctl enable waydroid-api${CL}"
fi

if [ "$(get_waydroid_status)" != "running" ]; then
    echo -e "  • Initialize Waydroid: ${GN}waydroid init -s GAPPS${CL}"
    echo -e "  • Start Waydroid: ${GN}waydroid session start${CL}"
fi

echo -e "\n${BL}Access Information:${CL}"
echo -e "  • VNC: ${GN}$(get_container_ip):5900${CL}"
echo -e "  • API: ${GN}http://$(get_container_ip):8080${CL}\n"
