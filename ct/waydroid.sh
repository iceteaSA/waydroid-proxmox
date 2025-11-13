#!/usr/bin/env bash

# Waydroid One-Command Installer for Proxmox LXC
# Copyright (c) 2025
# License: MIT
# https://github.com/iceteaSA/waydroid-proxmox
#
# Run with:
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/iceteaSA/waydroid-proxmox/main/ct/waydroid.sh)"

set -euo pipefail

# Script version
VERSION="3.0.0"
SCRIPT_NAME="waydroid.sh"

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION DEFAULTS
# ═══════════════════════════════════════════════════════════════════════════

# Container configuration
CTID="${CTID:-}"
HOSTNAME="${HOSTNAME:-waydroid}"
DISK_SIZE="${DISK_SIZE:-16}"
CORES="${CORES:-2}"
RAM="${RAM:-2048}"
BRIDGE="${BRIDGE:-vmbr0}"
STORAGE="${STORAGE:-local-lxc}"
OS_TEMPLATE="debian-12-standard"
UNPRIVILEGED=0

# GPU configuration
GPU_TYPE="${GPU_TYPE:-}"
USE_GAPPS="${USE_GAPPS:-yes}"
SOFTWARE_RENDERING="${SOFTWARE_RENDERING:-0}"
GPU_DEVICE="${GPU_DEVICE:-}"
RENDER_NODE="${RENDER_NODE:-}"

# Script behavior
INTERACTIVE="${INTERACTIVE:-yes}"
VERBOSE="${VERBOSE:-no}"
UPDATE_MODE="${UPDATE_MODE:-no}"
SKIP_PREFLIGHT="${SKIP_PREFLIGHT:-no}"

# ═══════════════════════════════════════════════════════════════════════════
# COMMUNITY SCRIPT INTEGRATION (tteck style)
# ═══════════════════════════════════════════════════════════════════════════

# Try to source community script functions if available
if [ -n "${FUNCTIONS_FILE_PATH:-}" ] && [ -f "$FUNCTIONS_FILE_PATH" ]; then
    # Validate file for security
    if [ "$(stat -c '%u' "$FUNCTIONS_FILE_PATH" 2>/dev/null || echo 999)" -eq 0 ]; then
        if [ ! -w "$FUNCTIONS_FILE_PATH" ] || [ "$(stat -c '%a' "$FUNCTIONS_FILE_PATH" | cut -c3)" -lt 6 ]; then
            # shellcheck disable=SC1090
            source "$FUNCTIONS_FILE_PATH" 2>/dev/null || true
            # Initialize community functions if available
            command -v color &>/dev/null && color
            command -v verb_ip6 &>/dev/null && verb_ip6
            command -v catch_errors &>/dev/null && catch_errors
            USING_COMMUNITY_FUNCTIONS=true
        fi
    fi
fi

# Fallback color definitions if not provided by community functions
if [ -z "${BL:-}" ]; then
    BL="\033[36m"
    RD="\033[01;31m"
    GN="\033[1;92m"
    YW="\033[1;93m"
    CL="\033[m"
    CM="${GN}✓${CL}"
    CROSS="${RD}✗${CL}"
fi

# Fallback message functions if not provided by community functions
if ! command -v msg_info &>/dev/null; then
    msg_info() { echo -e "${BL}[INFO]${CL} $1"; }
    msg_ok() { echo -e "${CM} $1"; }
    msg_error() { echo -e "${CROSS} $1"; }
    msg_warn() { echo -e "${YW}[WARN]${CL} $1"; }
fi

# Silent execution helper
if ! command -v silent &>/dev/null; then
    silent() {
        if [ "$VERBOSE" = "yes" ]; then
            "$@"
        else
            "$@" &>/dev/null
        fi
    }
fi

# ═══════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

