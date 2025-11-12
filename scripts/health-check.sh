#!/usr/bin/env bash

# Waydroid LXC Health Check Script
# Monitors all components and provides detailed status
# Can be run manually or via cron for continuous monitoring

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/helper-functions.sh" ]; then
    source "${SCRIPT_DIR}/helper-functions.sh"
else
    # Minimal fallback if helper functions not available
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
HEALTH_CHECK_LOG="/var/log/waydroid-health.log"
ALERT_THRESHOLD=3  # Number of consecutive failures before alert
ALERT_FILE="/var/run/waydroid-health-failures"

# Initialize failure counter
if [ ! -f "$ALERT_FILE" ]; then
    echo "0" > "$ALERT_FILE"
fi

# Health check results
OVERALL_HEALTH="healthy"
ISSUES_FOUND=0

# Logging function
log_health() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$HEALTH_CHECK_LOG"
}

check_component() {
    local name="$1"
    local test_cmd="$2"
    local critical="${3:-no}"

    if bash -c "$test_cmd" &>/dev/null; then
        echo -e "${GN}✓${CL} $name: OK"
        log_health "$name: OK"
        return 0
    else
        if [ "$critical" = "yes" ]; then
            echo -e "${RD}✗${CL} $name: FAILED (CRITICAL)"
            log_health "$name: FAILED (CRITICAL)"
            OVERALL_HEALTH="critical"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        else
            echo -e "${YW}!${CL} $name: WARNING"
            log_health "$name: WARNING"
            if [ "$OVERALL_HEALTH" != "critical" ]; then
                OVERALL_HEALTH="degraded"
            fi
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
        return 1
    fi
}

echo -e "${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}  Waydroid LXC Health Check${CL}"
echo -e "${GN}  $(date '+%Y-%m-%d %H:%M:%S')${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

# 1. System Resources
echo -e "${BL}[1/10] System Resources${CL}"
CPU_THRESHOLD=$(($(nproc) * 2))
check_component "CPU Load" "[ \$(awk '{print \$1}' /proc/loadavg | cut -d. -f1) -lt $CPU_THRESHOLD ]"
check_component "Memory Available" "[ \$(free -m | awk 'NR==2{print \$7}') -gt 256 ]" "yes"
check_component "Disk Space" "[ \$(df -h / | awk 'NR==2{print \$5}' | tr -d '%') -lt 90 ]" "yes"
echo ""

# 2. Kernel Modules
echo -e "${BL}[2/10] Kernel Modules${CL}"
check_component "binder_linux" "lsmod | grep -q binder_linux" "yes"
check_component "ashmem_linux" "lsmod | grep -q ashmem_linux" "yes"
echo ""

# 3. GPU Access (if not software rendering)
echo -e "${BL}[3/10] GPU Devices${CL}"
if [ -d /dev/dri ]; then
    check_component "/dev/dri/card0" "[ -e /dev/dri/card0 ]"
    check_component "/dev/dri/renderD128" "[ -e /dev/dri/renderD128 ]"
    check_component "GPU Permissions" "[ -r /dev/dri/card0 ] && [ -w /dev/dri/card0 ]"
else
    echo -e "${YW}!${CL} GPU devices not available (software rendering mode)"
fi
echo ""

# 4. Waydroid Installation
echo -e "${BL}[4/10] Waydroid${CL}"
check_component "Waydroid Binary" "command -v waydroid" "yes"
check_component "Waydroid Initialized" "[ -d /var/lib/waydroid/overlay ]" "yes"
check_component "Waydroid Images" "[ -f /var/lib/waydroid/waydroid.cfg ]"
echo ""

# 5. Waydroid Services
echo -e "${BL}[5/10] Waydroid Services${CL}"
check_component "Container Service" "systemctl is-active --quiet waydroid-container.service"
check_component "Session Running" "pgrep -f 'waydroid session' || waydroid status | grep -q RUNNING"
echo ""

# 6. Wayland Compositor
echo -e "${BL}[6/10] Wayland Compositor${CL}"
check_component "Sway Installed" "command -v sway" "yes"
check_component "Sway Running" "pgrep -x sway"
check_component "Wayland Display" "[ -n \"\$WAYLAND_DISPLAY\" ] || [ -e /run/user/0/wayland-0 ]"
echo ""

