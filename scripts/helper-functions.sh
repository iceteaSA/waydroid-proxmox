#!/usr/bin/env bash

# Helper functions for Waydroid Proxmox LXC
# Source this file in other scripts: source helper-functions.sh

# Color definitions
export BL="\033[36m"
export RD="\033[01;31m"
export GN="\033[1;92m"
export YW="\033[1;93m"
export CL="\033[m"
export CM="${GN}✓${CL}"
export CROSS="${RD}✗${CL}"

# Logging functions
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

# Check if running on Proxmox host
is_proxmox_host() {
    command -v pveversion &> /dev/null
}

# Check if running inside LXC
is_lxc() {
    [ -f /proc/1/environ ] && grep -q container=lxc /proc/1/environ
}

# Get Intel GPU information
get_intel_gpu_info() {
    if ! command -v lspci &> /dev/null; then
        msg_error "lspci not available"
        return 1
    fi

    lspci | grep -i "VGA.*Intel"
}

# Check if kernel modules are loaded
check_kernel_module() {
    local module=$1
    if lsmod | grep -q "^${module}"; then
        return 0
    else
        return 1
    fi
}

# Load kernel module
load_kernel_module() {
    local module=$1
    if check_kernel_module "$module"; then
        msg_ok "Module $module already loaded"
        return 0
    fi

    msg_info "Loading kernel module: $module"
    if modprobe "$module"; then
        msg_ok "Module $module loaded"
        return 0
    else
        msg_error "Failed to load module: $module"
        return 1
    fi
}

# Check if Waydroid is installed
is_waydroid_installed() {
    command -v waydroid &> /dev/null
}

# Get Waydroid status
get_waydroid_status() {
    if ! is_waydroid_installed; then
        echo "not_installed"
        return
    fi

    if waydroid status 2>&1 | grep -q "RUNNING"; then
        echo "running"
    else
        echo "stopped"
    fi
}

# Check GPU device access
check_gpu_access() {
    local has_access=true

    if [ ! -e /dev/dri/card0 ]; then
        msg_error "/dev/dri/card0 not found"
        has_access=false
    fi

    if [ ! -e /dev/dri/renderD128 ]; then
        msg_error "/dev/dri/renderD128 not found"
        has_access=false
    fi

    if [ ! -r /dev/dri/card0 ] || [ ! -w /dev/dri/card0 ]; then
        msg_error "No read/write access to /dev/dri/card0"
        has_access=false
    fi

    if $has_access; then
        msg_ok "GPU device access verified"
        return 0
    else
        return 1
    fi
}

# Initialize Waydroid
init_waydroid() {
    local force=$1

    if [ -d "/var/lib/waydroid/overlay" ] && [ "$force" != "force" ]; then
        msg_ok "Waydroid already initialized"
        return 0
    fi

    msg_info "Initializing Waydroid (this may take several minutes)..."
    if waydroid init -s GAPPS -f; then
        msg_ok "Waydroid initialized successfully"
        return 0
    else
        msg_error "Failed to initialize Waydroid"
        return 1
    fi
}

# Start Waydroid container
start_waydroid_container() {
    msg_info "Starting Waydroid container..."
    if waydroid container start; then
        msg_ok "Waydroid container started"
        return 0
    else
        msg_error "Failed to start Waydroid container"
        return 1
    fi
}

# Start Waydroid session
start_waydroid_session() {
    msg_info "Starting Waydroid session..."
    waydroid session start &
    sleep 3
    msg_ok "Waydroid session starting"
}

# Get container IP
get_container_ip() {
    hostname -I | awk '{print $1}'
}

# Test VNC connectivity
test_vnc() {
    local port=${1:-5900}
    if netstat -tuln | grep -q ":${port}"; then
        msg_ok "VNC server listening on port $port"
        return 0
    else
        msg_error "VNC server not listening on port $port"
        return 1
    fi
}

# Test API connectivity
test_api() {
    local port=${1:-8080}
    if netstat -tuln | grep -q ":${port}"; then
        msg_ok "API server listening on port $port"
        return 0
    else
        msg_error "API server not listening on port $port"
        return 1
    fi
}

# Display system information
show_system_info() {
    echo -e "\n${BL}=== System Information ===${CL}"
    echo -e "Hostname: $(hostname)"
    echo -e "IP Address: $(get_container_ip)"
    echo -e "OS: $(grep PRETTY_NAME /etc/os-release | cut -d '"' -f 2)"
    echo -e "Kernel: $(uname -r)"

    if get_intel_gpu_info &> /dev/null; then
        echo -e "\n${BL}=== GPU Information ===${CL}"
        get_intel_gpu_info
    fi

    if is_waydroid_installed; then
        echo -e "\n${BL}=== Waydroid Status ===${CL}"
        echo -e "Status: $(get_waydroid_status)"
        if [ -d "/var/lib/waydroid/overlay" ]; then
            echo -e "Initialized: Yes"
        else
            echo -e "Initialized: No"
        fi
    fi
    echo ""
}

# Export functions
export -f msg_info
export -f msg_ok
export -f msg_error
export -f msg_warn
export -f is_proxmox_host
export -f is_lxc
export -f get_intel_gpu_info
export -f check_kernel_module
export -f load_kernel_module
export -f is_waydroid_installed
export -f get_waydroid_status
export -f check_gpu_access
export -f init_waydroid
export -f start_waydroid_container
export -f start_waydroid_session
export -f get_container_ip
export -f test_vnc
export -f test_api
export -f show_system_info