# Show help message
show_help() {
    cat <<EOF
${GN}═══════════════════════════════════════════════════════════════════════════
  Waydroid One-Command Installer for Proxmox LXC v${VERSION}
═══════════════════════════════════════════════════════════════════════════${CL}

${BL}DESCRIPTION:${CL}
  Creates and configures a Proxmox LXC container with Waydroid, VNC access,
  and Home Assistant API integration. Supports both interactive and
  non-interactive modes.

${BL}USAGE:${CL}
  ${GN}# Interactive mode (recommended):${CL}
  bash $SCRIPT_NAME

  ${GN}# One-liner from GitHub:${CL}
  bash -c "\$(curl -fsSL https://raw.githubusercontent.com/iceteaSA/waydroid-proxmox/main/ct/waydroid.sh)"

  ${GN}# Non-interactive mode:${CL}
  bash $SCRIPT_NAME --ctid 200 --gpu intel --gapps --disk 20 --ram 4096

  ${GN}# Update existing container:${CL}
  pct exec <CTID> -- bash -c "\$(curl -fsSL https://raw.githubusercontent.com/iceteaSA/waydroid-proxmox/main/ct/waydroid.sh)" -- --update

${BL}OPTIONS:${CL}
  ${GN}Container Configuration:${CL}
    --ctid <id>           Container ID (default: auto-detect next available)
    --hostname <name>     Container hostname (default: waydroid)
    --disk <size>         Disk size in GB (default: 16)
    --cpu <cores>         CPU cores (default: 2)
    --ram <mb>            RAM in MB (default: 2048)
    --storage <pool>      Storage pool (default: local-lxc)
    --bridge <name>       Network bridge (default: vmbr0)
    --privileged          Use privileged container (default, for GPU)
    --unprivileged        Use unprivileged container (software rendering only)

  ${GN}GPU Configuration:${CL}
    --gpu <type>          GPU type: intel, amd, nvidia, software
                          (default: interactive prompt)
    --gpu-device <dev>    Specific GPU device (e.g., /dev/dri/card0)
    --render-node <dev>   Specific render node (e.g., /dev/dri/renderD128)
    --software-rendering  Force software rendering (no GPU passthrough)

  ${GN}Android Configuration:${CL}
    --gapps               Install Google Apps/Play Store (default)
    --no-gapps            Skip Google Apps installation

  ${GN}Script Behavior:${CL}
    --non-interactive     Run without prompts (use env vars/args only)
    --update              Update existing Waydroid installation
    --verbose             Show detailed command output
    --skip-preflight      Skip preflight checks (not recommended)
    -h, --help            Show this help message
    --version             Show version information

${BL}ENVIRONMENT VARIABLES:${CL}
  You can also set these environment variables:
    CTID, HOSTNAME, DISK_SIZE, CORES, RAM, STORAGE, BRIDGE
    GPU_TYPE, USE_GAPPS, SOFTWARE_RENDERING, GPU_DEVICE, RENDER_NODE
    INTERACTIVE, VERBOSE, UPDATE_MODE, SKIP_PREFLIGHT

${BL}EXAMPLES:${CL}
  ${GN}# Create container with Intel GPU and Google Apps:${CL}
  bash $SCRIPT_NAME --gpu intel --gapps

  ${GN}# Create with specific CTID and more resources:${CL}
  bash $SCRIPT_NAME --ctid 200 --cpu 4 --ram 4096 --disk 32

  ${GN}# Unprivileged container with software rendering:${CL}
  bash $SCRIPT_NAME --unprivileged --no-gapps

  ${GN}# Update Waydroid in existing container (run inside container):${CL}
  bash $SCRIPT_NAME --update

${BL}POST-INSTALLATION:${CL}
  After installation completes:
    1. Container will start automatically
    2. Connect via VNC: <container-ip>:5900
    3. API endpoint: http://<container-ip>:8080
    4. API token: /etc/waydroid-api/token (inside container)

${BL}DOCUMENTATION:${CL}
  GitHub: https://github.com/iceteaSA/waydroid-proxmox
  Issues: https://github.com/iceteaSA/waydroid-proxmox/issues

EOF
    exit 0
}

# Show version
show_version() {
    echo "Waydroid Proxmox Installer v${VERSION}"
    exit 0
}

# Detect environment
is_proxmox_host() {
    command -v pveversion &>/dev/null
}

is_lxc_container() {
    [ -f /proc/1/environ ] && grep -q container=lxc /proc/1/environ
}

# Get next available CTID
get_next_ctid() {
    if is_proxmox_host; then
        pvesh get /cluster/nextid 2>/dev/null || echo "100"
    else
        echo "100"
    fi
}

# Cleanup function for error handling
cleanup_on_error() {
    local exit_code=$?
    msg_error "Script failed at line $LINENO with exit code $exit_code"

    if is_proxmox_host && [ -n "${CTID:-}" ]; then
        if pct status "$CTID" &>/dev/null; then
            echo ""
            msg_warn "Container $CTID was partially created"
            if [ "$INTERACTIVE" = "yes" ]; then
                read -p "Remove failed container? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    msg_info "Removing container $CTID..."
                    pct stop "$CTID" 2>/dev/null || true
                    pct destroy "$CTID" 2>/dev/null || true
                    msg_ok "Container removed"
                fi
            fi
        fi
    fi

    exit "$exit_code"
}

trap cleanup_on_error ERR

# ═══════════════════════════════════════════════════════════════════════════
# ARGUMENT PARSING
# ═══════════════════════════════════════════════════════════════════════════

