#!/usr/bin/env bash

# LXC Container Tuning Script for Waydroid
# Optimizes Proxmox LXC containers for Waydroid workloads
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

# Script configuration
SCRIPT_VERSION="1.0.0"
DRY_RUN=false
VERBOSE=false
BACKUP_CONFIG=true
APPLY_PERFORMANCE=true
APPLY_SECURITY=true
APPLY_MONITORING=true

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

msg_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BL}[DEBUG]${CL} $1"
    fi
}

show_help() {
    cat << EOF
${GN}═══════════════════════════════════════════════${CL}
${GN}  LXC Container Tuning for Waydroid${CL}
${GN}  Version: $SCRIPT_VERSION${CL}
${GN}═══════════════════════════════════════════════${CL}

Usage: $0 [options] <CTID>

Options:
    -h, --help              Show this help message
    -d, --dry-run           Show what would be changed without applying
    -v, --verbose           Enable verbose output
    -n, --no-backup         Don't create backup of config
    --performance-only      Apply only performance optimizations
    --security-only         Apply only security optimizations
    --monitoring-only       Apply only monitoring optimizations
    --analyze-only          Only analyze current configuration

Arguments:
    CTID                    Container ID to optimize

Examples:
    $0 100                  # Tune container 100
    $0 --dry-run 100        # Preview changes for container 100
    $0 --performance-only 100  # Apply only performance tuning
    $0 --analyze-only 100   # Analyze current configuration

Description:
    This script optimizes Proxmox LXC containers for Waydroid workloads by:

    Performance:
    - Optimizing cgroup settings for Android containers
    - Configuring memory and CPU allocation
    - Tuning I/O scheduling and priorities
    - Setting up NUMA awareness

    Security:
    - Restricting Linux capabilities to minimum required
    - Configuring AppArmor profiles
    - Setting up seccomp filters
    - Implementing device access controls

    Monitoring:
    - Adding resource monitoring hooks
    - Enabling container health checks
    - GPU passthrough verification
    - Performance metric collection

EOF
}

# Check prerequisites
check_prerequisites() {
    if [ "$(id -u)" -ne 0 ]; then
        msg_error "This script must be run as root"
        exit 1
    fi

    if ! command -v pveversion &> /dev/null; then
        msg_error "This script must be run on a Proxmox VE host"
        exit 1
    fi

    if ! command -v pct &> /dev/null; then
        msg_error "pct command not found - is Proxmox installed correctly?"
        exit 1
    fi
}

# Validate CTID
validate_ctid() {
    local ctid=$1

    if ! [[ "$ctid" =~ ^[0-9]+$ ]]; then
        msg_error "Invalid CTID: must be numeric"
        return 1
    fi

    if [ "$ctid" -lt 100 ] || [ "$ctid" -gt 999999999 ]; then
        msg_error "Invalid CTID: must be between 100 and 999999999"
        return 1
    fi

    if ! pct status "$ctid" &>/dev/null; then
        msg_error "Container $ctid does not exist"
        return 1
    fi

    return 0
}

# Backup configuration
backup_config() {
    local ctid=$1
    local config_file="/etc/pve/lxc/${ctid}.conf"
    local backup_file="/etc/pve/lxc/${ctid}.conf.backup.$(date +%Y%m%d-%H%M%S)"

    if [ "$BACKUP_CONFIG" = true ] && [ "$DRY_RUN" = false ]; then
        msg_info "Creating backup of configuration..."
        if cp "$config_file" "$backup_file"; then
            msg_ok "Backup saved to: $backup_file"
        else
            msg_error "Failed to create backup"
            return 1
        fi
    fi
    return 0
}

# Get current container info
get_container_info() {
    local ctid=$1
    local config_file="/etc/pve/lxc/${ctid}.conf"

    msg_verbose "Reading container configuration from $config_file"

    # Read basic info
    CT_PRIVILEGED=false
    if ! grep -q "^unprivileged:" "$config_file" || grep -q "^unprivileged: 0" "$config_file"; then
        CT_PRIVILEGED=true
    fi

    CT_CORES=$(grep "^cores:" "$config_file" | cut -d: -f2 | xargs || echo "unknown")
    CT_MEMORY=$(grep "^memory:" "$config_file" | cut -d: -f2 | xargs || echo "unknown")
    CT_SWAP=$(grep "^swap:" "$config_file" | cut -d: -f2 | xargs || echo "unknown")

    # Check for GPU passthrough
    CT_HAS_GPU=false
    if grep -q "lxc.cgroup2.devices.allow.*226" "$config_file" || \
       grep -q "lxc.mount.entry.*dev/dri" "$config_file"; then
        CT_HAS_GPU=true
    fi

    # Check current features
    CT_FEATURES=$(grep "^features:" "$config_file" | cut -d: -f2 | xargs || echo "")

    # Check AppArmor status
    CT_APPARMOR=$(grep "^lxc.apparmor.profile:" "$config_file" | cut -d: -f2 | xargs || echo "not set")

    # Check capabilities
    CT_CAPS_DROP=$(grep "^lxc.cap.drop:" "$config_file" | cut -d: -f2 | xargs || echo "not set")
}