# 7. VNC Server
echo -e "${BL}[7/10] VNC Server${CL}"
check_component "WayVNC Installed" "command -v wayvnc" "yes"
check_component "WayVNC Running" "pgrep -f wayvnc"
check_component "VNC Port Open" "netstat -tuln | grep -q ':5900 '"
check_component "VNC Config" "[ -f /root/.config/wayvnc/config ]"
echo ""

# 8. API Server
echo -e "${BL}[8/10] API Server${CL}"
check_component "API Script" "[ -f /usr/local/bin/waydroid-api.py ]" "yes"
check_component "API Service" "systemctl is-active --quiet waydroid-api.service"
check_component "API Port Open" "netstat -tuln | grep -q ':8080 '"
check_component "API Responding" "curl -s -m 5 http://localhost:8080/health | grep -q healthy"
echo ""

# 9. Network Connectivity
echo -e "${BL}[9/10] Network${CL}"
check_component "Internet Connectivity" "ping -c 1 -W 2 8.8.8.8"
check_component "DNS Resolution" "host waydro.id"
check_component "Container IP" "hostname -I | grep -q '[0-9]'"
echo ""

# 10. Logs and Errors
echo -e "${BL}[10/10] Recent Errors${CL}"
if [ -f /var/log/waydroid-api.log ]; then
    recent_errors=$(tail -n 100 /var/log/waydroid-api.log 2>/dev/null | grep -c "ERROR" || echo "0")
    if [ "$recent_errors" -gt 10 ]; then
        echo -e "${YW}!${CL} API Errors: $recent_errors errors in recent logs"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    else
        echo -e "${GN}✓${CL} API Errors: $recent_errors recent errors (acceptable)"
    fi
else
    echo -e "${YW}!${CL} API log file not found"
fi

journal_errors=$(journalctl -u waydroid-container.service --since "10 minutes ago" 2>/dev/null | grep -c "error" || echo "0")
if [ "$journal_errors" -gt 5 ]; then
    echo -e "${YW}!${CL} Waydroid Errors: $journal_errors errors in last 10 minutes"
else
    echo -e "${GN}✓${CL} Waydroid Errors: $journal_errors recent errors (acceptable)"
fi
echo ""

# Overall Status
echo -e "${GN}═══════════════════════════════════════════════${CL}"
if [ "$OVERALL_HEALTH" = "healthy" ]; then
    echo -e "${GN}✓ Overall Status: HEALTHY${CL}"
    echo "0" > "$ALERT_FILE"
    EXIT_CODE=0
elif [ "$OVERALL_HEALTH" = "degraded" ]; then
    echo -e "${YW}! Overall Status: DEGRADED${CL}"
    echo -e "  Issues found: $ISSUES_FOUND"
    (
        flock -x 200
        current_failures=$(cat "$ALERT_FILE")
        echo $((current_failures + 1)) > "$ALERT_FILE"
    ) 200>"$ALERT_FILE.lock"
    EXIT_CODE=1
else
    echo -e "${RD}✗ Overall Status: CRITICAL${CL}"
    echo -e "  Critical issues found: $ISSUES_FOUND"
    (
        flock -x 200
        current_failures=$(cat "$ALERT_FILE")
        echo $((current_failures + 1)) > "$ALERT_FILE"
    ) 200>"$ALERT_FILE.lock"
    EXIT_CODE=2
fi
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

# Check if we need to alert
(
    flock -s 200
    current_failures=$(cat "$ALERT_FILE")
    if [ "$current_failures" -ge "$ALERT_THRESHOLD" ]; then
        log_health "ALERT: $current_failures consecutive health check failures!"
        if [ -f /usr/local/bin/waydroid-alert.sh ]; then
            /usr/local/bin/waydroid-alert.sh "Health check failed $current_failures times"
        fi
    fi
) 200<"$ALERT_FILE.lock"

# Output quick status for prometheus/monitoring
cat > /var/run/waydroid-health-status.json <<EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "status": "$OVERALL_HEALTH",
    "issues_count": $ISSUES_FOUND,
    "consecutive_failures": $current_failures
}
EOF

exit $EXIT_CODE