parse_arguments() {
    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help) show_help ;;
            --version) show_version ;;
            --ctid) CTID="$2"; shift ;;
            --hostname) HOSTNAME="$2"; shift ;;
            --disk) DISK_SIZE="$2"; shift ;;
            --cpu) CORES="$2"; shift ;;
            --ram) RAM="$2"; shift ;;
            --storage) STORAGE="$2"; shift ;;
            --bridge) BRIDGE="$2"; shift ;;
            --privileged) UNPRIVILEGED=0 ;;
            --unprivileged) UNPRIVILEGED=1; SOFTWARE_RENDERING=1 ;;
            --gpu) GPU_TYPE="$2"; shift ;;
            --gpu-device) GPU_DEVICE="$2"; shift ;;
            --render-node) RENDER_NODE="$2"; shift ;;
            --software-rendering) SOFTWARE_RENDERING=1 ;;
            --gapps) USE_GAPPS="yes" ;;
            --no-gapps) USE_GAPPS="no" ;;
            --non-interactive) INTERACTIVE="no" ;;
            --update) UPDATE_MODE="yes" ;;
            --verbose) VERBOSE="yes" ;;
            --skip-preflight) SKIP_PREFLIGHT="yes" ;;
            *) msg_warn "Unknown option: $1" ;;
        esac
        shift
    done
}

# ═══════════════════════════════════════════════════════════════════════════
# VALIDATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

validate_gpu_type() {
    local gpu="$1"
    if [[ ! "$gpu" =~ ^(intel|amd|nvidia|software)$ ]]; then
        msg_error "Invalid GPU type: $gpu (must be: intel, amd, nvidia, or software)"
        return 1
    fi
    return 0
}