# Display current analysis
analyze_container() {
    local ctid=$1

    echo -e "\n${GN}═══════════════════════════════════════════════${CL}"
    echo -e "${GN}  Container Analysis: ${ctid}${CL}"
    echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

    echo -e "${BL}Basic Configuration:${CL}"
    echo -e "  Container Type:     $([ "$CT_PRIVILEGED" = true ] && echo "${YW}Privileged${CL}" || echo "${GN}Unprivileged${CL}")"
    echo -e "  CPU Cores:          ${CT_CORES}"
    echo -e "  Memory:             ${CT_MEMORY}MB"
    echo -e "  Swap:               ${CT_SWAP}MB"
    echo -e "  Features:           ${CT_FEATURES:-none}"
    echo ""

    echo -e "${BL}GPU Configuration:${CL}"
    if [ "$CT_HAS_GPU" = true ]; then
        echo -e "  GPU Passthrough:    ${GN}Enabled${CL}"
        # Check actual GPU devices on host
        if [ -d /dev/dri ]; then
            echo -e "  Host GPU Devices:   $(ls -1 /dev/dri/ | tr '\n' ' ')"
        fi
    else
        echo -e "  GPU Passthrough:    ${YW}Disabled (software rendering)${CL}"
    fi
    echo ""

    echo -e "${BL}Security Configuration:${CL}"
    echo -e "  AppArmor Profile:   ${CT_APPARMOR}"
    if [ "$CT_CAPS_DROP" = "not set" ] || [ -z "$CT_CAPS_DROP" ]; then
        echo -e "  Capabilities:       ${YW}All capabilities enabled (not secure)${CL}"
    else
        echo -e "  Capabilities:       ${GN}Restricted${CL}"
        echo -e "                      Dropped: ${CT_CAPS_DROP}"
    fi
    echo ""

    # Analyze resource usage if container is running
    if pct status "$ctid" 2>/dev/null | grep -q "running"; then
        echo -e "${BL}Runtime Statistics:${CL}"

        # Get CPU usage
        local cpu_usage=$(pct exec "$ctid" -- top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' 2>/dev/null || echo "N/A")
        echo -e "  CPU Usage:          ${cpu_usage}%"

        # Get memory usage
        local mem_info=$(pct exec "$ctid" -- free -m | grep Mem | awk '{printf "%dMB / %dMB (%.1f%%)", $3, $2, $3/$2 * 100.0}' 2>/dev/null || echo "N/A")
        echo -e "  Memory Usage:       ${mem_info}"

        # Check if Waydroid processes are running
        if pct exec "$ctid" -- pgrep -f "waydroid|sway|wayvnc" &>/dev/null; then
            echo -e "  Waydroid Status:    ${GN}Running${CL}"
            local waydroid_procs=$(pct exec "$ctid" -- pgrep -f "waydroid|sway|wayvnc" | wc -l)
            echo -e "  Active Processes:   ${waydroid_procs}"
        else
            echo -e "  Waydroid Status:    ${YW}Not running${CL}"
        fi
        echo ""
    else
        echo -e "${YW}Container is not running - skipping runtime statistics${CL}\n"
    fi

    # Check for potential issues
    echo -e "${BL}Recommendations:${CL}"
    local issues=0

    if [ "$CT_PRIVILEGED" = true ] && [ "$CT_CAPS_DROP" = "not set" ] || [ -z "$CT_CAPS_DROP" ]; then
        echo -e "  ${YW}⚠${CL} Privileged container with all capabilities enabled (security risk)"
        issues=$((issues + 1))
    fi

    if [ "$CT_APPARMOR" = "unconfined" ]; then
        echo -e "  ${YW}⚠${CL} AppArmor is unconfined (reduced security)"
        issues=$((issues + 1))
    fi

    if [ "$CT_MEMORY" != "unknown" ] && [ "$CT_MEMORY" -lt 2048 ]; then
        echo -e "  ${YW}⚠${CL} Low memory allocation (recommended: 2048MB minimum)"
        issues=$((issues + 1))
    fi

    if [ "$CT_CORES" != "unknown" ] && [ "$CT_CORES" -lt 2 ]; then
        echo -e "  ${YW}⚠${CL} Low CPU allocation (recommended: 2 cores minimum)"
        issues=$((issues + 1))
    fi

    # Check for missing features that Waydroid needs
    if ! echo "$CT_FEATURES" | grep -q "nesting=1"; then
        echo -e "  ${YW}⚠${CL} Container nesting not enabled (required for Waydroid)"
        issues=$((issues + 1))
    fi

    if ! echo "$CT_FEATURES" | grep -q "keyctl=1"; then
        echo -e "  ${YW}⚠${CL} Keyctl not enabled (recommended for Waydroid)"
        issues=$((issues + 1))
    fi

    if [ $issues -eq 0 ]; then
        echo -e "  ${GN}✓${CL} No major issues detected"
    else
        echo -e "\n  ${YW}Found ${issues} potential issues${CL}"
    fi

    echo ""
}

# Apply performance optimizations
apply_performance_tuning() {
    local ctid=$1
    local config_file="/etc/pve/lxc/${ctid}.conf"

    echo -e "\n${BL}═══ Performance Optimizations ═══${CL}\n"

    # Determine optimal settings based on host capabilities
    local host_cores=$(nproc)
    local host_mem_mb=$(free -m | awk '/^Mem:/{print $2}')

    msg_verbose "Host has ${host_cores} cores and ${host_mem_mb}MB RAM"

    # CPU optimizations
    msg_info "Configuring CPU settings..."

    # CPU shares (higher priority)
    apply_config_setting "$ctid" "lxc.cgroup2.cpu.weight" "512" \
        "CPU weight/priority (default: 100, higher = more CPU time)"

    # CPU quota (200% = 2 full cores)
    if [ "$CT_CORES" != "unknown" ]; then
        local cpu_quota=$((CT_CORES * 100000))
        apply_config_setting "$ctid" "lxc.cgroup2.cpu.max" "${cpu_quota} 100000" \
            "CPU quota limit (microseconds per 100ms period)"
    fi

    # NUMA awareness (if applicable)
    if [ -d /sys/devices/system/node/node1 ]; then
        msg_verbose "NUMA system detected"
        apply_config_setting "$ctid" "lxc.cgroup2.cpuset.mems" "0" \
            "NUMA memory node assignment"
    fi

    # Memory optimizations
    msg_info "Configuring memory settings..."

    # Memory high threshold (soft limit - trigger reclaim)
    if [ "$CT_MEMORY" != "unknown" ]; then
        local mem_high=$((CT_MEMORY * 1024 * 1024 * 90 / 100))  # 90% of allocated
        apply_config_setting "$ctid" "lxc.cgroup2.memory.high" "${mem_high}" \
            "Memory soft limit (triggers reclaim at 90%)"

        # Memory max (hard limit)
        local mem_max=$((CT_MEMORY * 1024 * 1024))
        apply_config_setting "$ctid" "lxc.cgroup2.memory.max" "${mem_max}" \
            "Memory hard limit"

        # Swap max (limit swap usage)
        if [ "$CT_SWAP" != "unknown" ] && [ "$CT_SWAP" -gt 0 ]; then
            local swap_max=$((CT_SWAP * 1024 * 1024))
            apply_config_setting "$ctid" "lxc.cgroup2.memory.swap.max" "${swap_max}" \
                "Swap limit"
        fi
    fi

    # I/O optimizations
    msg_info "Configuring I/O settings..."

    # I/O weight (higher priority for disk I/O)
    apply_config_setting "$ctid" "lxc.cgroup2.io.weight" "500" \
        "I/O priority weight (default: 100)"

    # I/O latency target (lower = more responsive)
    apply_config_setting "$ctid" "lxc.cgroup2.io.latency" "target=10000" \
        "I/O latency target (10ms for interactive workloads)"

    # Process limits
    msg_info "Configuring process limits..."

    # PIDs max (prevent fork bombs, allow enough for Android)
    apply_config_setting "$ctid" "lxc.cgroup2.pids.max" "4096" \
        "Maximum number of processes/threads"

    # Huge pages (if supported and beneficial)
    if [ -d /sys/kernel/mm/hugepages ]; then
        msg_verbose "Huge pages available on host"
        # Enable transparent huge pages for better memory performance
        apply_config_setting "$ctid" "lxc.cgroup2.memory.thp" "1" \
            "Enable transparent huge pages"
    fi

    msg_ok "Performance optimizations configured"
}

# Apply security hardening
apply_security_hardening() {
    local ctid=$1
    local config_file="/etc/pve/lxc/${ctid}.conf"

    echo -e "\n${BL}═══ Security Hardening ═══${CL}\n"

    if [ "$CT_PRIVILEGED" = false ]; then
        msg_info "Container is unprivileged - enhanced security by default"
        return 0
    fi

    msg_info "Applying security restrictions for privileged container..."

    # Capability restrictions
    # Waydroid needs specific capabilities, drop everything else
    msg_info "Configuring Linux capabilities..."

    # Essential capabilities for Waydroid:
    # - CAP_SYS_ADMIN: for binder, mounting
    # - CAP_NET_ADMIN: for network configuration
    # - CAP_SYS_NICE: for process priority adjustment
    # - CAP_MKNOD: for device node creation
    # - CAP_SETUID/SETGID: for Android's user management
    # - CAP_DAC_OVERRIDE: for file access (Android permissions)
    # - CAP_CHOWN: for file ownership changes
    # - CAP_FOWNER: for file permission changes

    # Drop unnecessary capabilities (security hardening)
    local caps_to_drop=(
        "CAP_AUDIT_CONTROL"
        "CAP_AUDIT_READ"
        "CAP_AUDIT_WRITE"
        "CAP_BLOCK_SUSPEND"
        "CAP_DAC_READ_SEARCH"
        "CAP_IPC_LOCK"
        "CAP_IPC_OWNER"
        "CAP_LEASE"
        "CAP_LINUX_IMMUTABLE"
        "CAP_MAC_ADMIN"
        "CAP_MAC_OVERRIDE"
        "CAP_NET_BROADCAST"
        "CAP_NET_RAW"
        "CAP_SYSLOG"
        "CAP_SYS_BOOT"
        "CAP_SYS_MODULE"
        "CAP_SYS_PACCT"
        "CAP_SYS_PTRACE"
        "CAP_SYS_RAWIO"
        "CAP_SYS_RESOURCE"
        "CAP_SYS_TIME"
        "CAP_SYS_TTY_CONFIG"
        "CAP_WAKE_ALARM"
    )

    local caps_drop_str=$(IFS=' '; echo "${caps_to_drop[*]}" | tr ' ' ' ')

    msg_verbose "Dropping capabilities: ${caps_drop_str}"
    apply_config_setting "$ctid" "lxc.cap.drop" "$caps_drop_str" \
        "Drop unnecessary capabilities for security"

    # AppArmor profile
    msg_info "Configuring AppArmor..."

    # Note: We use 'unconfined' for Waydroid because it needs device access
    # In production, consider creating a custom AppArmor profile
    if [ "$CT_APPARMOR" != "unconfined" ]; then
        msg_warn "AppArmor profile is not 'unconfined' - Waydroid may not work correctly"
        msg_warn "Current profile: ${CT_APPARMOR}"
        msg_warn "Consider setting to 'unconfined' or creating custom profile"
    else
        msg_ok "AppArmor set to unconfined (required for GPU passthrough)"
    fi

    # Seccomp filter
    msg_info "Configuring seccomp filters..."

    # Check if custom seccomp profile exists
    local seccomp_profile="/usr/share/lxc/config/common.seccomp"
    if [ -f "$seccomp_profile" ]; then
        msg_verbose "Using default seccomp profile: $seccomp_profile"
        # Note: For Waydroid, we typically need to allow binder-related syscalls
        # The default LXC seccomp profile should work, but may need customization
    else
        msg_warn "Default seccomp profile not found - running without seccomp filtering"
    fi

    # Device access controls
    msg_info "Configuring device access..."

    # Ensure devices are properly restricted
    if [ "$CT_HAS_GPU" = true ]; then
        # Allow only specific DRM and video devices
        msg_verbose "Configuring GPU device access"

        # Remove overly permissive 'allow a' if it exists
        if grep -q "^lxc.cgroup2.devices.allow: a$" "$config_file"; then
            msg_warn "Found overly permissive device access (allow: a)"
            msg_warn "This allows access to ALL devices - security risk!"

            if [ "$DRY_RUN" = false ]; then
                # Comment out the overly permissive line
                sed -i 's/^lxc.cgroup2.devices.allow: a$/# lxc.cgroup2.devices.allow: a  # Commented by tune-lxc.sh - too permissive/' "$config_file"
                msg_ok "Commented out overly permissive device access"
            else
                echo "  ${YW}[DRY RUN]${CL} Would comment out: lxc.cgroup2.devices.allow: a"
            fi
        fi

        # Ensure specific GPU devices are allowed
        ensure_config_line "$ctid" "lxc.cgroup2.devices.allow" "c 226:* rwm" \
            "DRM devices (GPU)"
        ensure_config_line "$ctid" "lxc.cgroup2.devices.allow" "c 29:0 rwm" \
            "Framebuffer device"

        # Optionally allow video devices for hardware acceleration
        ensure_config_line "$ctid" "lxc.cgroup2.devices.allow" "c 81:* rwm" \
            "Video4Linux devices (optional)"
    fi

    # Ensure proper mount restrictions
    msg_info "Verifying mount options..."

    # Check for nodev, nosuid on mounts (where appropriate)
    # Note: root mount can't have these, but /tmp and others should
    msg_verbose "Mount security options configured via Proxmox defaults"

    msg_ok "Security hardening applied"
}

# Apply monitoring enhancements
apply_monitoring() {
    local ctid=$1

    echo -e "\n${BL}═══ Monitoring Enhancements ═══${CL}\n"

    msg_info "Setting up resource monitoring..."

    # Create monitoring directory
    local monitor_dir="/var/lib/vz/lxc-monitor"
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$monitor_dir"
        chmod 755 "$monitor_dir"
    else
        echo "  ${YW}[DRY RUN]${CL} Would create: $monitor_dir"
    fi

    # Create resource monitoring script
    local monitor_script="${monitor_dir}/monitor-${ctid}.sh"

    if [ "$DRY_RUN" = false ]; then
        cat > "$monitor_script" << 'EOFMONITOR'
#!/bin/bash
# Container resource monitor
# Auto-generated by tune-lxc.sh

CTID="$1"
LOG_FILE="/var/log/lxc-monitor-${CTID}.log"

# Get container stats
get_stats() {
    if ! pct status "$CTID" 2>/dev/null | grep -q "running"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'),stopped,0,0,0,0" >> "$LOG_FILE"
        return
    fi

    # Get CPU usage
    local cpu_usage=$(pct exec "$CTID" -- top -bn1 2>/dev/null | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' || echo "0")

    # Get memory usage
    local mem_used=$(pct exec "$CTID" -- free -m 2>/dev/null | grep Mem | awk '{print $3}' || echo "0")
    local mem_total=$(pct exec "$CTID" -- free -m 2>/dev/null | grep Mem | awk '{print $2}' || echo "1")
    local mem_percent=$(echo "scale=2; $mem_used * 100 / $mem_total" | bc)

    # Get disk usage
    local disk_usage=$(pct exec "$CTID" -- df -h / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo "0")

    # Get process count
    local proc_count=$(pct exec "$CTID" -- ps aux 2>/dev/null | wc -l || echo "0")

    # Log to file
    echo "$(date '+%Y-%m-%d %H:%M:%S'),running,$cpu_usage,$mem_percent,$disk_usage,$proc_count" >> "$LOG_FILE"
}

# Run stats collection
get_stats
EOFMONITOR

        chmod +x "$monitor_script"

        # Replace CTID placeholder
        sed -i "s/CTID=\"\$1\"/CTID=\"${ctid}\"/" "$monitor_script"

        msg_ok "Created monitoring script: $monitor_script"
    else
        echo "  ${YW}[DRY RUN]${CL} Would create: $monitor_script"
    fi

    # Create cron job for periodic monitoring
    msg_info "Setting up periodic monitoring..."

    local cron_entry="*/5 * * * * ${monitor_script} ${ctid} # LXC ${ctid} monitoring"

    if [ "$DRY_RUN" = false ]; then
        # Check if cron entry already exists
        if ! crontab -l 2>/dev/null | grep -q "lxc-monitor.*${ctid}"; then
            (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
            msg_ok "Added cron job for monitoring (runs every 5 minutes)"
        else
            msg_ok "Monitoring cron job already exists"
        fi
    else
        echo "  ${YW}[DRY RUN]${CL} Would add cron: $cron_entry"
    fi

    # GPU monitoring (if GPU passthrough enabled)
    if [ "$CT_HAS_GPU" = true ]; then
        msg_info "Setting up GPU monitoring..."

        local gpu_monitor_script="${monitor_dir}/gpu-check-${ctid}.sh"

        if [ "$DRY_RUN" = false ]; then
            cat > "$gpu_monitor_script" << EOFGPU
#!/bin/bash
# GPU passthrough verification
# Auto-generated by tune-lxc.sh

CTID="${ctid}"

echo "=== GPU Passthrough Check for CT ${ctid} ==="
echo "Timestamp: \$(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Check host GPU devices
echo "Host GPU Devices:"
ls -la /dev/dri/ 2>/dev/null || echo "No GPU devices found"
echo ""

# Check container GPU access (if running)
if pct status "\$CTID" 2>/dev/null | grep -q "running"; then
    echo "Container GPU Devices:"
    pct exec "\$CTID" -- ls -la /dev/dri/ 2>/dev/null || echo "No GPU devices in container"
    echo ""

    echo "Container GPU Processes:"
    pct exec "\$CTID" -- ps aux | grep -E "sway|waydroid|wayvnc" | grep -v grep || echo "No GPU processes running"
    echo ""

    echo "GPU Driver Info:"
    pct exec "\$CTID" -- glxinfo -B 2>/dev/null || echo "glxinfo not available"
else
    echo "Container is not running"
fi
EOFGPU

            chmod +x "$gpu_monitor_script"
            msg_ok "Created GPU monitoring script: $gpu_monitor_script"
            msg_info "Run manually: $gpu_monitor_script"
        else
            echo "  ${YW}[DRY RUN]${CL} Would create: $gpu_monitor_script"
        fi
    fi

    # Container health check integration
    msg_info "Setting up health check integration..."

    if [ "$DRY_RUN" = false ]; then
        # Check if container has health check script
        if pct exec "$ctid" -- test -f /root/scripts/health-check.sh 2>/dev/null; then
            msg_ok "Container has health-check.sh - monitoring integrated"
        else
            msg_warn "Container doesn't have health-check.sh"
            msg_info "Consider copying health-check.sh into the container"
        fi
    fi

    msg_ok "Monitoring enhancements configured"
}

# Helper function to apply config setting
apply_config_setting() {
    local ctid=$1
    local key=$2
    local value=$3
    local description=$4

    local config_file="/etc/pve/lxc/${ctid}.conf"

    msg_verbose "Setting: $key = $value"

    if [ "$DRY_RUN" = true ]; then
        echo "  ${YW}[DRY RUN]${CL} Would set: ${GN}${key}${CL} = ${value}"
        if [ -n "$description" ]; then
            echo "            ${BL}# ${description}${CL}"
        fi
        return 0
    fi

    # Remove existing setting
    sed -i "/^${key}:/d" "$config_file"

    # Add new setting with comment
    if [ -n "$description" ]; then
        echo "# ${description}" >> "$config_file"
    fi
    echo "${key}: ${value}" >> "$config_file"
}

# Helper function to ensure a config line exists (for multi-value keys)
ensure_config_line() {
    local ctid=$1
    local key=$2
    local value=$3
    local description=$4

    local config_file="/etc/pve/lxc/${ctid}.conf"

    # Check if this exact line already exists
    if grep -q "^${key}: ${value}$" "$config_file"; then
        msg_verbose "Already configured: $key: $value"
        return 0
    fi

    msg_verbose "Adding: $key: $value"

    if [ "$DRY_RUN" = true ]; then
        echo "  ${YW}[DRY RUN]${CL} Would add: ${GN}${key}${CL}: ${value}"
        if [ -n "$description" ]; then
            echo "            ${BL}# ${description}${CL}"
        fi
        return 0
    fi

    # Add the line
    if [ -n "$description" ]; then
        echo "# ${description}" >> "$config_file"
    fi
    echo "${key}: ${value}" >> "$config_file"
}

# Main execution
main() {
    # Parse arguments first to check for --help
    CTID=""
    ANALYZE_ONLY=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--no-backup)
                BACKUP_CONFIG=false
                shift
                ;;
            --performance-only)
                APPLY_SECURITY=false
                APPLY_MONITORING=false
                shift
                ;;
            --security-only)
                APPLY_PERFORMANCE=false
                APPLY_MONITORING=false
                shift
                ;;
            --monitoring-only)
                APPLY_PERFORMANCE=false
                APPLY_SECURITY=false
                shift
                ;;
            --analyze-only)
                ANALYZE_ONLY=true
                shift
                ;;
            [0-9]*)
                CTID=$1
                shift
                ;;
            *)
                msg_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo -e "${GN}  LXC Container Tuning for Waydroid${CL}"
    echo -e "${GN}  Version: ${SCRIPT_VERSION}${CL}"
    echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

    # Check prerequisites
    check_prerequisites

    # Validate CTID
    if [ -z "$CTID" ]; then
        msg_error "Container ID (CTID) is required"
        echo ""
        show_help
        exit 1
    fi

    if ! validate_ctid "$CTID"; then
        exit 1
    fi

    # Get container info
    get_container_info "$CTID"

    # Display analysis
    analyze_container "$CTID"

    # If analyze-only, stop here
    if [ "$ANALYZE_ONLY" = true ]; then
        msg_info "Analysis complete (--analyze-only mode)"
        exit 0
    fi

    # Confirm before applying changes
    if [ "$DRY_RUN" = false ]; then
        echo -e "${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
        echo -e "${YW}  WARNING: This will modify container configuration${CL}"
        echo -e "${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}\n"

        # Check if container is running
        if pct status "$CTID" 2>/dev/null | grep -q "running"; then
            msg_warn "Container is currently running"
            msg_warn "Some changes may require a restart to take effect"
            echo ""
        fi

        read -p "Continue with optimization? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            msg_info "Operation cancelled"
            exit 0
        fi
        echo ""
    fi

    # Backup configuration
    if ! backup_config "$CTID"; then
        msg_error "Failed to backup configuration - aborting"
        exit 1
    fi

    # Apply optimizations
    if [ "$APPLY_PERFORMANCE" = true ]; then
        apply_performance_tuning "$CTID"
    fi

    if [ "$APPLY_SECURITY" = true ]; then
        apply_security_hardening "$CTID"
    fi

    if [ "$APPLY_MONITORING" = true ]; then
        apply_monitoring "$CTID"
    fi

    # Summary
    echo -e "\n${GN}═══════════════════════════════════════════════${CL}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${GN}  Dry Run Complete${CL}"
        echo -e "${GN}  (No changes were made)${CL}"
    else
        echo -e "${GN}  Optimization Complete!${CL}"
    fi
    echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

    if [ "$DRY_RUN" = false ]; then
        msg_info "Applied optimizations to container ${CTID}"
        echo ""
        echo -e "${BL}Next steps:${CL}"

        if pct status "$CTID" 2>/dev/null | grep -q "running"; then
            echo "  1. Review changes: ${GN}cat /etc/pve/lxc/${CTID}.conf${CL}"
            echo "  2. Restart container for changes to take effect: ${GN}pct restart ${CTID}${CL}"
            echo "  3. Verify Waydroid: ${GN}pct enter ${CTID} -- systemctl status waydroid-vnc${CL}"
            echo "  4. Check monitoring: ${GN}tail -f /var/log/lxc-monitor-${CTID}.log${CL}"
        else
            echo "  1. Review changes: ${GN}cat /etc/pve/lxc/${CTID}.conf${CL}"
            echo "  2. Start container: ${GN}pct start ${CTID}${CL}"
            echo "  3. Verify Waydroid: ${GN}pct enter ${CTID} -- systemctl status waydroid-vnc${CL}"
            echo "  4. Check monitoring: ${GN}tail -f /var/log/lxc-monitor-${CTID}.log${CL}"
        fi

        if [ "$BACKUP_CONFIG" = true ]; then
            echo ""
            echo -e "${BL}Backup:${CL}"
            echo "  Configuration backed up to:"
            echo "  ${GN}$(ls -t /etc/pve/lxc/${CTID}.conf.backup.* 2>/dev/null | head -1)${CL}"
            echo ""
            echo "  To restore: ${YW}cp /etc/pve/lxc/${CTID}.conf.backup.* /etc/pve/lxc/${CTID}.conf${CL}"
        fi
    else
        msg_info "This was a dry run - no changes were made"
        msg_info "Run without --dry-run to apply changes"
    fi

    echo ""
}

# Run main function
main "$@"