validate_ctid() {
    local ctid="$1"
    if ! [[ "$ctid" =~ ^[0-9]+$ ]]; then
        msg_error "Invalid CTID: must be numeric"
        return 1
    fi
    if [ "$ctid" -lt 100 ] || [ "$ctid" -gt 999999999 ]; then
        msg_error "Invalid CTID: must be between 100 and 999999999"
        return 1
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# PREFLIGHT CHECKS
# ═══════════════════════════════════════════════════════════════════════════

preflight_checks() {
    [ "$SKIP_PREFLIGHT" = "yes" ] && return 0

    msg_info "Running preflight checks..."
    local checks_passed=true

    # Check required commands on host
    if is_proxmox_host; then
        for cmd in pct pvesm pveam modprobe lspci; do
            if ! command -v "$cmd" &>/dev/null; then
                msg_error "Required command not found: $cmd"
                checks_passed=false
            fi
        done

        # Check storage
        if ! pvesm status | grep -q "^${STORAGE}"; then
            msg_error "Storage '${STORAGE}' does not exist"
            msg_info "Available storage:"
            pvesm status | awk 'NR>1 {print "  - " $1}'
            checks_passed=false
        fi

        # Check network bridge
        if [ ! -d "/sys/class/net/${BRIDGE}" ]; then
            msg_error "Network bridge '${BRIDGE}' does not exist"
            checks_passed=false
        fi

        # Check CTID availability
        if [ -n "$CTID" ] && pct status "$CTID" &>/dev/null; then
            msg_error "Container $CTID already exists"
            checks_passed=false
        fi
    fi

    if [ "$checks_passed" = false ]; then
        msg_error "Preflight checks failed"
        return 1
    fi

    msg_ok "Preflight checks passed"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# INTERACTIVE PROMPTS
# ═══════════════════════════════════════════════════════════════════════════

interactive_setup() {
    [ "$INTERACTIVE" = "no" ] && return 0

    echo ""
    echo -e "${GN}═══════════════════════════════════════════════════════════════════════════${CL}"
    echo -e "${GN}  Waydroid LXC Installation for Proxmox VE${CL}"
    echo -e "${GN}═══════════════════════════════════════════════════════════════════════════${CL}"
    echo ""

    # Container type
    if [ -z "$UNPRIVILEGED" ] || [ "$UNPRIVILEGED" = "0" ]; then
        echo -e "${BL}Container Configuration:${CL}"
        echo -e "  1) Privileged (recommended for GPU passthrough)"
        echo -e "  2) Unprivileged (more secure, software rendering only)"
        read -p "Select container type [1]: " -r CONTAINER_TYPE
        CONTAINER_TYPE=${CONTAINER_TYPE:-1}

        if [ "$CONTAINER_TYPE" = "2" ]; then
            UNPRIVILEGED=1
            SOFTWARE_RENDERING=1
            msg_warn "Unprivileged container selected - will use software rendering"
        fi
        echo ""
    fi

    # GPU type (only if privileged)
    if [ "$UNPRIVILEGED" = "0" ] && [ -z "$GPU_TYPE" ]; then
        echo -e "${BL}GPU Configuration:${CL}"
        echo -e "  1) Intel (recommended - hardware acceleration)"
        echo -e "  2) AMD (hardware acceleration)"
        echo -e "  3) NVIDIA (software rendering only)"
        echo -e "  4) Software rendering (no GPU passthrough)"
        read -p "Select GPU type [1]: " -r GPU_CHOICE
        GPU_CHOICE=${GPU_CHOICE:-1}

        case $GPU_CHOICE in
            1) GPU_TYPE="intel" ;;
            2) GPU_TYPE="amd" ;;
            3) GPU_TYPE="nvidia"; SOFTWARE_RENDERING=1 ;;
            4) GPU_TYPE="software"; SOFTWARE_RENDERING=1 ;;
            *) GPU_TYPE="intel" ;;
        esac
        msg_info "Selected: $GPU_TYPE"
        echo ""
    fi

    # GPU detection for hardware acceleration
    if [ "$SOFTWARE_RENDERING" = "0" ] && is_proxmox_host; then
        msg_info "Detecting ${GPU_TYPE^^} GPU..."

        case $GPU_TYPE in
            intel)
                if lspci | grep -i "VGA.*Intel" &>/dev/null; then
                    msg_ok "Intel GPU detected"
                    lspci | grep -i "VGA.*Intel"
                else
                    msg_warn "Intel GPU not detected"
                    read -p "Continue with software rendering? (y/N): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        SOFTWARE_RENDERING=1
                        GPU_TYPE="software"
                    else
                        exit 1
                    fi
                fi
                ;;
            amd)
                if lspci | grep -i "VGA.*AMD\|VGA.*Radeon" &>/dev/null; then
                    msg_ok "AMD GPU detected"
                    lspci | grep -i "VGA.*AMD\|VGA.*Radeon"
                else
                    msg_warn "AMD GPU not detected"
                    read -p "Continue with software rendering? (y/N): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        SOFTWARE_RENDERING=1
                        GPU_TYPE="software"
                    else
                        exit 1
                    fi
                fi
                ;;
        esac
        echo ""

        # GPU device selection
        if [ "$SOFTWARE_RENDERING" = "0" ] && [ -d /dev/dri ]; then
            mapfile -t CARDS < <(ls /dev/dri/card* 2>/dev/null | sort || true)
            mapfile -t RENDERS < <(ls /dev/dri/renderD* 2>/dev/null | sort || true)

            if [ ${#CARDS[@]} -gt 1 ]; then
                echo -e "${BL}Multiple GPU card devices detected:${CL}"
                for i in "${!CARDS[@]}"; do
                    echo -e "  $((i+1))) ${CARDS[$i]}"
                done
                read -p "Select card device [1]: " -r CARD_CHOICE
                CARD_CHOICE=${CARD_CHOICE:-1}
                GPU_DEVICE="${CARDS[$((CARD_CHOICE-1))]}"
                msg_ok "Selected: $GPU_DEVICE"
            elif [ ${#CARDS[@]} -eq 1 ]; then
                GPU_DEVICE="${CARDS[0]}"
                msg_ok "Using card device: $GPU_DEVICE"
            fi

            if [ ${#RENDERS[@]} -gt 1 ]; then
                echo -e "${BL}Multiple render nodes detected:${CL}"
                for i in "${!RENDERS[@]}"; do
                    echo -e "  $((i+1))) ${RENDERS[$i]}"
                done
                read -p "Select render node [1]: " -r RENDER_CHOICE
                RENDER_CHOICE=${RENDER_CHOICE:-1}
                RENDER_NODE="${RENDERS[$((RENDER_CHOICE-1))]}"
                msg_ok "Selected: $RENDER_NODE"
            elif [ ${#RENDERS[@]} -eq 1 ]; then
                RENDER_NODE="${RENDERS[0]}"
                msg_ok "Using render node: $RENDER_NODE"
            fi
            echo ""
        fi
    fi

    # GAPPS selection
    if [ "$INTERACTIVE" = "yes" ]; then
        echo -e "${BL}Android Configuration:${CL}"
        read -p "Install Google Apps (Play Store, Gmail, etc.)? (Y/n): " -r GAPPS_CHOICE
        GAPPS_CHOICE=${GAPPS_CHOICE:-y}

        if [[ $GAPPS_CHOICE =~ ^[Nn]$ ]]; then
            USE_GAPPS="no"
            msg_info "Will install without GAPPS"
        else
            USE_GAPPS="yes"
            msg_info "Will install with GAPPS"
        fi
        echo ""
    fi

    # Show summary
    echo -e "${GN}═══════════════════════════════════════════════════════════════════════════${CL}"
    echo -e "${GN}  Installation Summary${CL}"
    echo -e "${GN}═══════════════════════════════════════════════════════════════════════════${CL}"
    echo -e "${BL}Container:${CL}"
    echo -e "  CTID: ${GN}${CTID}${CL}"
    echo -e "  Type: ${GN}$([ "$UNPRIVILEGED" = "1" ] && echo "Unprivileged" || echo "Privileged")${CL}"
    echo -e "  Cores: ${GN}${CORES}${CL}"
    echo -e "  RAM: ${GN}${RAM}MB${CL}"
    echo -e "  Disk: ${GN}${DISK_SIZE}GB${CL}"
    echo -e "${BL}GPU:${CL}"
    echo -e "  Type: ${GN}${GPU_TYPE}${CL}"
    echo -e "  Rendering: ${GN}$([ "$SOFTWARE_RENDERING" = "1" ] && echo "Software" || echo "Hardware Accelerated")${CL}"
    [ -n "$GPU_DEVICE" ] && echo -e "  Device: ${GN}${GPU_DEVICE}${CL}"
    [ -n "$RENDER_NODE" ] && echo -e "  Render: ${GN}${RENDER_NODE}${CL}"
    echo -e "${BL}Android:${CL}"
    echo -e "  GAPPS: ${GN}${USE_GAPPS}${CL}"
    echo -e "${GN}═══════════════════════════════════════════════════════════════════════════${CL}"
    echo ""

    read -p "Continue with installation? (Y/n): " -r CONFIRM
    CONFIRM=${CONFIRM:-y}
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        msg_info "Installation cancelled"
        exit 0
    fi
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════
# CONTAINER CREATION (Proxmox Host)
# ═══════════════════════════════════════════════════════════════════════════

create_container() {
    msg_info "Creating LXC container ${CTID}..."

    # Download template if needed
    local template_path="/var/lib/vz/template/cache/${OS_TEMPLATE}_amd64.tar.zst"
    if [ ! -f "$template_path" ]; then
        msg_info "Downloading Debian 12 template..."
        silent pveam update
        silent pveam download "$STORAGE" "${OS_TEMPLATE}_amd64.tar.zst"
        msg_ok "Template downloaded"
    fi

    # Create container
    pct create "$CTID" "$template_path" \
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
        --onboot 1

    msg_ok "Container created"
}

configure_container() {
    local config_file="/etc/pve/lxc/${CTID}.conf"

    msg_info "Configuring container..."

    # Base Waydroid configuration
    cat >> "$config_file" <<EOF

# Waydroid Configuration
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: a
lxc.mount.auto: proc:rw sys:rw cgroup:rw
lxc.autodev: 1
EOF

    # GPU passthrough configuration
    if [ "$SOFTWARE_RENDERING" = "0" ]; then
        cat >> "$config_file" <<EOF

# GPU Passthrough
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 29:0 rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir 0 0
lxc.mount.entry: /dev/fb0 dev/fb0 none bind,optional,create=file 0 0
EOF

        # Specific devices
        if [ -n "$GPU_DEVICE" ]; then
            echo "lxc.mount.entry: $GPU_DEVICE dev/dri/$(basename "$GPU_DEVICE") none bind,optional,create=file 0 0" >> "$config_file"
        fi

        if [ -n "$RENDER_NODE" ]; then
            echo "lxc.mount.entry: $RENDER_NODE dev/dri/$(basename "$RENDER_NODE") none bind,optional,create=file 0 0" >> "$config_file"
        fi
    fi

    # Privileged container specific config
    if [ "$UNPRIVILEGED" = "0" ]; then
        echo "lxc.cap.drop:" >> "$config_file"
    fi

    msg_ok "Container configured"
}

setup_host_kernel_modules() {
    msg_info "Loading kernel modules on host..."

    modprobe binder_linux 2>/dev/null || msg_warn "binder_linux module not available"
    modprobe ashmem_linux 2>/dev/null || msg_warn "ashmem_linux module not available"

    # Make persistent
    cat > /etc/modules-load.d/waydroid.conf <<EOF
binder_linux
ashmem_linux
EOF

    msg_ok "Kernel modules configured"
}

start_container() {
    msg_info "Starting container..."
    pct start "$CTID"

    # Wait for container to be ready
    local max_wait=60
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if pct exec "$CTID" -- systemctl is-system-running --wait &>/dev/null; then
            msg_ok "Container is ready"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    msg_error "Container failed to become ready"
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════
# WAYDROID INSTALLATION (Inside Container)
# ═══════════════════════════════════════════════════════════════════════════

install_dependencies() {
    msg_info "Installing system dependencies..."

    silent apt-get update
    silent apt-get upgrade -y

    silent apt-get install -y \
        curl sudo gnupg ca-certificates lsb-release \
        software-properties-common wget unzip \
        wayland-protocols weston sway xwayland \
        python3 python3-pip python3-venv git net-tools

    msg_ok "Dependencies installed"
}

install_gpu_drivers() {
    [ "$SOFTWARE_RENDERING" = "1" ] && return 0

    msg_info "Installing GPU drivers for ${GPU_TYPE}..."

    case $GPU_TYPE in
        intel)
            silent apt-get install -y \
                intel-media-va-driver i965-va-driver \
                mesa-va-drivers mesa-vulkan-drivers libgl1-mesa-dri
            ;;
        amd)
            silent apt-get install -y \
                mesa-va-drivers mesa-vulkan-drivers \
                libgl1-mesa-dri firmware-amd-graphics
            ;;
        *)
            msg_info "No specific GPU drivers for ${GPU_TYPE}"
            ;;
    esac

    msg_ok "GPU drivers installed"
}

install_waydroid() {
    msg_info "Adding Waydroid repository..."

    # Download and verify GPG key
    local temp_key="/tmp/waydroid-gpg-$$.key"
    curl -fsSL --connect-timeout 30 --max-time 60 \
        https://repo.waydro.id/waydroid.gpg -o "$temp_key"

    gpg --dearmor < "$temp_key" > /usr/share/keyrings/waydroid-archive-keyring.gpg
    rm -f "$temp_key"

    echo "deb [signed-by=/usr/share/keyrings/waydroid-archive-keyring.gpg] https://repo.waydro.id/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/waydroid.list

    silent apt-get update
    msg_ok "Waydroid repository added"

    msg_info "Installing Waydroid..."
    silent apt-get install -y waydroid
    msg_ok "Waydroid installed"

    msg_info "Installing WayVNC..."
    silent apt-get install -y wayvnc tigervnc-viewer tigervnc-common
    msg_ok "WayVNC installed"
}

configure_gpu_access() {
    [ "$SOFTWARE_RENDERING" = "1" ] && return 0

    msg_info "Configuring GPU access..."

    groupadd -f render
    usermod -aG render root
    usermod -aG video root

    mkdir -p /var/lib/waydroid/lxc/waydroid/

    case $GPU_TYPE in
        intel|amd)
            cat > /etc/udev/rules.d/99-waydroid-gpu.rules <<EOF
# GPU devices for Waydroid
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", TAG+="waydroid", GROUP="render", MODE="0660"
SUBSYSTEM=="drm", KERNEL=="renderD*", TAG+="waydroid", GROUP="render", MODE="0660"
EOF
            ;;
    esac

    msg_ok "GPU access configured"
}

setup_vnc() {
    msg_info "Setting up VNC..."

    mkdir -p /root/.config/wayvnc

    # Generate VNC password
    local vnc_password
    vnc_password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
    echo "$vnc_password" > /root/.config/wayvnc/password
    chmod 600 /root/.config/wayvnc/password

    cat > /root/.config/wayvnc/config <<EOF
address=0.0.0.0
port=5900
enable_auth=true
username=waydroid
password_file=/root/.config/wayvnc/password
max_rate=60
EOF

    # Save password for user
    echo "$vnc_password" > /root/vnc-password.txt
    chmod 600 /root/vnc-password.txt

    msg_ok "VNC configured (password: /root/vnc-password.txt)"
}

create_startup_script() {
    msg_info "Creating startup scripts..."

    cat > /usr/local/bin/start-waydroid.sh <<'EOFSCRIPT'
#!/bin/bash
# Start Waydroid with VNC access

export XDG_RUNTIME_DIR=/run/user/0
export WAYLAND_DISPLAY=wayland-0

# GPU environment variables
GPU_TYPE="${GPU_TYPE:-intel}"
SOFTWARE_RENDERING="${SOFTWARE_RENDERING:-0}"

if [ "$SOFTWARE_RENDERING" = "0" ]; then
    case $GPU_TYPE in
        intel)
            export MESA_LOADER_DRIVER_OVERRIDE=iris
            export LIBVA_DRIVER_NAME=iHD
            ;;
        amd)
            export MESA_LOADER_DRIVER_OVERRIDE=radeonsi
            export LIBVA_DRIVER_NAME=radeonsi
            ;;
    esac
else
    export LIBGL_ALWAYS_SOFTWARE=1
fi

mkdir -p $XDG_RUNTIME_DIR

# Start compositor
sway &
SWAY_PID=$!
sleep 3

# Start VNC
wayvnc 0.0.0.0 5900 &
WAYVNC_PID=$!

# Initialize Waydroid if needed
if [ ! -d "/var/lib/waydroid/overlay" ]; then
    echo "Initializing Waydroid..."
    if [ "${USE_GAPPS:-yes}" = "yes" ]; then
        waydroid init -s GAPPS -f || exit 1
    else
        waydroid init -f || exit 1
    fi
fi

# Start Waydroid
waydroid container start || exit 1
waydroid session start &

echo "Waydroid started. VNC on port 5900"
echo "Sway PID: $SWAY_PID, WayVNC PID: $WAYVNC_PID"

wait
EOFSCRIPT

    chmod +x /usr/local/bin/start-waydroid.sh

    # Substitute actual values
    sed -i "s/GPU_TYPE=\"\${GPU_TYPE:-intel}\"/GPU_TYPE=\"${GPU_TYPE}\"/" /usr/local/bin/start-waydroid.sh
    sed -i "s/SOFTWARE_RENDERING=\"\${SOFTWARE_RENDERING:-0}\"/SOFTWARE_RENDERING=\"${SOFTWARE_RENDERING}\"/" /usr/local/bin/start-waydroid.sh
    sed -i "s/USE_GAPPS:-yes}/USE_GAPPS:-${USE_GAPPS}}/" /usr/local/bin/start-waydroid.sh

    msg_ok "Startup scripts created"
}

create_systemd_services() {
    msg_info "Creating systemd services..."

    # VNC service
    cat > /etc/systemd/system/waydroid-vnc.service <<EOF
[Unit]
Description=Waydroid with VNC Access
After=network.target
Wants=waydroid-container.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/local/bin/start-waydroid.sh
Restart=on-failure
RestartSec=15
TimeoutStartSec=120
TimeoutStopSec=30
User=root
Environment="XDG_RUNTIME_DIR=/run/user/0"
Environment="WAYLAND_DISPLAY=wayland-0"
WatchdogSec=60
MemoryHigh=3G
MemoryMax=4G
CPUQuota=200%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable waydroid-vnc.service

    msg_ok "VNC service created"
}

# Install API (reusing existing waydroid-api.py from waydroid-lxc.sh)
install_api() {
    msg_info "Installing Home Assistant API..."

    # Create the API script (copy from existing implementation)
    local api_script="/usr/local/bin/waydroid-api.py"

    # Download from GitHub if not in update mode
    if [ "$UPDATE_MODE" = "no" ] || [ ! -f "$api_script" ]; then
        curl -fsSL -o "$api_script" \
            "https://raw.githubusercontent.com/iceteaSA/waydroid-proxmox/main/api/waydroid-api.py" 2>/dev/null || {
            # Fallback: create basic API
            cat > "$api_script" <<'EOFAPI'
#!/usr/bin/env python3
"""Basic Waydroid API"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import subprocess
import logging
import os
import secrets

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

API_TOKEN_FILE = '/etc/waydroid-api/token'

class WaydroidAPIHandler(BaseHTTPRequestHandler):
    def _check_auth(self):
        if not os.path.exists(API_TOKEN_FILE):
            return True
        with open(API_TOKEN_FILE, 'r') as f:
            valid_token = f.read().strip()
        auth_header = self.headers.get('Authorization', '')
        if auth_header.startswith('Bearer '):
            return secrets.compare_digest(auth_header[7:], valid_token)
        return False

    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'healthy'}).encode())
        elif self.path == '/status' and self._check_auth():
            r = subprocess.run(['waydroid', 'status'], capture_output=True, text=True)
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'running' if r.returncode == 0 else 'stopped'}).encode())
        else:
            self.send_response(401 if not self._check_auth() else 404)
            self.end_headers()

def run_server(port=8080):
    os.makedirs(os.path.dirname(API_TOKEN_FILE), exist_ok=True)
    if not os.path.exists(API_TOKEN_FILE):
        token = secrets.token_urlsafe(32)
        with open(API_TOKEN_FILE, 'w') as f:
            f.write(token)
        os.chmod(API_TOKEN_FILE, 0o600)
        logger.info(f"Generated API token: {token}")

    httpd = HTTPServer(('0.0.0.0', port), WaydroidAPIHandler)
    logger.info(f'Waydroid API on port {port}')
    httpd.serve_forever()

if __name__ == '__main__':
    run_server()
EOFAPI
        }
    fi

    chmod +x "$api_script"

    # API service
    cat > /etc/systemd/system/waydroid-api.service <<EOF
[Unit]
Description=Waydroid Home Assistant API
After=waydroid-vnc.service network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $api_script
Restart=always
RestartSec=10
TimeoutStartSec=30
User=root
WatchdogSec=30
MemoryHigh=256M
MemoryMax=512M

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable waydroid-api.service

    msg_ok "API installed"
}

start_services() {
    msg_info "Starting services..."

    systemctl start waydroid-vnc.service
    systemctl start waydroid-api.service

    # Wait for services to be ready
    sleep 5

    if systemctl is-active --quiet waydroid-vnc.service; then
        msg_ok "Waydroid VNC service started"
    else
        msg_warn "Waydroid VNC service may not be running"
    fi

    if systemctl is-active --quiet waydroid-api.service; then
        msg_ok "API service started"
    else
        msg_warn "API service may not be running"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# POST-INSTALLATION
# ═══════════════════════════════════════════════════════════════════════════

show_completion_message() {
    local container_ip
    if is_lxc_container; then
        container_ip=$(hostname -I | awk '{print $1}')
    else
        container_ip=$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}')
    fi
    container_ip=${container_ip:-<container-ip>}

    # Get API token
    local api_token="<see /etc/waydroid-api/token>"
    if [ -f /etc/waydroid-api/token ]; then
        api_token=$(cat /etc/waydroid-api/token)
    fi

    # Get VNC password
    local vnc_password="<see /root/vnc-password.txt>"
    if [ -f /root/vnc-password.txt ]; then
        vnc_password=$(cat /root/vnc-password.txt)
    fi

    echo ""
    echo -e "${GN}═══════════════════════════════════════════════════════════════════════════${CL}"
    echo -e "${GN}  Waydroid Installation Complete!${CL}"
    echo -e "${GN}═══════════════════════════════════════════════════════════════════════════${CL}"
    echo ""
    echo -e "${BL}Container Details:${CL}"
    echo -e "  CTID: ${GN}${CTID}${CL}"
    echo -e "  IP Address: ${GN}${container_ip}${CL}"
    echo -e "  Hostname: ${GN}${HOSTNAME}${CL}"
    echo ""
    echo -e "${BL}Access Information:${CL}"
    echo -e "  ${GN}VNC:${CL}"
    echo -e "    Address: ${GN}${container_ip}:5900${CL}"
    echo -e "    Username: ${GN}waydroid${CL}"
    echo -e "    Password: ${GN}${vnc_password}${CL}"
    echo ""
    echo -e "  ${GN}Home Assistant API:${CL}"
    echo -e "    Endpoint: ${GN}http://${container_ip}:8080${CL}"
    echo -e "    Token: ${GN}${api_token}${CL}"
    echo ""
    echo -e "${BL}Configuration:${CL}"
    echo -e "  GPU: ${GN}${GPU_TYPE}${CL}"
    echo -e "  Rendering: ${GN}$([ "$SOFTWARE_RENDERING" = "1" ] && echo "Software" || echo "Hardware Accelerated")${CL}"
    echo -e "  GAPPS: ${GN}${USE_GAPPS}${CL}"
    echo ""
    echo -e "${BL}Next Steps:${CL}"
    if is_proxmox_host; then
        echo -e "  1. Connect via VNC: ${GN}${container_ip}:5900${CL}"
        echo -e "  2. Wait for Android to boot (first boot takes 2-3 minutes)"
        [ "$USE_GAPPS" = "yes" ] && echo -e "  3. Sign in with your Google account"
        echo -e "  4. Test API: ${GN}curl http://${container_ip}:8080/health${CL}"
    else
        echo -e "  Services are running automatically"
        echo -e "  Connect via VNC to access Android UI"
    fi
    echo ""
    echo -e "${BL}Home Assistant Integration Example:${CL}"
    cat <<'EOFHA'
  POST http://${container_ip}:8080/app/launch
  Headers:
    Authorization: Bearer ${api_token}
  Body:
    {"package": "com.android.settings"}
EOFHA
    echo ""
    echo -e "${BL}Documentation:${CL}"
    echo -e "  GitHub: ${GN}https://github.com/iceteaSA/waydroid-proxmox${CL}"
    echo ""
    echo -e "${GN}═══════════════════════════════════════════════════════════════════════════${CL}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION FLOW
# ═══════════════════════════════════════════════════════════════════════════

main() {
    # Parse arguments
    parse_arguments "$@"

    # Detect environment and set defaults
    if is_proxmox_host; then
        # Running on Proxmox host - will create container
        msg_info "Running on Proxmox VE host"

        # Get CTID if not specified
        if [ -z "$CTID" ]; then
            CTID=$(get_next_ctid)
            msg_info "Auto-detected next CTID: $CTID"
        fi

        # Validate CTID
        validate_ctid "$CTID" || exit 1

        # Set GPU type if not specified
        if [ -z "$GPU_TYPE" ]; then
            GPU_TYPE="intel"
        fi

        # Run preflight checks
        preflight_checks || exit 1

        # Interactive prompts if enabled
        interactive_setup

        # Create and configure container
        create_container
        configure_container
        setup_host_kernel_modules
        start_container

        # Copy this script into container and execute it there
        msg_info "Installing Waydroid inside container..."

        # Create temporary script in container
        pct exec "$CTID" -- bash -c "cat > /tmp/waydroid-install.sh" < "$0"

        # Execute inside container with appropriate flags
        pct exec "$CTID" -- bash /tmp/waydroid-install.sh \
            --non-interactive \
            --gpu "$GPU_TYPE" \
            $([ "$USE_GAPPS" = "yes" ] && echo "--gapps" || echo "--no-gapps") \
            $([ "$SOFTWARE_RENDERING" = "1" ] && echo "--software-rendering") \
            $([ "$VERBOSE" = "yes" ] && echo "--verbose")

        # Clean up
        pct exec "$CTID" -- rm -f /tmp/waydroid-install.sh

        # Show completion message
        show_completion_message

    elif is_lxc_container; then
        # Running inside LXC container - install Waydroid
        msg_info "Running inside LXC container"

        if [ "$UPDATE_MODE" = "yes" ]; then
            msg_info "Update mode - will refresh Waydroid installation"
        fi

        # Ensure we have a GPU type set
        if [ -z "$GPU_TYPE" ]; then
            GPU_TYPE="software"
            SOFTWARE_RENDERING=1
        fi

        # Validate GPU type if specified
        if [ -n "$GPU_TYPE" ]; then
            validate_gpu_type "$GPU_TYPE" || exit 1
        fi

        # Install everything
        install_dependencies
        install_gpu_drivers
        install_waydroid
        configure_gpu_access
        setup_vnc
        create_startup_script
        create_systemd_services
        install_api

        # Cleanup
        msg_info "Cleaning up..."
        silent apt-get autoremove -y
        silent apt-get autoclean -y
        msg_ok "Cleanup complete"

        # Start services
        start_services

        # Show completion (when run standalone in container)
        if [ "$INTERACTIVE" = "yes" ]; then
            show_completion_message
        fi

    else
        msg_error "This script must run on either a Proxmox host or inside an LXC container"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# SCRIPT ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    msg_error "This script must be run as root"
    exit 1
fi

# Execute main function
main "$@"
